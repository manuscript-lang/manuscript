/* Size-class allocator: one heap for the whole process. Ported from crates/ms-rt/src/alloc.rs.
 *
 * Small blocks (up to MSALLOC_MAX_SMALL bytes) come from 64 KiB pages carved out of one large lazily
 * committed reservation shared by every thread. Each page serves a single size class and belongs to one
 * heap; a table with one word per page records the class and the owner, so free needs no size and treats
 * every block alike, whichever thread allocated it.
 *
 * A thread that claims a heap allocates from its own pages without locks. A block freed by another thread
 * is pushed onto its owner's lock-free remote-free stack, found by the owner index in the page table, and
 * the owner drains it on its next slow-path allocation. When a thread releases its heap the heap keeps its
 * pages and free lists and the next thread to claim one adopts it, so nothing is unmapped and a block
 * outlives its thread. Threads that never claimed a heap (pool and helper threads) use the system allocator.
 *
 * Large blocks go to the system allocator, with freed blocks up to MSALLOC_LARGE_MAX kept in per-size free
 * lists so growing and rebuilding big lists does not map and unmap memory (musl's malloc does an
 * mmap/munmap pair for every block above a few KiB). One buffer per heap grows in place in its own chunk
 * of address space, so a list that doubles is not copied at every step.
 */
#include <stdatomic.h>

#include "alloc.h"
#include "ms_sys.h"

#define MAX_SMALL MSALLOC_MAX_SMALL
#define NUM_CLASSES MSALLOC_NUM_CLASSES
#define NUM_LARGE MSALLOC_NUM_LARGE
#define LARGE_MIN_SHIFT MSALLOC_LARGE_MIN_SHIFT
#define LARGE_MAX MSALLOC_LARGE_MAX

#define PAGE_SHIFT 16
#define PAGE_SIZE ((size_t)1 << PAGE_SHIFT)
/* The huge page size Linux's transparent huge pages use on the supported targets. */
#define HUGE_PAGE ((size_t)2 << 20)
/* Bytes at the start of each reservation that stay on small pages: the first touch of a huge page clears
 * all of it, so a short program would pay for memory it never uses. */
#define HUGE_AFTER (2 * HUGE_PAGE)
/* Address space reserved for the small-block pages of the whole process, at most. */
#define PAGES_SIZE ((size_t)256 << 30)
/* How many times the reservation is halved before the allocator gives up and uses the system's. */
#define MAX_SHRINK 10
/* Heaps that can exist at once (the owner field of the page table is 16 bits). */
#define MAX_HEAPS ((size_t)1 << 16)
/* Page-table word: owner heap in the upper bits, size class in the low byte. */
#define OWNER_SHIFT 8
/* Owner of no heap: the state of a thread that has not claimed one. */
#define NO_HEAP UINT32_MAX
/* Arena growth step where memory is committed explicitly. */
#define COMMIT_STEP ((size_t)4 << 20)
/* Smallest system block that grows by remapping rather than by copying. */
#define REMAP_MIN ((size_t)128 << 10)
/* Address space of one growing buffer; a heap takes one on first use. */
#define GROW_SIZE ((size_t)1 << 30)
#define GROW_CHUNKS 1024
/* A block grows in the growth region once it reaches this size. */
#define GROW_MIN ((size_t)32 << 10)
/* Resident bytes the growth region keeps after its block is freed; the rest goes back. */
#define GROW_KEEP ((size_t)64 << 20)
/* Bytes the large free lists may hold before further frees go back to the system. */
#define LARGE_CACHE_LIMIT ((size_t)64 << 20)
/* Most blocks of one large class a thread keeps for itself; further frees go to the shared lists, where
 * threads without a heap (blocking-pool jobs) find them. */
#define LOCAL_PER_CLASS 4
#define UNMAPPED ((uintptr_t)1 << (UINTPTR_MAX == UINT64_MAX ? 63 : 31))

#define LIKELY(x) __builtin_expect(!!(x), 1)
#define UNLIKELY(x) __builtin_expect(!!(x), 0)
#define NOINLINE __attribute__((noinline))
#define COLD __attribute__((cold, noinline))

const uint16_t msalloc_class_size[NUM_CLASSES] = {
    16,  32,  48,  64,  80,  96,  112, 128,  160,  192,  224,  256,
    320, 384, 448, 512, 640, 768, 896, 1024, 1280, 1536, 1792, 2048,
};

