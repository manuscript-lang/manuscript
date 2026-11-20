/* Unit tests for runtime/core/alloc.c, ported from crates/ms-rt/src/alloc.rs; `make c-test` builds them
 * with ASan, UBSan and -DMS_ALLOC_STATS (live-block counts, freed blocks scribbled). */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "alloc.h"
#include "ms_rt/sys.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_alloc.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

#define GROW_MIN ((size_t)32 << 10)
#define REMAP_MIN ((size_t)128 << 10)

/* Every byte of a 4 KiB page of a test block holds the page's tag, so a block fills with memset and still
 * tells pages apart. */
static uint8_t tag(size_t i) {
    return (uint8_t)(i / 4096 % 250 + 1);
}

static void fill(uint8_t *p, size_t from, size_t to) {
    for (size_t lo = from; lo < to; lo += 4096) {
        size_t hi = lo + 4096 < to ? lo + 4096 : to;
        memset(p + lo, tag(lo), hi - lo);
    }
}

static void classes_cover_sizes(void) {
    for (size_t size = 1; size <= MSALLOC_MAX_SMALL; size++) {
        /* A block of every size must come back usable for that many bytes and never overlap its neighbour. */
        uint8_t *p = msrt_alloc(size);
        CHECK(msrt_heap_usable_size(p) >= size || !msrt_heap_owns(p));
        memset(p, 0xEE, size);
        msrt_free(p);
    }
    /* The class sizes are strictly increasing and the last serves MAX_SMALL. */
    for (size_t c = 1; c < MSALLOC_NUM_CLASSES; c++) {
        CHECK(msalloc_class_size[c] > msalloc_class_size[c - 1]);
    }
    CHECK(msalloc_class_size[MSALLOC_NUM_CLASSES - 1] == MSALLOC_MAX_SMALL);
    /* The smallest class for each size is the first that fits: usable size is the class size. */
    for (size_t size = 1; size <= MSALLOC_MAX_SMALL; size++) {
        void *p = msrt_alloc(size);
        size_t usable = msrt_heap_usable_size(p);
        size_t want = 0;
        while (msalloc_class_size[want] < size) want++;
        CHECK(usable == msalloc_class_size[want]);
        msrt_free(p);
    }
}

static void alloc_free_reuse_and_realloc(void) {
    int64_t before = msalloc_live_blocks();
    uint8_t *a = msrt_alloc(40), *b = msrt_alloc(40);
    CHECK(a != b);
    CHECK((uintptr_t)a % 16 == 0);
    for (int i = 0; i < 40; i++) a[i] = (uint8_t)i;
    uint8_t *c = msrt_realloc(a, 5000);
    for (int i = 0; i < 40; i++) CHECK(c[i] == i);
    uint8_t *d = msrt_realloc(c, 100);
    for (int i = 0; i < 40; i++) CHECK(d[i] == i);
    msrt_free(d);
    msrt_free(b);
    msrt_free(msrt_alloc(40));
    CHECK(msalloc_live_blocks() == before);
}

static void zeroed_and_trim(void) {
    uint8_t *p = msrt_alloc(64);
    memset(p, 0xFF, 64);
    msrt_free(p);
    uint8_t *z = msrt_alloc_zeroed(64);
    for (int i = 0; i < 64; i++) CHECK(z[i] == 0);
    /* A shrink that keeps more than half of the class stays in place; a deep shrink moves. */
    CHECK(msrt_heap_trim(z, 40) == (void *)z);
    uint8_t *small = msrt_heap_trim(z, 8);
    CHECK(msrt_heap_usable_size(small) == 16);
    msrt_free(small);
    CHECK(msrt_realloc(0, 10) != 0);
    msrt_free(0);
}

static void growing_a_big_block_keeps_its_bytes(void) {
    int64_t before = msalloc_live_blocks();
    size_t size = REMAP_MIN;
    uint8_t *p = msrt_alloc(size);
    fill(p, 0, size);
    for (int n = 0; n < 6; n++) {
        size_t old = size;
        size *= 2;
        p = msrt_realloc(p, size);
        for (size_t i = 0; i < old; i += 97) CHECK(p[i] == tag(i));
        fill(p, old, size);
    }
    msrt_free(p);
    CHECK(msalloc_live_blocks() == before);
}

