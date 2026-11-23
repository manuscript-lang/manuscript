/* Clocks for the @std/time natives: the wall clock and the process monotonic clock, over libuv on every platform. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <stdatomic.h>
#include <uv.h>

#include "runtime/std/time_internal.h"

MsTimestamp ms_clock_realtime(void) {
  uv_timespec64_t now = {0};
  (void)uv_clock_gettime(UV_CLOCK_REALTIME, &now);
  return (MsTimestamp){.seconds = now.tv_sec, .nanos = now.tv_nsec};
}

/* Does not count sleep on macOS, like std::time::Instant. */
static int64_t monotonic_nanoseconds(void) { return (int64_t)uv_hrtime(); }

/* The first reading, taken once by whichever thread asks first; INT64_MIN until then. */
static _Atomic int64_t first_reading = INT64_MIN;

int64_t ms_clock_monotonic_since_start(void) {
  int64_t start = atomic_load(&first_reading);
  if (start == INT64_MIN) {
    int64_t first = monotonic_nanoseconds();
    if (!atomic_compare_exchange_strong(&first_reading, &start, first)) {
      first = start; /* another thread won; `start` now holds its reading */
    }
    start = first;
  }
  return monotonic_nanoseconds() - start; /* read after the start is fixed, so never negative */
}