/* size / 16 (rounded up) -> class index, for sizes 1..=2048. */
static const uint8_t LOOKUP[129] = {
    0,  0,  1,  2,  3,  4,  5,  6,  7,  8,  8,  9,  9,  10, 10, 11, 11, 12, 12, 12, 12, 13, 13, 13, 13,
    14, 14, 14, 14, 15, 15, 15, 15, 16, 16, 16, 16, 16, 16, 16, 16, 17, 17, 17, 17, 17, 17, 17, 17, 18,
    18, 18, 18, 18, 18, 18, 18, 19, 19, 19, 19, 19, 19, 19, 19, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20,
    20, 20, 20, 20, 20, 20, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 22, 22, 22,
    22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23,
    23, 23, 23, 23,
};

/* Size of large class `c`: 4, 5, 6, 7 times 1 KiB, then doubling. */
size_t msalloc_large_size(size_t c) {
    return (size_t)(4 + c % 4) << (LARGE_MIN_SHIFT - 2 + c / 4);
}

static inline size_t log2_floor(size_t x) {
    return (size_t)(sizeof(size_t) * 8 - 1 - (size_t)__builtin_clzll((unsigned long long)x));
}

/* The smallest large class holding `size` bytes (`size` is at most LARGE_MAX). */
static inline size_t large_class_up(size_t size) {
    if (size <= (size_t)1 << LARGE_MIN_SHIFT) {
        return 0;
    }
    size_t s = size - 1;
    size_t k = log2_floor(s);
    return (k - LARGE_MIN_SHIFT) * 4 + ((s >> (k - 2)) - 4) + 1;
}

/* The largest large class that fits in `usable` bytes (`usable` is at least 4 KiB). */
static inline size_t large_class_down(size_t usable) {
    size_t k = log2_floor(usable);
    size_t c = (k - LARGE_MIN_SHIFT) * 4 + ((usable >> (k - 2)) - 4);
    return c < NUM_LARGE - 1 ? c : NUM_LARGE - 1;
}

static inline size_t class_of(size_t size) {
    return LOOKUP[(size + 15) / 16];
}

/* A lock that never allocates; the critical sections are a few loads and stores, so a spin with a yield
 * is enough. */
typedef struct {
    atomic_flag held;
} Lock;

#define LOCK_INIT {ATOMIC_FLAG_INIT}

static void lock(Lock *l) {
    while (atomic_flag_test_and_set_explicit(&l->held, memory_order_acquire)) {
        mssys_yield();
    }
}

static void unlock(Lock *l) {
    atomic_flag_clear_explicit(&l->held, memory_order_release);
}

/* Freed large blocks for threads that have no heap of their own: a pool job reads a file into a block that
 * the runtime thread frees, so without a way back every such block would be mapped anew and faulted in
 * page by page. */
static struct {
    void *free[NUM_LARGE];
    /* Usable bytes held in `free`. */
    size_t cached;
} shared_cache;
static Lock shared_lock = LOCK_INIT;

typedef struct {
    /* Index of this thread's heap, or NO_HEAP. */
    uint32_t heap;
    void *free[NUM_CLASSES];
    char *bump[NUM_CLASSES];
    char *bump_end[NUM_CLASSES];
    void *large_free[NUM_LARGE];
    /* Blocks held in each large_free list. */
    uint8_t large_count[NUM_LARGE];
    /* Usable bytes held in large_free. */
    size_t large_cached;
    /* This heap's growth chunk (index into the growth reservation), or SIZE_MAX: address space for the one
     * buffer that is growing, so it extends in place. Its live length is in grow_len. */
    size_t grow_chunk;
    /* Bytes of the chunk made usable so far. */
    size_t grow_committed;
    /* Allocations and bytes requested since start. */
    uint64_t requested[2];
    /* The allocation count at which the profiler takes its next sample. */
    uint64_t sample_at;
#ifdef MS_ALLOC_STATS
    int64_t live;
#endif
} State;

#define STATE_INIT {.heap = NO_HEAP, .grow_chunk = SIZE_MAX, .sample_at = UINT64_MAX}

static _Thread_local State st = STATE_INIT;

/* The process's reservation: small-block pages, their table, and the growth chunks. Until it is mapped
 * they sit at an address no pointer reaches, so no block is ever inside them. What every free and
 * ownership test reads is in one object so it costs one address load. */
static struct {
    _Atomic uintptr_t base;
    _Atomic(uint32_t *) table;
    _Atomic uintptr_t grow_base;
    /* Bytes of address space the page reservation actually got. */
    _Atomic size_t pages_len;
    /* log2 of the size of one growth chunk, halved along with the pages. */
    _Atomic size_t grow_bits;
} hot = {UNMAPPED, 0, UNMAPPED, PAGES_SIZE, 30};

static Lock region_lock = LOCK_INIT;
static bool region_done;

