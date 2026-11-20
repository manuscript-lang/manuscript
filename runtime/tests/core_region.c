/* Unit tests for runtime/core/region.c; `make c-test` builds them with ASan and UBSan. */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "alloc.h"
#include "region.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_region.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static void blocks_are_aligned_and_distinct(void) {
    msregion *r = msregion_new(1 << 20);
    CHECK(r != 0);
    uint8_t *prev = 0;
    for (size_t i = 1; i <= 500; i++) {
        uint8_t *p = msregion_alloc(r, i);
        CHECK(p != 0 && (uintptr_t)p % 16 == 0);
        CHECK(p != prev);
        memset(p, (int)i, i);
        prev = p;
    }
    CHECK(msregion_used(r) > 0 && msregion_held(r) <= msregion_budget(r));
    msregion_release(r);
}

static void over_the_budget_fails_and_changes_nothing(void) {
    msregion *r = msregion_new(8192);
    CHECK(r != 0);
    size_t got = 0;
    while (msregion_alloc(r, 1000)) got++;
    CHECK(got >= 4 && got <= 8);
    size_t used = msregion_used(r), held = msregion_held(r);
    CHECK(held <= 8192);
    CHECK(msregion_alloc(r, 1 << 20) == 0);
    CHECK(msregion_used(r) == used && msregion_held(r) == held);
    /* Small requests still fit in what is held. */
    msregion_release(r);
    CHECK(msregion_new(10) == 0);
    msregion_release(0);
}

static void a_big_request_gets_its_own_chunk(void) {
    msregion *r = msregion_new((size_t)4 << 20);
    uint8_t *p = msregion_alloc(r, (size_t)1 << 20);
    CHECK(p != 0);
    memset(p, 0x42, (size_t)1 << 20);
    uint8_t *q = msregion_alloc_zeroed(r, 100);
    for (int i = 0; i < 100; i++) CHECK(q[i] == 0);
    CHECK(msregion_alloc(r, (size_t)4 << 20) == 0);
    msregion_release(r);
}

static void reset_reuses_the_first_chunk(void) {
    msregion *r = msregion_new(1 << 20);
    void *first = msregion_alloc(r, 64);
    for (int i = 0; i < 1000; i++) CHECK(msregion_alloc(r, 500) != 0);
    CHECK(msregion_held(r) > 4096);
    msregion_reset(r);
    CHECK(msregion_used(r) == 0 && msregion_held(r) == 4096);
    CHECK(msregion_alloc(r, 64) == first);
    msregion_release(r);
}

static void *release_elsewhere(void *r) {
    msregion_release(r);
    return 0;
}

static void a_region_is_released_from_another_thread(void) {
    msregion *r = msregion_new(1 << 20);
    for (int i = 0; i < 100; i++) CHECK(msregion_alloc(r, 700) != 0);
    pthread_t t;
    pthread_create(&t, 0, release_elsewhere, r);
    pthread_join(t, 0);
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
