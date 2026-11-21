/* Unit test of the sampling profiler's clock (runtime/sys/posix/sampler.c, runtime/sys/windows/sampler.c). Run by `make c-test`. */
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

#include "ms_rt/sys.h"

#define CHECK(c)                                                  \
    do {                                                          \
        if (!(c)) {                                               \
            fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #c); \
            exit(1);                                              \
        }                                                         \
    } while (0)

/* On Unix the sample runs in a handler on the target thread; on Windows a sampler thread reads it while suspended. */
#ifdef _WIN32
#define SAMPLE_ON_TARGET false
#else
#define SAMPLE_ON_TARGET true
#endif

static _Atomic int samples;
static _Atomic int bad;
static int token;

static void count(uintptr_t pc, uintptr_t fp, bool on_target, void *context) {
    if (pc == 0 || on_target != SAMPLE_ON_TARGET || context != &token) {
        atomic_store(&bad, 1);
    }
    (void)fp;
    atomic_fetch_add(&samples, 1);
}

/* Spends CPU time, which is what the clock counts. */
static void burn(int64_t nanos) {
    volatile uint64_t sink = 0;
    const int64_t until = ms_sys_monotonic_ns() + nanos;
    while (ms_sys_monotonic_ns() < until) {
        sink += 1;
    }
}

int main(void) {
    CHECK(!ms_sys_sampler_start(0, count, &token));
    CHECK(!ms_sys_sampler_start(10001, count, &token));
    CHECK(ms_sys_sampler_start(1000, count, &token));
    CHECK(!ms_sys_sampler_start(1000, count, &token));
    burn(300 * 1000000LL);
    ms_sys_sampler_stop();
    const int taken = atomic_load(&samples);
    CHECK(taken >= 20);
    CHECK(atomic_load(&bad) == 0);
    burn(50 * 1000000LL);
    CHECK(atomic_load(&samples) == taken);
    /* It can start again after a stop. */
    CHECK(ms_sys_sampler_start(1000, count, &token));
    burn(100 * 1000000LL);
    ms_sys_sampler_stop();
    CHECK(atomic_load(&samples) > taken);
    puts("sys_sampler ok");
    return 0;
}