/* Next page not handed to any heap. */
static _Atomic size_t next_page;
/* Bytes of the page reservation made usable (everything on Unix, grown in steps on Windows). */
static _Atomic size_t committed;
static Lock commit_lock = LOCK_INIT;
/* Next growth chunk not taken. */
static _Atomic size_t next_chunk;
/* Length of the block living in each growth chunk, 0 when the chunk is free. Any thread frees a block by
 * clearing its length; the heap owning the chunk takes it again. */
static _Atomic size_t grow_len[GROW_CHUNKS];
/* Head of the blocks other threads freed into each heap. */
static _Atomic(void *) remote[MAX_HEAPS];
/* Heaps handed out so far. */
static _Atomic size_t heap_count;
/* Requests of threads that have released their heap, so work done on a worker thread stays counted. */
static _Atomic uint64_t released[2];

/* Heaps whose thread ended, with their free lists and partly used pages. */
typedef struct Idle {
    struct Idle *next;
    State state;
} Idle;
static Idle *idle_heaps;
static Lock idle_lock = LOCK_INIT;

static int64_t (*sampler)(size_t);

static inline size_t pages_len(void) {
    return atomic_load_explicit(&hot.pages_len, memory_order_relaxed);
}

static inline size_t num_pages(void) {
    return pages_len() >> PAGE_SHIFT;
}

static inline size_t grow_size(void) {
    return (size_t)1 << atomic_load_explicit(&hot.grow_bits, memory_order_relaxed);
}

static inline uintptr_t grow_base(size_t chunk) {
    return atomic_load_explicit(&hot.grow_base, memory_order_relaxed) + chunk * grow_size();
}

static inline void *link_next(void *p) {
    return *(void **)p;
}

static inline void set_link(void *p, void *next) {
    *(void **)p = next;
}

/* Page-table word of the small-block page holding p, or false when p is not in the pages. */
static inline bool page_word(const void *p, uint32_t *word) {
    uintptr_t off = (uintptr_t)p - atomic_load_explicit(&hot.base, memory_order_relaxed);
    if (off >= pages_len()) {
        return false;
    }
    *word = atomic_load_explicit(&hot.table, memory_order_relaxed)[off >> PAGE_SHIFT];
    return true;
}

/* The growth chunk holding p, or GROW_CHUNKS when none does. */
static inline size_t grow_chunk_of(const void *p) {
    uintptr_t off = (uintptr_t)p - atomic_load_explicit(&hot.grow_base, memory_order_relaxed);
    size_t chunk = (size_t)(off >> atomic_load_explicit(&hot.grow_bits, memory_order_relaxed));
    return chunk < GROW_CHUNKS ? chunk : GROW_CHUNKS;
}

#ifdef MS_ALLOC_STATS
static inline void live_add(State *s, int64_t delta) {
    s->live += delta;
}
int64_t msalloc_live_blocks(void) {
    return st.live;
}
#else
#define live_add(s, delta) ((void)0)
#endif

/* ---- shared cache of large blocks ---- */

static void *shared_take(size_t size) {
    if (size <= MAX_SMALL || size > LARGE_MAX) {
        return 0;
    }
    size_t c = large_class_up(size);
    lock(&shared_lock);
    void *head = shared_cache.free[c];
    if (head) {
        shared_cache.free[c] = link_next(head);
        shared_cache.cached -= mssys_malloc_size(head);
    }
    unlock(&shared_lock);
    return head;
}

void *msrt_heap_shared_take(size_t size) {
    return shared_take(size);
}

uint8_t msrt_heap_shared_put(void *p) {
    size_t usable = mssys_malloc_size(p);
    if (usable < ((size_t)1 << LARGE_MIN_SHIFT) || usable > LARGE_MAX) {
        return 0;
    }
    lock(&shared_lock);
    if (shared_cache.cached + usable > LARGE_CACHE_LIMIT) {
        unlock(&shared_lock);
        return 0;
    }
    size_t c = large_class_down(usable);
    set_link(p, shared_cache.free[c]);
    shared_cache.free[c] = p;
    shared_cache.cached += usable;
    unlock(&shared_lock);
    return 1;
}

/* ---- the reservation ---- */

