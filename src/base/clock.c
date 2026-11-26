#define _POSIX_C_SOURCE 200809L /* clock_gettime under -std=c17 */
#include "base/clock.h"

#include <stdio.h>

#include "base/env.h"
#include "base/string.h"

#if defined(_WIN32)
#include <windows.h>

int64_t ms_clock_ns(void) {
  static LARGE_INTEGER frequency;
  LARGE_INTEGER now;
  if (frequency.QuadPart == 0) {
    QueryPerformanceFrequency(&frequency);
  }
  QueryPerformanceCounter(&now);
  const int64_t seconds = now.QuadPart / frequency.QuadPart;
  const int64_t rest = now.QuadPart % frequency.QuadPart;
  return seconds * 1000000000 + rest * 1000000000 / frequency.QuadPart;
}
#else
#include <time.h>

int64_t ms_clock_ns(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (int64_t)now.tv_sec * 1000000000 + now.tv_nsec;
}
#endif

bool ms_build_times_enabled(void) {
  MsString value = ms_string_empty();
  const bool set = ms_env_get("MS_BUILD_TIMES", &value) && !ms_span_is_text(ms_string_span(&value), "0");
  ms_string_release(&value);
  return set;
}

void ms_build_time_step(bool report, const char *step, int64_t *mark) {
  const int64_t now = ms_clock_ns();
  if (report) {
    (void)fprintf(stderr, "ms build: %-8s %7.1f ms\n", step, (double)(now - *mark) / 1e6);
  }
  *mark = now;
}