static void a_growing_block_extends_in_place_and_shrinks_out(void) {
    int64_t before = msalloc_live_blocks();
    uint8_t *small = msrt_alloc(64);
    size_t size = 4096;
    uint8_t *p = msrt_alloc(size);
    fill(p, 0, size);
    uint8_t *home = 0;
    while (size < ((size_t)8 << 20)) {
        size_t old = size;
        size *= 2;
        p = msrt_realloc(p, size);
        if (size >= GROW_MIN) {
            if (!home) home = p;
            CHECK(p == home);
            CHECK(msrt_heap_usable_size(p) == size);
        }
        for (size_t i = 0; i < old; i += 89) CHECK(p[i] == tag(i));
        fill(p, old, size);
    }
    /* A second big block does not get the region while the first lives. */
    uint8_t *other = msrt_realloc(msrt_alloc(GROW_MIN / 2), GROW_MIN);
    CHECK(other != home);
    msrt_free(other);
    /* Shrinking below the threshold moves the bytes out and frees the region. */
    uint8_t *q = msrt_realloc(p, 1000);
    CHECK(q != home);
    for (size_t i = 0; i < 1000; i += 7) CHECK(q[i] == tag(i));
    uint8_t *again = msrt_realloc(msrt_alloc(GROW_MIN / 2), GROW_MIN);
    CHECK(again == home);
    msrt_free(again);
    msrt_free(q);
    msrt_free(small);
    CHECK(msalloc_live_blocks() == before);
}

static void large_classes_round_trip(void) {
    CHECK(msalloc_large_size(0) == 4096);
    CHECK(msalloc_large_size(1) == 5120);
    CHECK(msalloc_large_size(4) == 8192);
    CHECK(msalloc_large_size(MSALLOC_NUM_LARGE - 1) == MSALLOC_LARGE_MAX);
    for (size_t size = MSALLOC_MAX_SMALL + 1; size <= MSALLOC_LARGE_MAX; size += 997) {
        size_t r = msrt_heap_large_request(size);
        CHECK(r >= size && (r == 4096 || r <= size + size / 4 + 1));
        CHECK(msrt_heap_large_request(r) == r);
    }
}

static void large_blocks_are_reused(void) {
    uint8_t *a = msrt_alloc(100000);
    /* The system may round a block up past its class (macOS does); a freed block is filed under the
     * largest class that fits its usable size. */
    size_t usable = ms_sys_malloc_size(a);
    size_t size = usable;
    while (msrt_heap_large_request(size) != size) size--;
    a[99999] = 7;
    msrt_free(a);
    uint8_t *b = msrt_alloc(size);
    CHECK(a == b);
    uint8_t *z = msrt_heap_alloc_zeroed_cached(size);
    CHECK(z == 0); /* the cache is empty again */
    msrt_free(b);
    z = msrt_heap_alloc_zeroed_cached(size);
    CHECK(z == a);
    for (size_t i = 0; i < size; i += 4093) CHECK(z[i] == 0);
    msrt_free(z);
}

static void many_blocks_across_pages(void) {
    int64_t before = msalloc_live_blocks();
    enum { COUNT = 20000 };
    static uint8_t *v[COUNT];
    for (size_t i = 0; i < COUNT; i++) {
        v[i] = msrt_alloc(16 + (i % 17) * 16);
        *v[i] = (uint8_t)i;
    }
    for (size_t i = 0; i < COUNT; i++) CHECK(*v[i] == (uint8_t)i);
    for (size_t i = 0; i < COUNT; i++) msrt_free(v[i]);
    CHECK(msalloc_live_blocks() == before);
}

static void *thread_release_heap(void *arg) {
    uintptr_t *out = arg;
    msrt_heap_claim();
    uint8_t *p = msrt_alloc(64);
    memset(p, 0xAB, 64);
    uint8_t *keep = msrt_alloc(64);
    msrt_free(keep);
    out[0] = (uintptr_t)p;
    out[1] = (uintptr_t)keep;
    msrt_heap_release();
    return 0;
}

static void *thread_adopt_heap(void *arg) {
    msrt_heap_claim();
    /* The adopted free list hands back the block freed before the first thread ended. */
    CHECK((uintptr_t)msrt_alloc(64) == *(uintptr_t *)arg);
    msrt_heap_release();
    return 0;
}

