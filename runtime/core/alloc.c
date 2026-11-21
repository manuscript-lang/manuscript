/* The runtime's allocator: mimalloc (runtime/third_party/mimalloc) behind the msrt_* names the compiled program and
 * the runtime call. mimalloc keeps one heap per thread and returns a block freed by another thread to its owner, so
 * the claim and release of a heap are bookkeeping only. This file adds what the runtime wants on top: the out-of-memory
 * report, the counters the counting runtime and the gates read, and the allocation sampler the profiler hooks.
 *
 * Counters: `requested` is the allocations and bytes asked for since start (per thread, folded into `released` when a
 * thread releases its heap). With MS_ALLOC_STATS every block is counted live as well, by the size class mimalloc
 * gave it, so a leak report names the blocks.
 */
#include "alloc.h"

#include <stdatomic.h>

#include <mimalloc.h>
#include <mimalloc-stats.h>

#define LIKELY(x) __builtin_expect(!!(x), 1)
#define UNLIKELY(x) __builtin_expect(!!(x), 0)
#define COLD __attribute__((cold, noinline))

typedef struct Counters {
    uint64_t requested[2];
    uint64_t sample_at; /* the allocation count at which the profiler takes its next sample */
} Counters;

static _Thread_local Counters mine = {.sample_at = UINT64_MAX};
static _Atomic uint64_t released[2];
static int64_t (*sampler)(size_t);

/* ---- live blocks, counting runtime only ---- */

#ifdef MS_ALLOC_STATS
enum { BUCKETS = 48 };

static _Atomic int64_t live_all;
static _Atomic int64_t live_by_bucket[BUCKETS];

/* The bucket of a block of `usable` bytes: its size rounded up to a power of two (bucket 0 holds up to 16). */
static size_t bucket_of(size_t usable) {
    size_t bucket = 0;
    for (size_t limit = 16; limit < usable && bucket + 1 < BUCKETS; limit <<= 1) {
        bucket++;
    }
    return bucket;
}

static void live_add(void *p, int64_t delta) {
    atomic_fetch_add_explicit(&live_all, delta, memory_order_relaxed);
    atomic_fetch_add_explicit(&live_by_bucket[bucket_of(mi_usable_size(p))], delta, memory_order_relaxed);
}

int64_t msalloc_live_blocks(void) { return atomic_load_explicit(&live_all, memory_order_relaxed); }
int64_t msrt_heap_live_total(void) { return atomic_load_explicit(&live_all, memory_order_relaxed); }

size_t msrt_heap_live_by_size(size_t *sizes, int64_t *counts, size_t capacity) {
    size_t found = 0;
    for (size_t bucket = 0; bucket < BUCKETS && found < capacity; bucket++) {
        const int64_t count = atomic_load_explicit(&live_by_bucket[bucket], memory_order_relaxed);
        if (count != 0) {
            sizes[found] = (size_t)16 << bucket;
            counts[found++] = count;
        }
    }
    return found;
}
#else
static inline void live_add(void *p, int64_t delta) {
    (void)p;
    (void)delta;
}
int64_t msalloc_live_blocks(void) { return 0; }
int64_t msrt_heap_live_total(void) { return 0; }
size_t msrt_heap_live_by_size(size_t *sizes, int64_t *counts, size_t capacity) {
    if (capacity != 0) {
        sizes[0] = 0;
        counts[0] = 0;
    }
    return 0;
}
#endif

/* ---- the profiler's sampler ---- */

/* Hands the allocation profiler one sample and arms the next. */
COLD static void take_sample(size_t size) {
    mine.sample_at = UINT64_MAX; /* disarmed while the hook runs: it may allocate */
    const int64_t period = sampler != NULL ? sampler(size) : INT64_MAX;
    mine.sample_at = period >= INT64_MAX - (int64_t)mine.requested[0] ? UINT64_MAX : mine.requested[0] + (uint64_t)period;
}

void msrt_heap_sample_every(int64_t period, void *hook) {
    sampler = (int64_t (*)(size_t))hook;
    mine.sample_at = mine.requested[0] + (uint64_t)period;
}

static inline void note_request(size_t size) {
    mine.requested[0]++;
    mine.requested[1] += size;
    if (UNLIKELY(mine.requested[0] >= mine.sample_at)) {
        take_sample(size);
    }
}

