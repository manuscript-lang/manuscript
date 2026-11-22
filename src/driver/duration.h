/* driver/duration.h: command-line durations, in the syntax of the standard library's `time.parse_duration`. */
#ifndef MS_DRIVER_DURATION_H
#define MS_DRIVER_DURATION_H

#include "base/safe.h"

/* Parses `300ms`, `-1.5h` or `2h45m` to nanoseconds. False when the text is not a duration or overflows. */
MS_NODISCARD bool ms_duration_parse(MsSpan text, int64_t *nanoseconds);

#endif