bool msalloc_reserve(void *(*map)(size_t), void (*unmap)(void *, size_t), msalloc_region *out) {
    unsigned fit = 0;
    msalloc_region r;
    bool found = false;
    for (unsigned shrink = 0; shrink <= MAX_SHRINK && !found; shrink++) {
        size_t pages_bytes = PAGES_SIZE >> shrink;
        size_t gsize = GROW_SIZE >> shrink;
        size_t glen = gsize * GROW_CHUNKS;
        size_t table_len = (pages_bytes >> PAGE_SHIFT) * 4;
        void *pages = map(pages_bytes), *table = map(table_len), *grow = map(glen);
        if (pages && table && grow && mssys_commit(table, table_len)) {
            r = (msalloc_region){pages, pages_bytes, table, grow, glen, (size_t)log2_floor(gsize)};
            fit = shrink;
            found = true;
            break;
        }
        if (pages) unmap(pages, pages_bytes);
        if (table) unmap(table, table_len);
        if (grow) unmap(grow, glen);
    }
    if (!found) {
        return false;
    }
    if (fit == 0) {
        *out = r;
        return true;
    }
    /* Hand the first fit back and map a quarter of it (which the space just freed always holds). */
    unmap(r.pages, r.pages_len);
    unmap(r.table, (r.pages_len >> PAGE_SHIFT) * 4);
    unmap(r.grow, r.grow_len);
    unsigned smaller = fit + 2 < MAX_SHRINK ? fit + 2 : MAX_SHRINK;
    for (unsigned shrink = smaller; shrink <= MAX_SHRINK; shrink++) {
        size_t pages_bytes = PAGES_SIZE >> shrink;
        size_t gsize = GROW_SIZE >> shrink;
        size_t glen = gsize * GROW_CHUNKS;
        size_t table_len = (pages_bytes >> PAGE_SHIFT) * 4;
        void *pages = map(pages_bytes), *table = map(table_len), *grow = map(glen);
        if (pages && table && grow && mssys_commit(table, table_len)) {
            *out = (msalloc_region){pages, pages_bytes, table, grow, glen, (size_t)log2_floor(gsize)};
            return true;
        }
        if (pages) unmap(pages, pages_bytes);
        if (table) unmap(table, table_len);
        if (grow) unmap(grow, glen);
    }
    return false;
}

/* Maps the reservation once; false when the system refuses (everything then uses the system allocator). */
COLD static bool ensure_region(void) {
    lock(&region_lock);
    if (!region_done) {
        region_done = true;
        msalloc_region r;
        if (msalloc_reserve(mssys_map, mssys_unmap, &r)) {
            /* Huge pages only past the first few MiB: the kernel clears a whole 2 MiB page on the first
             * touch, which costs a short program about 0.35 ms at start-up for memory it never uses. */
            if (r.pages_len > HUGE_AFTER) {
                mssys_prefer_huge((char *)r.pages + HUGE_AFTER, r.pages_len - HUGE_AFTER);
            }
            if (r.grow_len > HUGE_AFTER) {
                mssys_prefer_huge((char *)r.grow + HUGE_AFTER, r.grow_len - HUGE_AFTER);
            }
            atomic_store_explicit(&hot.pages_len, r.pages_len, memory_order_relaxed);
            atomic_store_explicit(&hot.grow_bits, r.grow_bits, memory_order_relaxed);
            atomic_store_explicit(&hot.table, (uint32_t *)r.table, memory_order_relaxed);
            atomic_store_explicit(&hot.grow_base, (uintptr_t)r.grow, memory_order_relaxed);
            /* Published last: a reader that sees base sees the rest. */
            atomic_store_explicit(&hot.base, (uintptr_t)r.pages, memory_order_release);
        }
    }
    unlock(&region_lock);
    return atomic_load_explicit(&hot.base, memory_order_acquire) != UNMAPPED;
}

/* ---- heaps ---- */

void msrt_heap_claim(void) {
    State *s = &st;
    if (s->heap != NO_HEAP || !ensure_region()) {
        return;
    }
    lock(&idle_lock);
    Idle *adopted = idle_heaps;
    if (adopted) {
        idle_heaps = adopted->next;
    }
    unlock(&idle_lock);
    if (adopted) {
        *s = adopted->state;
        mssys_free(adopted);
        return;
    }
    size_t heap = atomic_fetch_add_explicit(&heap_count, 1, memory_order_relaxed);
    if (heap >= MAX_HEAPS) {
        atomic_store_explicit(&heap_count, MAX_HEAPS, memory_order_relaxed);
        return;
    }
    s->heap = (uint32_t)heap;
}

