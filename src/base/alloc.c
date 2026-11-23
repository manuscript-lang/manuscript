/* Owns the allocator hook and the mimalloc default (see alloc.h). */
#include "base/alloc.h"

#include <mimalloc.h>
#include <stdatomic.h>
#ifdef MS_STATS
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#endif

#include "base/fatal.h"

/* The one other mutable global of base besides the fatal handler: set once before threads. */
static const MsAllocator *installed = NULL;

/* Whether any hook, observer or live-byte tracking is on. Without one the allocation functions are the counters and
 * the mimalloc call: no indirect call, no atomic add of a zero delta. */
#ifdef MS_STATS
static _Atomic bool hooked = true; /* the counting runtime tracks live blocks from the first allocation */
#else
static _Atomic bool hooked = false;
#endif
static void refresh_hooked(void);

static void *mimalloc_allocate(size_t size) {
  return mi_malloc(size);
}
static void *mimalloc_reallocate(void *block, size_t size) {
  return mi_realloc(block, size);
}
static void mimalloc_release(void *block) {
  mi_free(block);
}

static const MsAllocator mimalloc_allocator = {mimalloc_allocate, mimalloc_reallocate, mimalloc_release};

static const MsAllocator *current(void) {
  return installed != NULL ? installed : &mimalloc_allocator;
}

static void *checked(void *block) {
  if (block == NULL) {
    ms_fatal(MS_FATAL_OUT_OF_MEMORY, "out of memory");
  }
  return block;
}

void ms_alloc_install(const MsAllocator *allocator) {
  installed = allocator;
  refresh_hooked();
}

static _Thread_local int64_t counted_allocations, counted_bytes;

void ms_alloc_counts(int64_t *allocations, int64_t *bytes) {
  *allocations = counted_allocations;
  *bytes = counted_bytes;
}

static MsAllocObserver observer = NULL;

void ms_alloc_observe(MsAllocObserver function) {
  observer = function;
  refresh_hooked();
}

static void count(size_t size) {
  counted_allocations++;
  counted_bytes += (int64_t)size;
  if (observer != NULL) {
    observer(size);
  }
}

/* The live bytes: the usable size of every mimalloc block handed out less those freed. The sum is striped over
 * cache-line padded counters, each thread adding to its own stripe, so threads do not contend; a block freed on
 * another thread than the one that made it leaves one stripe negative, and only the sum is meaningful. */
enum { LIVE_STRIPES = 64 };
typedef struct LiveStripe {
  _Alignas(64) _Atomic int64_t bytes;
#ifdef MS_STATS
  _Atomic int64_t blocks; /* the same, in blocks: the counting runtime's leak figure */
#endif
} LiveStripe;
static LiveStripe live_stripes[LIVE_STRIPES];
/* Tracking costs a mi_usable_size call per allocation and free, so it runs only in a program that can ask for the
 * figure (ms_alloc_track_live, called from the constructor of the unit that answers it). */
static _Atomic bool tracking = false;
static _Atomic unsigned next_stripe;
static _Thread_local LiveStripe *my_stripe = NULL;

void ms_alloc_track_live(void) {
  atomic_store_explicit(&tracking, true, memory_order_relaxed);
  refresh_hooked();
}

static void refresh_hooked(void) {
#ifdef MS_STATS
  const bool on = true;
#else
  const bool on = installed != NULL || observer != NULL || atomic_load_explicit(&tracking, memory_order_relaxed);
#endif
  atomic_store_explicit(&hooked, on, memory_order_relaxed);
}

static LiveStripe *stripe(void) {
  if (my_stripe == NULL) {
    my_stripe = &live_stripes[atomic_fetch_add_explicit(&next_stripe, 1, memory_order_relaxed) % LIVE_STRIPES];
  }
  return my_stripe;
}

static void live_add(int64_t delta) {
  if (installed != NULL) {
    return; /* a test allocator's blocks have no known size */
  }
  atomic_fetch_add_explicit(&stripe()->bytes, delta, memory_order_relaxed);
}

#ifdef MS_STATS
static void block_add(int64_t delta) {
  atomic_fetch_add_explicit(&stripe()->blocks, delta, memory_order_relaxed);
}

/* MS_STATS_TRACE=1: remembers the allocation site (the callers' return addresses, read through the frame pointers the
 * stats build keeps) of every live block, so the report can name what leaked. A fixed table: a program with more live
 * blocks than it holds is not traced past it. */
enum { TRACE_SLOTS = 1 << 16, TRACE_DEPTH = 5 };
typedef struct TraceSlot {
  const void *block;
  void *frames[TRACE_DEPTH];
} TraceSlot;
static TraceSlot trace_slots[TRACE_SLOTS];
static atomic_flag trace_lock = ATOMIC_FLAG_INIT;
static _Atomic int trace_state; /* 0 unread, 1 off, 2 on */

static bool tracing(void) {
  int state = atomic_load_explicit(&trace_state, memory_order_relaxed);
  if (state == 0) {
    state = getenv("MS_STATS_TRACE") != NULL ? 2 : 1;
    atomic_store_explicit(&trace_state, state, memory_order_relaxed);
  }
  return state == 2;
}

