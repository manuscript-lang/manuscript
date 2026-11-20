/* ms_rt/time.h: the @std/time natives (runtime/std/time*.c). A Duration is an int64_t of nanoseconds passed by
 * value. A Timestamp (seconds since the Unix epoch and a nanosecond part) and an Instant (a clock domain and a
 * tick) are passed by pointer, and a result record is written through the trailing `out`. A function that can fail
 * returns an MsStatus and writes *out only on success; arithmetic that overflows faults with a message. */
#ifndef MS_RT_TIME_H
#define MS_RT_TIME_H

#include "ms_rt/base.h"
#include "ms_rt/runtime.h"
#include "ms_rt/string.h"

typedef struct MsTimestamp {
    int64_t seconds;
    int64_t nanos;
} MsTimestamp;

typedef struct MsInstant {
    uint64_t domain;
    int64_t tick;
} MsInstant;

/* A Timestamp broken down in a zone: the Date fields in declaration order, then the zone abbreviation. */
typedef struct MsCalendar {
    int64_t year;
    int64_t month;
    int64_t day;
    int64_t hour;
    int64_t minute;
    int64_t second;
    int64_t nanosecond;
    int64_t weekday;     /* Sunday is 0 */
    int64_t day_of_year; /* January 1 is 1 */
    int64_t offset_seconds;
    ms_str zone;
} MsCalendar;

int64_t msstd_time_duration_add(int64_t left, int64_t other);
int64_t msstd_time_duration_plus(int64_t left, int64_t right);
int64_t msstd_time_duration_minus(int64_t left, int64_t right);
int64_t msstd_time_duration_subtract(int64_t left, int64_t other);
int64_t msstd_time_int_milliseconds(int64_t n);
int64_t msstd_time_int_seconds(int64_t n);
int64_t msstd_time_int_minutes(int64_t n);
int64_t msstd_time_duration_multiply(int64_t value, int64_t factor);
int64_t msstd_time_duration_divide(int64_t value, int64_t divisor);
int64_t msstd_time_duration_negate(int64_t value);
int64_t msstd_time_duration_abs(int64_t value);
int64_t msstd_time_duration_compare(int64_t left, int64_t other);
int64_t msstd_time_duration_to_microseconds(int64_t value);
int64_t msstd_time_duration_to_milliseconds(int64_t value);
double msstd_time_duration_to_seconds(int64_t value);
double msstd_time_duration_to_minutes(int64_t value);
double msstd_time_duration_to_hours(int64_t value);

void msstd_time_instant_shift(const MsInstant *value, int64_t duration, MsInstant *out);
void msstd_time_instant_unshift(const MsInstant *value, int64_t duration, MsInstant *out);
int64_t msstd_time_instant_difference(const MsInstant *left, const MsInstant *other);
int64_t msstd_time_instant_compare(const MsInstant *left, const MsInstant *other);
uint8_t msstd_time_instant_equal(const MsInstant *left, const MsInstant *other);
void msstd_time_clock_now(MsInstant *out);
void msstd_time_wall_clock_now(MsTimestamp *out);

uint8_t msstd_time_parse_timestamp(const ms_str *text, MsTimestamp *out);
void msstd_time_timestamp_to_string(const MsTimestamp *value, ms_str *out);
uint8_t msstd_time_timestamp_calendar(const MsTimestamp *value, const ms_str *zone, MsCalendar *out);
uint8_t msstd_time_timestamp_format(const MsTimestamp *value, const ms_str *pattern, const ms_str *zone, ms_str *out);
uint8_t msstd_time_from_calendar(int64_t year, int64_t month, int64_t day, int64_t hour, int64_t minute, int64_t second, int64_t nanosecond, const ms_str *zone, MsTimestamp *out);
void msstd_time_error_message(uint8_t status, ms_str *out);

#endif
