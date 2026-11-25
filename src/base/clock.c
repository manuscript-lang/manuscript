#define _POSIX_C_SOURCE 200809L /* clock_gettime under -std=c17 */
#include "base/clock.h"

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