static void a_released_heap_is_adopted_with_its_blocks(void) {
    uintptr_t blocks[2];
    pthread_t t;
    pthread_create(&t, 0, thread_release_heap, blocks);
    pthread_join(t, 0);
    /* A block outlives its thread, and any thread frees it. */
    CHECK(*(uint8_t *)blocks[0] == 0xAB);
    CHECK(msrt_heap_usable_size((void *)blocks[0]) == 64);
    msrt_free((void *)blocks[0]);
    pthread_create(&t, 0, thread_adopt_heap, &blocks[1]);
    pthread_join(t, 0);
}

static pthread_barrier_t gate;

static void *thread_many_heaps(void *arg) {
    (void)arg;
    msrt_heap_claim();
    void *p = msrt_alloc(100);
    CHECK(msrt_heap_has());
    pthread_barrier_wait(&gate);
    msrt_free(p);
    pthread_barrier_wait(&gate);
    msrt_heap_release();
    return 0;
}

static void more_than_256_heaps_exist_at_once(void) {
    enum { N = 300 };
    pthread_t t[N];
    pthread_barrier_init(&gate, 0, N);
    for (int i = 0; i < N; i++) pthread_create(&t[i], 0, thread_many_heaps, 0);
    for (int i = 0; i < N; i++) pthread_join(t[i], 0);
    pthread_barrier_destroy(&gate);
}

/* The shared large-block lists and the idle-heap list sit behind a spin lock that yields: many more threads
 * than cores allocating and freeing large blocks, and claiming and releasing heaps, must all finish. */
static void *thread_spin(void *arg) {
    size_t t = (size_t)arg;
    for (int round = 0; round < 40; round++) {
        msrt_heap_claim();
        for (size_t i = 0; i < 200; i++) {
            size_t size = MSALLOC_MAX_SMALL + 1 + (i * 37 + t) % 20000;
            uint8_t *p = msrt_alloc(size);
            CHECK(p != 0);
            p[0] = (uint8_t)round;
            p[size - 1] = (uint8_t)i;
            msrt_free(p);
        }
        msrt_heap_release();
    }
    return 0;
}

static void the_spin_lock_survives_more_threads_than_cores(void) {
    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    size_t n = 4 * (size_t)(cores > 0 ? cores : 4);
    pthread_t *t = malloc(n * sizeof *t);
    for (size_t i = 0; i < n; i++) pthread_create(&t[i], 0, thread_spin, (void *)i);
    for (size_t i = 0; i < n; i++) pthread_join(t[i], 0);
    free(t);
}

static void *thread_foreign(void *arg) {
    uintptr_t *b = arg; /* small, large, grown */
    msrt_heap_claim();
    void *small = msrt_realloc((void *)b[0], 3000);
    msrt_free(small);
    msrt_free((void *)b[1]);
    uint8_t *g = msrt_realloc((void *)b[2], GROW_MIN * 3);
    CHECK(g[GROW_MIN * 2 - 1] == 0x5A);
    msrt_free(g);
    msrt_heap_release();
    return 0;
}

static void every_kind_of_block_frees_and_resizes_on_any_thread(void) {
    uintptr_t b[3];
    b[0] = (uintptr_t)msrt_alloc(48);
    b[1] = (uintptr_t)msrt_alloc(100000);
    uint8_t *grown = msrt_realloc(msrt_alloc(GROW_MIN / 2), GROW_MIN * 2);
    memset(grown, 0x5A, GROW_MIN * 2);
    b[2] = (uintptr_t)grown;
    pthread_t t;
    pthread_create(&t, 0, thread_foreign, b);
    pthread_join(t, 0);
    /* The foreign free cleared the growth chunk, so its owner can grow a buffer again. */
    uint8_t *again = msrt_realloc(msrt_alloc(GROW_MIN / 2), GROW_MIN);
    CHECK(again == grown);
    msrt_free(again);
}

static void *thread_free_remote(void *arg) {
    msrt_free(arg);
    return 0;
}