/* ---- allocation ---- */

void *msrt_alloc(size_t size) {
    note_request(size);
    void *const p = mi_malloc(size);
    if (UNLIKELY(p == NULL)) {
        msalloc_oom(size);
    }
    live_add(p, 1);
    return p;
}

void *msrt_alloc_zeroed(size_t size) {
    note_request(size);
    void *const p = mi_zalloc(size);
    if (UNLIKELY(p == NULL)) {
        msalloc_oom(size);
    }
    live_add(p, 1);
    return p;
}

/* Resizes `p` without counting a request. */
static void *resize(void *p, size_t size) {
    live_add(p, -1);
    void *const grown = mi_realloc(p, size == 0 ? 1 : size);
    if (UNLIKELY(grown == NULL)) {
        msalloc_oom(size);
    }
    live_add(grown, 1);
    return grown;
}

void *msrt_realloc(void *p, size_t size) {
    if (p == NULL) {
        return msrt_alloc(size);
    }
    if (size > mi_usable_size(p)) {
        note_request(size); /* a growth is a request, as the ownership counts have always read it; a shrink is not */
    }
    return resize(p, size);
}

void msrt_free(void *p) {
    if (p == NULL) {
        return;
    }
    live_add(p, -1);
    mi_free(p);
}

size_t msrt_heap_usable_size(void *p) { return mi_usable_size(p); }

/* A block of `new_size` bytes holding the first bytes of `p`, which the caller shrinks: the block itself when the
 * smaller size would waste little, else a copy. */
void *msrt_heap_trim(void *p, size_t new_size) { return p == NULL ? msrt_alloc(new_size) : resize(p, new_size); }

/* ---- per-thread heaps and figures ---- */

void msrt_heap_claim(void) {}

/* A thread's counts outlive it: they join the totals the report reads. */
void msrt_heap_release(void) {
    atomic_fetch_add_explicit(&released[0], mine.requested[0], memory_order_relaxed);
    atomic_fetch_add_explicit(&released[1], mine.requested[1], memory_order_relaxed);
    mine.requested[0] = mine.requested[1] = 0;
    mine.sample_at = UINT64_MAX;
}

uint8_t msrt_heap_has(void) { return 1; }

/* out[0] bytes in use and out[1] bytes the allocator holds from the system, for the process. mimalloc counts a page's
 * blocks when the page fills or is collected and folds a thread's counts into the process figures only after some
 * churn, so the calling thread collects first (a normal collection: it frees nothing a program still holds). The
 * commit figure is per chunk. */
void msrt_heap_stats(int64_t *out) {
    mi_collect(false);
    mi_stats_t stats = {.size = sizeof stats, .version = MI_STAT_VERSION};
    size_t current_commit = 0;
    size_t peak_commit = 0;
    mi_process_info(NULL, NULL, NULL, NULL, NULL, &current_commit, &peak_commit, NULL);
    const int64_t committed = (int64_t)current_commit;
    const int64_t used = mi_stats_get(&stats) ? stats.malloc_normal.current + stats.malloc_huge.current : committed;
    out[0] = used;
    out[1] = committed;
}

/* out[0] allocations and out[1] bytes requested by the calling thread and by every thread that has
 * finished (released its heap). Threads still running are not included. */
void msrt_heap_requested(uint64_t *out) {
    out[0] = mine.requested[0] + atomic_load_explicit(&released[0], memory_order_relaxed);
    out[1] = mine.requested[1] + atomic_load_explicit(&released[1], memory_order_relaxed);
}

void ms_heap_requested_thread(uint64_t *out) {
    out[0] = mine.requested[0];
    out[1] = mine.requested[1];
}

void ms_heap_requested_restore(const uint64_t *saved) {
    mine.requested[0] = saved[0];
    mine.requested[1] = saved[1];
}

/* Starts the counters over: the program's main begins, so the counts a gate reads cover the program and not the
 * runtime's own start-up records (the main task and its stack region), which differ by platform. */
void msrt_heap_requested_reset(void) {
    mine.requested[0] = mine.requested[1] = 0;
    atomic_store_explicit(&released[0], 0, memory_order_relaxed);
    atomic_store_explicit(&released[1], 0, memory_order_relaxed);
}
