/* The monotonic clock on Linux and macOS. */
#include "runtime/sys/sys.h"
#include "runtime/sys/posix/timespec.h"

extern int clock_gettime(int clock, MsTimespec *ts);

#ifdef __APPLE__
#define MS_CLOCK_MONOTONIC 6
#else
#define MS_CLOCK_MONOTONIC 1
#endif

#define MS_NANOSECONDS_PER_SECOND INT64_C(1000000000)

int64_t ms_sys_monotonic_ns(void) {
    MsTimespec now = {0};
    if (clock_gettime(MS_CLOCK_MONOTONIC, &now) != 0) {
        return 0; /* cannot fail for a valid clock id and pointer */
    }
    return now.seconds * MS_NANOSECONDS_PER_SECOND + now.nanoseconds;
}
