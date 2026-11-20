/* The layout of the C library's `struct timespec` on the 64-bit Linux and macOS targets, so sys files need no
 * libc header. */
#ifndef MS_SYS_POSIX_TIMESPEC_H
#define MS_SYS_POSIX_TIMESPEC_H

#include <stdint.h>

typedef struct MsTimespec {
    int64_t seconds;
    int64_t nanoseconds;
} MsTimespec;

_Static_assert(sizeof(MsTimespec) == 16, "MsTimespec must match struct timespec");

#endif