static void remote_free_returns_to_owner_and_leaves_the_count(void) {
    void *p = msrt_alloc(48);
    int64_t before[2], after[2];
    msrt_heap_stats(before);
    pthread_t t;
    pthread_create(&t, 0, thread_free_remote, p);
    pthread_join(t, 0);
    /* No allocation has drained the remote stack, yet the block no longer counts as used. */
    msrt_heap_stats(after);
    CHECK(before[0] - after[0] == 48);
    /* The owner's next slow-path allocation drains the remote stack. */
    bool got = false;
    enum { N = 4096 };
    static void *v[N];
    for (int i = 0; i < N; i++) {
        v[i] = msrt_alloc(48);
        got |= v[i] == p;
    }
    CHECK(got);
    for (int i = 0; i < N; i++) msrt_free(v[i]);
}

/* A reservation the system refuses above `limit` bytes per mapping is halved until the sizes fit and then
 * quartered again to leave room; every refused attempt gives back what it mapped. */
static size_t map_limit;
static struct { void *p; size_t len; } mapped[64];
static size_t mapped_n;

static void *limited_map(size_t len) {
    if (len > map_limit) return 0;
    void *p = ms_sys_map_anon(len);
    mapped[mapped_n].p = p;
    mapped[mapped_n++].len = len;
    return p;
}

static void limited_unmap(void *p, size_t len) {
    ms_sys_unmap(p, len);
    for (size_t i = 0; i < mapped_n; i++) {
        if (mapped[i].p == p) mapped[i] = mapped[--mapped_n];
    }
}

static void *refuse_map(size_t len) {
    (void)len;
    return 0;
}

static void never_unmap(void *p, size_t len) {
    (void)p;
    (void)len;
    CHECK(false);
}

static void a_refused_reservation_is_halved_until_it_fits(void) {
    const size_t pages = (size_t)256 << 30, grow = ((size_t)1 << 30) * 1024;
    for (unsigned shrink = 0; shrink <= 10; shrink += shrink == 0 ? 3 : 7) {
        map_limit = grow >> shrink;
        mapped_n = 0;
        msalloc_region r;
        CHECK(msalloc_reserve(limited_map, limited_unmap, &r));
        unsigned kept = shrink == 0 ? 0 : (shrink + 2 < 10 ? shrink + 2 : 10);
        CHECK(r.pages_len == pages >> kept);
        CHECK((size_t)1 << r.grow_bits == ((size_t)1 << 30) >> kept);
        CHECK(mapped_n == 3); /* only the accepted mappings stay */
        for (size_t i = 0; i < mapped_n; i++) ms_sys_unmap(mapped[i].p, mapped[i].len);
    }
    msalloc_region r;
    CHECK(!msalloc_reserve(refuse_map, never_unmap, &r));
}

static void sampling_calls_the_hook_every_period(void) {
    static int calls;
    calls = 0;
    int64_t hook(size_t size) {
        (void)size;
        calls++;
        return 10;
    }
    msrt_heap_sample_every(10, (void *)hook);
    for (int i = 0; i < 100; i++) msrt_free(msrt_alloc(32));
    CHECK(calls == 10);
    msrt_heap_sample_every(INT64_MAX / 2, (void *)hook);
}

static void requested_counts_allocations(void) {
    uint64_t a[2], b[2];
    msrt_heap_requested(a);
    msrt_free(msrt_alloc(100));
    msrt_free(msrt_alloc(200));
    msrt_heap_requested(b);
    CHECK(b[0] - a[0] == 2 && b[1] - a[1] == 300);
}

int main(void) {
    msrt_heap_claim();
    CHECK(msrt_heap_has());
    classes_cover_sizes();
    alloc_free_reuse_and_realloc();
    zeroed_and_trim();
    growing_a_big_block_keeps_its_bytes();
    a_growing_block_extends_in_place_and_shrinks_out();
    large_classes_round_trip();
    large_blocks_are_reused();
    many_blocks_across_pages();
    a_released_heap_is_adopted_with_its_blocks();
    more_than_256_heaps_exist_at_once();
    the_spin_lock_survives_more_threads_than_cores();
    every_kind_of_block_frees_and_resizes_on_any_thread();
    remote_free_returns_to_owner_and_leaves_the_count();
    a_refused_reservation_is_halved_until_it_fits();
    sampling_calls_the_hook_every_period();
    requested_counts_allocations();
    puts("core_alloc: ok");
    return 0;
}
