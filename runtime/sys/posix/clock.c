#include "ms_sys.h"

struct mssys_timespec {
    int64_t sec;
    int64_t nsec;
};

extern int clock_gettime(int clock, struct mssys_timespec *ts);

#ifdef __APPLE__
#define CLOCK_MONOTONIC 6
#else
#define CLOCK_MONOTONIC 1
#endif

int64_t mssys_monotonic_ns(void) {
    struct mssys_timespec t = {0, 0};
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.sec * 1000000000 + t.nsec;
}
