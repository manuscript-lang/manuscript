/* base/clock.h: a monotonic clock for measuring how long a step took. */
#ifndef MS_BASE_CLOCK_H
#define MS_BASE_CLOCK_H

#include <stdint.h>

/* Nanoseconds from an arbitrary fixed point; it never goes backwards. */
int64_t ms_clock_ns(void);

#endif