void msrt_heap_release(void) {
    State *s = &st;
    if (s->heap == NO_HEAP) {
        return;
    }
    for (size_t c = 0; c < NUM_LARGE; c++) {
        void *p = s->large_free[c];
        while (p) {
            void *next = link_next(p);
            mssys_free(p);
            p = next;
        }
        s->large_free[c] = 0;
    }
    for (size_t c = 0; c < NUM_LARGE; c++) {
        s->large_count[c] = 0;
    }
    s->large_cached = 0;
    atomic_fetch_add_explicit(&released[0], s->requested[0], memory_order_relaxed);
    atomic_fetch_add_explicit(&released[1], s->requested[1], memory_order_relaxed);
    s->requested[0] = s->requested[1] = 0;
    s->sample_at = UINT64_MAX;
#ifdef MS_ALLOC_STATS
    s->live = 0;
#endif
    /* The list node comes from the system allocator, not from this heap. */
    Idle *node = mssys_malloc(sizeof(Idle));
    if (!node) {
        msalloc_rust_oom(sizeof(Idle));
    }
    node->state = *s;
    *s = (State)STATE_INIT;
    lock(&idle_lock);
    node->next = idle_heaps;
    idle_heaps = node;
    unlock(&idle_lock);
}

uint8_t msrt_heap_has(void) {
    return st.heap != NO_HEAP;
}

/* Whether p lies in the reservation (small pages or a growth chunk). */
uint8_t msrt_heap_owns(const void *p) {
    uint32_t word;
    return page_word(p, &word) || grow_chunk_of(p) < GROW_CHUNKS;
}

/* Pushes a block onto its owning heap's remote-free stack. */
static void remote_free(size_t heap, void *p) {
    _Atomic(void *) *stack = &remote[heap];
    void *head = atomic_load_explicit(stack, memory_order_relaxed);
    do {
        /* A freed block is at least 16 bytes and holds the link in its first word. */
        set_link(p, head);
    } while (!atomic_compare_exchange_weak_explicit(stack, &head, p, memory_order_release, memory_order_relaxed));
}

/* Moves the blocks other threads freed into this heap onto its free lists. */
COLD static void drain_remote(State *s) {
    void *p = atomic_exchange_explicit(&remote[s->heap], 0, memory_order_acquire);
    while (p) {
        void *next = link_next(p);
        uint32_t word = 0;
        page_word(p, &word);
        size_t c = (uint8_t)word;
        set_link(p, s->free[c]);
        s->free[c] = p;
        p = next;
    }
}

COLD static void *refill(State *s, size_t c) {
    size_t page = atomic_fetch_add_explicit(&next_page, 1, memory_order_relaxed);
    if (page >= num_pages()) {
        atomic_store_explicit(&next_page, num_pages(), memory_order_relaxed);
        return 0;
    }
    uintptr_t base = atomic_load_explicit(&hot.base, memory_order_relaxed);
    size_t used = (page + 1) * PAGE_SIZE;
    if (used > atomic_load_explicit(&committed, memory_order_acquire)) {
        lock(&commit_lock);
        size_t have = atomic_load_explicit(&committed, memory_order_relaxed);
        if (used > have) {
            size_t step = used - have > COMMIT_STEP ? used - have : COMMIT_STEP;
            size_t room = pages_len() - have;
            size_t chunk = step < room ? step : room;
            if (!mssys_commit((void *)(base + have), chunk)) {
                unlock(&commit_lock);
                return 0;
            }
            atomic_store_explicit(&committed, have + chunk, memory_order_release);
        }
        unlock(&commit_lock);
    }
    atomic_load_explicit(&hot.table, memory_order_relaxed)[page] = (s->heap << OWNER_SHIFT) | (uint32_t)c;
    char *start = (char *)(base + page * PAGE_SIZE);
    size_t size = msalloc_class_size[c];
    s->bump_end[c] = start + PAGE_SIZE / size * size;
    s->bump[c] = start;
    return start;
}

/* ---- allocation ---- */

static void *alloc_large(State *s, size_t size);

/* Hands the allocation profiler one sample and arms the next. */
COLD static void take_sample(State *s, size_t size) {
    /* Disarmed while the hook runs: it may allocate. */
    s->sample_at = UINT64_MAX;
    int64_t period = sampler ? sampler(size) : INT64_MAX;
    State *now = &st;
    now->sample_at = period >= INT64_MAX - (int64_t)now->requested[0] ? UINT64_MAX : now->requested[0] + (uint64_t)period;
}

void msrt_heap_sample_every(int64_t period, void *hook) {
    sampler = (int64_t (*)(size_t))hook;
    st.sample_at = st.requested[0] + (uint64_t)period;
}

NOINLINE static void *alloc_slow(size_t size) {
    State *s = &st;
    if (size <= MAX_SMALL && s->heap != NO_HEAP) {
        if (atomic_load_explicit(&remote[s->heap], memory_order_relaxed)) {
            drain_remote(s);
        }
        size_t c = class_of(size ? size : 1);
        void *head = s->free[c];
        if (head) {
            s->free[c] = link_next(head);
            live_add(s, 1);
            return head;
        }
        char *p = s->bump[c];
        if (!p || p >= s->bump_end[c]) {
            p = refill(s, c);
        }
        if (p) {
            s->bump[c] = p + msalloc_class_size[c];
            live_add(s, 1);
            return p;
        }
    }
    return alloc_large(s, size);
}

