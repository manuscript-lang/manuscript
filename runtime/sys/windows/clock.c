/* The monotonic clock on Windows. */
#include "ms_rt/sys.h"
#include "winapi.h"

#define MS_NANOSECONDS_PER_SECOND INT64_C(1000000000)

int64_t ms_sys_monotonic_ns(void) {
    int64_t frequency = 0;
    int64_t count = 0;
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&count);
    if (frequency < 1) {
        frequency = 1; /* cannot happen on supported Windows versions */
    }
    /* Whole seconds and the remainder separately, so count * 1e9 cannot overflow after long uptimes. */
    const int64_t seconds = count / frequency;
    const int64_t remainder = count % frequency;
    return seconds * MS_NANOSECONDS_PER_SECOND + remainder * MS_NANOSECONDS_PER_SECOND / frequency;
}
