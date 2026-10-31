#define _POSIX_C_SOURCE 200809L
#include <time.h>
#include <stdint.h>
int64_t codec_bench_cpu_ns(void) {
    struct timespec at;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &at) != 0) return -1;
    return (int64_t)at.tv_sec * 1000000000 + at.tv_nsec;
}