/* Allocates size bytes (16-byte aligned, uninitialised). Faults on exhaustion. A recycled small block is
 * the common case and is handled here; everything else is in alloc_slow. */
void *msrt_alloc(size_t size) {
    State *s = &st;
    s->requested[0]++;
    s->requested[1] += size;
    if (UNLIKELY(s->requested[0] >= s->sample_at)) {
        take_sample(s, size);
    }
    if (size <= MAX_SMALL) {
        size_t c = class_of(size ? size : 1);
        void *head = s->free[c];
        if (LIKELY(head != 0)) {
            s->free[c] = link_next(head);
            live_add(s, 1);
            return head;
        }
    }
    return alloc_slow(size);
}

/* Asks for huge pages over the whole 2 MiB units inside a block the system allocator mapped: a block above
 * LARGE_MAX is a big list or buffer whose first touch otherwise costs one page fault per 4 KiB. */
static void advise_huge(void *p, size_t len) {
    uintptr_t start = ((uintptr_t)p + HUGE_PAGE - 1) & ~(uintptr_t)(HUGE_PAGE - 1);
    uintptr_t end = ((uintptr_t)p + len) & ~(uintptr_t)(HUGE_PAGE - 1);
    if (end > start) {
        mssys_prefer_huge((void *)start, end - start);
    }
}

NOINLINE static void *alloc_large(State *s, size_t size) {
    size_t request = size > 16 ? size : 16;
    if (size > MAX_SMALL && size <= LARGE_MAX) {
        size_t c = large_class_up(size);
        void *head = s->large_free[c];
        if (head) {
            s->large_free[c] = link_next(head);
            s->large_count[c]--;
            s->large_cached -= mssys_malloc_size(head);
            live_add(s, 1);
            return head;
        }
        request = msalloc_large_size(c);
        void *shared = shared_take(size);
        if (shared) {
            live_add(s, 1);
            return shared;
        }
    }
    void *p = mssys_malloc(request);
    if (!p) {
        msalloc_rust_oom(request);
    }
    if (request > LARGE_MAX) {
        advise_huge(p, request);
    }
    live_add(s, 1);
    return p;
}

/* The size a large block of `size` bytes is requested from the system with, so freeing it files it under
 * the class that a later request of the same size looks in. */
size_t msrt_heap_large_request(size_t size) {
    return size > MAX_SMALL && size <= LARGE_MAX ? msalloc_large_size(large_class_up(size)) : size;
}

/* A zeroed large block taken from the free lists, or null when none is cached. The system's lazily zeroed
 * pages cost a page fault per page on first use, more than clearing a block that is already mapped. */
void *msrt_heap_alloc_zeroed_cached(size_t size) {
    if (size <= MAX_SMALL || size > LARGE_MAX) {
        return 0;
    }
    State *s = &st;
    size_t c = large_class_up(size);
    void *head = s->large_free[c];
    if (!head) {
        return 0;
    }
    s->requested[0]++;
    s->requested[1] += size;
    s->large_free[c] = link_next(head);
    s->large_count[c]--;
    s->large_cached -= mssys_malloc_size(head);
    __builtin_memset(head, 0, size);
    live_add(s, 1);
    return head;
}

void *msrt_alloc_zeroed(size_t size) {
    void *p = msrt_alloc(size);
    __builtin_memset(p, 0, size);
    return p;
}

/* ---- free ---- */

/* Keeps a freed system block in its large free list, or returns it to the system. */
static void free_large(State *s, void *p) {
    size_t usable = mssys_malloc_size(p);
    size_t c = large_class_down(usable > ((size_t)1 << LARGE_MIN_SHIFT) ? usable : ((size_t)1 << LARGE_MIN_SHIFT));
    if (s->heap != NO_HEAP && usable >= ((size_t)1 << LARGE_MIN_SHIFT) && usable <= LARGE_MAX &&
        s->large_cached + usable <= LARGE_CACHE_LIMIT && s->large_count[c] < LOCAL_PER_CLASS) {
        set_link(p, s->large_free[c]);
        s->large_free[c] = p;
        s->large_count[c]++;
        s->large_cached += usable;
    } else if (!msrt_heap_shared_put(p)) {
        mssys_free(p);
    }
}

/* Frees the block in growth chunk `chunk`, from any thread. Its pages stay resident for the next buffer
 * unless there are many and the chunk is this heap's. */
