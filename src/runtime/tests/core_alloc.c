/* Unit tests for src/runtime/core/alloc.c, the msrt_* wrapper over mimalloc; `make c-test` builds them with
 * -DMS_ALLOC_STATS (live-block counts). */
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/alloc.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_alloc.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static void alloc_realloc_and_free(void) {
    const int64_t base = msalloc_live_blocks();
    uint8_t *p = msrt_alloc(100);
    CHECK(msalloc_live_blocks() == base + 1);
    memset(p, 7, 100);
    p = msrt_realloc(p, 100000);
    CHECK(p[0] == 7 && p[99] == 7);
    CHECK(msalloc_live_blocks() == base + 1);
    p = msrt_heap_trim(p, 50);
    CHECK(p[49] == 7);
    msrt_free(p);
    CHECK(msalloc_live_blocks() == base);
    msrt_free(NULL);
}

static void zeroed_blocks_are_zero(void) {
    for (size_t size = 1; size < 1 << 20; size = size * 3 + 1) {
        uint8_t *p = msrt_alloc_zeroed(size);
        for (size_t i = 0; i < size; i++) CHECK(p[i] == 0);
        memset(p, 0xff, size);
        msrt_free(p);
    }
}

static void *free_elsewhere(void *p) {
    msrt_heap_claim();
    msrt_free(p);
    msrt_heap_release();
    return NULL;
}

static void a_block_frees_on_any_thread(void) {
    const int64_t base = msalloc_live_blocks();
    for (int i = 0; i < 1000; i++) {
        void *p = msrt_alloc((size_t)i * 37 + 1);
        pthread_t t;
        CHECK(pthread_create(&t, NULL, free_elsewhere, p) == 0);
        pthread_join(t, NULL);
    }
    CHECK(msalloc_live_blocks() == base);
}

static int sampler_calls;
static int64_t count_sample(size_t size) {
    (void)size;
    sampler_calls++;
    return 10;
}

static void sampling_calls_the_hook_every_period(void) {
    sampler_calls = 0;
    msrt_heap_sample_every(10, (void *)count_sample);
    for (int i = 0; i < 100; i++) msrt_free(msrt_alloc(32));
    CHECK(sampler_calls == 10);
    msrt_heap_sample_every(INT64_MAX / 2, (void *)count_sample);
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
    alloc_realloc_and_free();
    zeroed_blocks_are_zero();
    a_block_frees_on_any_thread();
    sampling_calls_the_hook_every_period();
    requested_counts_allocations();
    puts("core_alloc: ok");
    return 0;
}