static size_t trace_home(const void *block) { return ((uintptr_t)block >> 4) * 0x9E3779B97F4A7C15ull >> 48; }

__attribute__((noinline)) static void trace_alloc(const void *block) {
  if (!tracing() || installed != NULL) {
    return;
  }
  void *frames[TRACE_DEPTH] = {0};
  void **frame = __builtin_frame_address(0);
  for (int i = 0; i < TRACE_DEPTH && frame != NULL && ((uintptr_t)frame & 7) == 0; i++) {
    frames[i] = frame[1];
    void **next = frame[0];
    if (next <= frame) {
      break;
    }
    frame = next;
  }
  while (atomic_flag_test_and_set_explicit(&trace_lock, memory_order_acquire)) {
  }
  for (size_t step = 0, at = trace_home(block); step < TRACE_SLOTS; step++, at = (at + 1) % TRACE_SLOTS) {
    if (trace_slots[at].block == NULL || trace_slots[at].block == (const void *)1) {
      trace_slots[at].block = block;
      __builtin_memcpy(trace_slots[at].frames, frames, sizeof frames);
      break;
    }
  }
  atomic_flag_clear_explicit(&trace_lock, memory_order_release);
}

static void trace_free(const void *block) {
  if (!tracing() || installed != NULL) {
    return;
  }
  while (atomic_flag_test_and_set_explicit(&trace_lock, memory_order_acquire)) {
  }
  for (size_t step = 0, at = trace_home(block); step < TRACE_SLOTS; step++, at = (at + 1) % TRACE_SLOTS) {
    if (trace_slots[at].block == block) {
      trace_slots[at].block = (const void *)1; /* a tombstone keeps the probe chain */
      break;
    }
    if (trace_slots[at].block == NULL) {
      break;
    }
  }
  atomic_flag_clear_explicit(&trace_lock, memory_order_release);
}

void ms_alloc_trace_report(void) {
  if (!tracing()) {
    return;
  }
  for (size_t at = 0; at < TRACE_SLOTS; at++) {
    if (trace_slots[at].block > (const void *)1) {
      fprintf(stderr, "ms-rt live block %p from", trace_slots[at].block);
      for (int i = 0; i < TRACE_DEPTH && trace_slots[at].frames[i] != NULL; i++) {
        fprintf(stderr, " %p", trace_slots[at].frames[i]);
      }
      fprintf(stderr, "\n");
    }
  }
}

int64_t ms_alloc_live_blocks(void) {
  int64_t sum = 0;
  for (size_t i = 0; i < LIVE_STRIPES; i++) {
    sum += atomic_load_explicit(&live_stripes[i].blocks, memory_order_relaxed);
  }
  return sum;
}

void ms_alloc_counts_reset(void) {
  counted_allocations = 0;
  counted_bytes = 0;
}
#else
#define block_add(delta) ((void)0)
#define trace_alloc(block) ((void)0)
#define trace_free(block) ((void)0)
#endif

static int64_t usable(const void *block) {
  if (block == NULL || installed != NULL || !atomic_load_explicit(&tracking, memory_order_relaxed)) {
    return 0;
  }
  return (int64_t)mi_usable_size(block);
}

int64_t ms_alloc_live_bytes(void) {
  int64_t sum = 0;
  for (size_t i = 0; i < LIVE_STRIPES; i++) {
    sum += atomic_load_explicit(&live_stripes[i].bytes, memory_order_relaxed);
  }
  return sum < 0 ? 0 : sum; /* blocks made before tracking began leave it below the truth, never above */
}

void *ms_alloc(size_t size) {
  if (!atomic_load_explicit(&hooked, memory_order_relaxed)) {
    counted_allocations++;
    counted_bytes += (int64_t)size;
    return checked(mi_malloc(size));
  }
  count(size);
  void *block = checked(current()->allocate(size));
  live_add(usable(block));
  block_add(1);
  trace_alloc(block);
  return block;
}

void *ms_alloc_zeroed(size_t size) {
  if (installed == NULL) {
    /* mimalloc knows when a block comes from fresh pages that are already zero, so it skips the clearing. */
    count(size);
    void *fresh = checked(mi_zalloc(size));
    live_add(usable(fresh));
    block_add(1);
    trace_alloc(fresh);
    return fresh;
  }
  void *block = ms_alloc(size);
  __builtin_memset(block, 0, size);
  return block;
}

void *ms_realloc(void *block, size_t size) {
  count(size);
  const int64_t before = usable(block);
  void *moved = checked(block == NULL ? current()->allocate(size) : current()->reallocate(block, size));
  live_add(usable(moved) - before);
  if (block == NULL) {
    block_add(1);
  }
  if (block != moved) {
    trace_free(block);
    trace_alloc(moved);
  }
  return moved;
}

void ms_free(void *block) {
  if (!atomic_load_explicit(&hooked, memory_order_relaxed)) {
    mi_free(block); /* accepts NULL */
    return;
  }
  if (block != NULL) {
    live_add(-usable(block));
    block_add(-1);
    trace_free(block);
    current()->release(block);
  }
}