static void grow_release(State *s, size_t chunk) {
    if (chunk == s->grow_chunk && s->grow_committed > GROW_KEEP) {
        mssys_decommit((void *)grow_base(chunk), s->grow_committed);
        s->grow_committed = 0;
    }
    atomic_store_explicit(&grow_len[chunk], 0, memory_order_release);
}

/* Frees a block returned by msrt_alloc or msrt_realloc on any thread. Null is ignored. */
void msrt_free(void *p) {
    if (!p) {
        return;
    }
    State *s = &st;
    live_add(s, -1);
    uint32_t word;
    size_t chunk;
    if (page_word(p, &word)) {
        size_t c = (uint8_t)word;
        uint32_t owner = word >> OWNER_SHIFT;
        if (owner == s->heap) {
#ifdef MS_ALLOC_STATS
            /* The counting build scribbles over freed blocks so a use after free shows up. */
            __builtin_memset(p, 0xDD, msalloc_class_size[c]);
#endif
            set_link(p, s->free[c]);
            s->free[c] = p;
        } else {
            remote_free(owner, p);
        }
    } else if ((chunk = grow_chunk_of(p)) < GROW_CHUNKS) {
        grow_release(s, chunk);
    } else {
        /* Not a block of the reservation, so it came from the system allocator. */
        free_large(s, p);
    }
}

/* ---- sizes and resizing ---- */

/* Usable size of a live block. */
size_t msrt_heap_usable_size(void *p) {
    size_t chunk = grow_chunk_of(p);
    if (chunk < GROW_CHUNKS) {
        return atomic_load_explicit(&grow_len[chunk], memory_order_acquire);
    }
    uint32_t word;
    if (page_word(p, &word)) {
        return msalloc_class_size[(uint8_t)word];
    }
    return mssys_malloc_size(p);
}

/* realloc for a block that is shrinking: a small block whose class already fits new_size (more than half
 * used) stays where it is, decided by one page-table read without entering realloc. */
void *msrt_heap_trim(void *p, size_t new_size) {
    uint32_t word;
    if (page_word(p, &word)) {
        size_t old = msalloc_class_size[(uint8_t)word];
        if (new_size <= old && new_size > old / 2) {
            return p;
        }
    }
    return msrt_realloc(p, new_size);
}

/* Takes a growth chunk for this heap; false when none is left. */
COLD static bool grow_map(State *s) {
    if (s->heap == NO_HEAP) {
        return false;
    }
    size_t chunk = atomic_fetch_add_explicit(&next_chunk, 1, memory_order_relaxed);
    if (chunk >= GROW_CHUNKS) {
        atomic_store_explicit(&next_chunk, GROW_CHUNKS, memory_order_relaxed);
        return false;
    }
    s->grow_chunk = chunk;
    s->grow_committed = 0;
    return true;
}

/* Makes the first len bytes of the growth chunk usable; false when the system refuses. */
static bool grow_commit(State *s, size_t len) {
    if (len > s->grow_committed) {
        size_t to = (len + COMMIT_STEP - 1) / COMMIT_STEP * COMMIT_STEP;
        if (to > grow_size()) {
            to = grow_size();
        }
        if (!mssys_commit((void *)(grow_base(s->grow_chunk) + s->grow_committed), to - s->grow_committed)) {
            return false;
        }
        s->grow_committed = to;
    }
    return true;
}

/* A block of `size` bytes at the start of this heap's growth chunk, or null when it is taken or too small. */
static void *grow_take(State *s, size_t size) {
    if ((s->grow_chunk == SIZE_MAX && !grow_map(s)) || size > grow_size()) {
        return 0;
    }
    if (atomic_load_explicit(&grow_len[s->grow_chunk], memory_order_acquire) != 0 || !grow_commit(s, size)) {
        return 0;
    }
    atomic_store_explicit(&grow_len[s->grow_chunk], size, memory_order_release);
    live_add(s, 1);
    return (void *)grow_base(s->grow_chunk);
}

/* Resizes the block in this heap's growth chunk: in place while it stays big, otherwise out of it. */
static void *grow_resize(void *p, size_t new_size) {
    State *s = &st;
    size_t chunk = s->grow_chunk;
    if (new_size >= GROW_MIN && new_size <= grow_size() && grow_commit(s, new_size)) {
        atomic_store_explicit(&grow_len[chunk], new_size, memory_order_release);
        return p;
    }
    size_t old = atomic_load_explicit(&grow_len[chunk], memory_order_acquire);
    void *q = msrt_alloc(new_size);
    __builtin_memcpy(q, p, old < new_size ? old : new_size);
    grow_release(s, chunk);
    live_add(s, -1);
    return q;
}

