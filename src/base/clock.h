/* base/clock.h: a monotonic clock for measuring how long a step took. */
#ifndef MS_BASE_CLOCK_H
#define MS_BASE_CLOCK_H

#include <stdbool.h>
#include <stdint.h>

/* Nanoseconds from an arbitrary fixed point; it never goes backwards. */
int64_t ms_clock_ns(void);

/* `MS_BUILD_TIMES` set to anything but 0 prints how long each step of a build took, in milliseconds. */
bool ms_build_times_enabled(void);

/* With `report`, prints the time since `*mark` as the step `step` (to stderr); either way `*mark` becomes now. */
void ms_build_time_step(bool report, const char *step, int64_t *mark);

#endif
