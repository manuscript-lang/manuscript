/* Unit tests for src/runtime/core/region.c; `make c-test` builds them with ASan and UBSan. */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/region.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_region.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static MsRegion *new_region(size_t budget) {
    MsRegion *region = NULL;
    CHECK(ms_region_new(budget, &region));
    return region;
}

static void *alloc_ok(MsRegion *region, size_t size) {
    void *block = NULL;
    CHECK(ms_region_alloc(region, size, &block));
    return block;
}

static void blocks_are_aligned_and_distinct(void) {
    MsRegion *region = new_region(1 << 20);
    const uint8_t *previous = NULL;
    for (size_t size = 1; size <= 500; size++) {
        uint8_t *block = alloc_ok(region, size);
        CHECK((uintptr_t)block % 16 == 0);
        CHECK(block != previous);
        memset(block, (int)size, size);
        previous = block;
    }
    CHECK(ms_region_used(region) > 0 && ms_region_held(region) <= ms_region_budget(region));
    ms_region_release(region);
}

static void over_the_budget_fails_and_changes_nothing(void) {
    MsRegion *region = new_region(8192);
    size_t granted = 0;
    void *block = NULL;
    while (ms_region_alloc(region, 1000, &block)) {
        granted++;
    }
    CHECK(granted >= 4 && granted <= 8);
    const size_t used = ms_region_used(region);
    const size_t held = ms_region_held(region);
    CHECK(held <= 8192);
    CHECK(!ms_region_alloc(region, 1 << 20, &block));
    CHECK(!ms_region_alloc(region, SIZE_MAX, &block));
    CHECK(ms_region_used(region) == used && ms_region_held(region) == held);
    ms_region_release(region);
    MsRegion *too_small = NULL;
    CHECK(!ms_region_new(10, &too_small) && too_small == NULL);
    ms_region_release(NULL);
}

static void a_big_request_gets_its_own_chunk(void) {
    MsRegion *region = new_region((size_t)4 << 20);
    memset(alloc_ok(region, (size_t)1 << 20), 0x42, (size_t)1 << 20);
    uint8_t *zeroed = NULL;
    CHECK(ms_region_alloc_zeroed(region, 100, (void **)&zeroed));
    for (size_t i = 0; i < 100; i++) {
        CHECK(zeroed[i] == 0);
    }
    void *block = NULL;
    CHECK(!ms_region_alloc(region, (size_t)4 << 20, &block));
    ms_region_release(region);
}

static void reset_reuses_the_first_chunk(void) {
    MsRegion *region = new_region(1 << 20);
    const void *first = alloc_ok(region, 64);
    for (int i = 0; i < 1000; i++) {
        (void)alloc_ok(region, 500);
    }
    CHECK(ms_region_held(region) > 4096);
    ms_region_reset(region);
    CHECK(ms_region_used(region) == 0 && ms_region_held(region) == 4096);
    CHECK(alloc_ok(region, 64) == first);
    ms_region_release(region);
}

static void *release_elsewhere(void *region) {
    ms_region_release(region);
    return NULL;
}

static void a_region_is_released_from_another_thread(void) {
    MsRegion *region = new_region(1 << 20);
    for (int i = 0; i < 100; i++) {
        (void)alloc_ok(region, 700);
    }
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, release_elsewhere, region) == 0);
    CHECK(pthread_join(thread, NULL) == 0);
}

int main(void) {
    msrt_heap_claim();
    blocks_are_aligned_and_distinct();
    over_the_budget_fails_and_changes_nothing();
    a_big_request_gets_its_own_chunk();
    reset_reuses_the_first_chunk();
    a_region_is_released_from_another_thread();
    puts("core_region: ok");
    return 0;
}