static void *move_block(void *p, size_t old, size_t new_size) {
    void *q = msrt_alloc(new_size);
    __builtin_memcpy(q, p, old < new_size ? old : new_size);
    msrt_free(p);
    return q;
}

/* Resizes a block, preserving the common prefix. */
void *msrt_realloc(void *p, size_t new_size) {
    if (!p) {
        return msrt_alloc(new_size);
    }
    State *s = &st;
    size_t chunk = grow_chunk_of(p);
    if (chunk < GROW_CHUNKS) {
        if (chunk == s->grow_chunk) {
            return grow_resize(p, new_size);
        }
        /* Another heap's growing buffer: the bytes move out and its chunk is freed. */
        size_t old = atomic_load_explicit(&grow_len[chunk], memory_order_acquire);
        return move_block(p, old, new_size);
    }
    uint32_t word;
    if (page_word(p, &word)) {
        size_t old = msalloc_class_size[(uint8_t)word];
        if (new_size <= old && new_size > old / 2) {
            return p;
        }
        return move_block(p, old, new_size);
    }
    size_t old = mssys_malloc_size(p);
    if (new_size <= MAX_SMALL) {
        return move_block(p, old, new_size);
    }
    /* A big block that is growing moves into the growth region once, and extends there in place from then on. */
    if (new_size > old && new_size >= GROW_MIN) {
        void *q = grow_take(s, new_size);
        if (q) {
            __builtin_memcpy(q, p, old);
            /* The old block goes straight back: a cached copy would stay resident unused. */
            live_add(s, -1);
            mssys_free(p);
            return q;
        }
    }
    /* Growing a big block with no cached block to move into: let the system remap its pages instead of
     * copying them into fresh (page-faulting) memory. */
    bool uncached = new_size > old && old >= REMAP_MIN &&
                    (new_size > LARGE_MAX || s->large_free[large_class_up(new_size)] == 0);
    if ((old > LARGE_MAX && new_size > LARGE_MAX) || uncached) {
        void *q = mssys_realloc(p, new_size);
        if (!q) {
            msalloc_rust_oom(new_size);
        }
        return q;
    }
    if (new_size <= old && new_size > old / 2) {
        return p;
    }
    return move_block(p, old, new_size);
}

/* ---- figures ---- */

/* Small-block heap figures in bytes for the calling thread's heap: out[0] is used (blocks handed out and
 * not on a free list), out[1] the bytes of pages in use. Large blocks belong to the system allocator and
 * are not included. Walks the page table and the free lists, so it is meant for occasional diagnostics. */
void msrt_heap_stats(int64_t *out) {
    State *s = &st;
    out[0] = out[1] = 0;
    if (s->heap == NO_HEAP) {
        return;
    }
    uint32_t *table = atomic_load_explicit(&hot.table, memory_order_relaxed);
    size_t carved = 0, pages = 0;
    size_t limit = atomic_load_explicit(&next_page, memory_order_relaxed);
    if (limit > num_pages()) {
        limit = num_pages();
    }
    for (size_t page = 0; page < limit; page++) {
        uint32_t word = table[page];
        if (word >> OWNER_SHIFT == s->heap) {
            size_t size = msalloc_class_size[(uint8_t)word];
            carved += PAGE_SIZE / size * size;
            pages++;
        }
    }
    size_t spare = 0;
    for (size_t c = 0; c < NUM_CLASSES; c++) {
        size_t size = msalloc_class_size[c];
        if ((uintptr_t)s->bump_end[c] > (uintptr_t)s->bump[c]) {
            spare += (size_t)(s->bump_end[c] - s->bump[c]);
        }
        for (void *p = s->free[c]; p; p = link_next(p)) {
            spare += size;
        }
    }
    /* Blocks other threads freed wait on the remote-free stack until this thread's next slow-path
     * allocation; they are free, and counting them as used made the figure depend on thread timing. Only
     * this thread drains the stack, so the chain from a loaded head stays valid. */
    for (void *p = atomic_load_explicit(&remote[s->heap], memory_order_acquire); p; p = link_next(p)) {
        uint32_t word = 0;
        page_word(p, &word);
        spare += msalloc_class_size[(uint8_t)word];
    }
    out[0] = (int64_t)(carved > spare ? carved - spare : 0);
    out[1] = (int64_t)(pages * PAGE_SIZE);
}

/* out[0] allocations and out[1] bytes requested by the calling thread and by every thread that has
 * finished (released its heap). Threads still running are not included. */
void msrt_heap_requested(uint64_t *out) {
    out[0] = st.requested[0] + atomic_load_explicit(&released[0], memory_order_relaxed);
    out[1] = st.requested[1] + atomic_load_explicit(&released[1], memory_order_relaxed);
}
