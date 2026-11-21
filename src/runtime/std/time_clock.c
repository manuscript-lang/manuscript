/* Clocks for the @std/time natives: the wall clock and the process monotonic clock, for POSIX and Windows. */
#ifndef __APPLE__ /* Apple hides CLOCK_UPTIME_RAW once _POSIX_C_SOURCE is set, and needs no macro for clock_gettime */
#define _POSIX_C_SOURCE 200809L // NOLINT(cert-dcl37-c,cert-dcl51-cpp): clock_gettime under -std=c11
#endif
#include <stdatomic.h>

#include "time_internal.h"

#ifdef _WIN32
#include <windows.h>

enum {
    FILETIME_TICKS_PER_SECOND = 10000000,
    NANOS_PER_FILETIME_TICK = 100,
};
/* 100 ns ticks from 1601-01-01 to 1970-01-01. */
#define FILETIME_UNIX_EPOCH INT64_C(116444736000000000)

MsTimestamp ms_clock_realtime(void) {
    FILETIME now;
    GetSystemTimePreciseAsFileTime(&now);
    const int64_t ticks = (int64_t)(((uint64_t)now.dwHighDateTime << 32) | now.dwLowDateTime) - FILETIME_UNIX_EPOCH;
    int64_t seconds = ticks / FILETIME_TICKS_PER_SECOND;
    int64_t rest = ticks % FILETIME_TICKS_PER_SECOND;
    if (rest < 0) {
        seconds--;
        rest += FILETIME_TICKS_PER_SECOND;
    }
    return (MsTimestamp){.seconds = seconds, .nanos = rest * NANOS_PER_FILETIME_TICK};
}

static int64_t monotonic_nanoseconds(void) {
    LARGE_INTEGER frequency, counter;
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&counter);
    const int64_t whole = counter.QuadPart / frequency.QuadPart;
    const int64_t rest = counter.QuadPart % frequency.QuadPart;
    return whole * MS_NANOS_PER_SECOND + rest * MS_NANOS_PER_SECOND / frequency.QuadPart;
}
#else
#include <time.h>

MsTimestamp ms_clock_realtime(void) {
    struct timespec now;
    (void)clock_gettime(CLOCK_REALTIME, &now);
    return (MsTimestamp){.seconds = (int64_t)now.tv_sec, .nanos = (int64_t)now.tv_nsec};
}

static int64_t monotonic_nanoseconds(void) {
#ifdef __APPLE__
    const clockid_t clock = CLOCK_UPTIME_RAW; /* does not count sleep, like std::time::Instant */
#else
    const clockid_t clock = CLOCK_MONOTONIC;
#endif
    struct timespec now;
    (void)clock_gettime(clock, &now);
    return (int64_t)now.tv_sec * MS_NANOS_PER_SECOND + (int64_t)now.tv_nsec;
}
#endif

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
