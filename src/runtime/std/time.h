/* ms_rt/time.h: the @std/time natives (src/runtime/std/time*.c). A Duration is an int64_t of nanoseconds
 * passed by value. A Timestamp (seconds since the Unix epoch and a nanosecond part) and an Instant (a clock
 * domain and a tick) are passed by pointer, and a result record is written through the trailing `out`. A
 * function that can fail returns an MsStatus and writes *out only on success; arithmetic that overflows
 * faults with a message. Zones are resolved in Manuscript (stdlib/internal/zone.ms), which reads the bundled
 * database through msstd_time_zone_data: the natives here take the offset east of UTC and the zone's name. */
#ifndef MS_RUNTIME_STD_TIME_H
#define MS_RUNTIME_STD_TIME_H

#include "base/list.h"
#include "base/safe.h"
#include "abi/status.h"
#include "base/string.h"

typedef struct MsTimestamp {
  int64_t seconds;
  int64_t nanos;
} MsTimestamp;

typedef struct MsInstant {
  uint64_t domain;
  int64_t tick;
} MsInstant;

/* A Timestamp broken down in a zone: the Date fields in declaration order, then the zone name. */
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
  MsString zone;
} MsCalendar;

/* ms-sig: msstd_time_duration_add(left: i64, other: i64) -> i64 @domain=time */
int64_t msstd_time_duration_add(int64_t left, int64_t other);
/* ms-sig: msstd_time_duration_plus(left: i64, right: i64) -> i64 @domain=time */
int64_t msstd_time_duration_plus(int64_t left, int64_t right);
/* ms-sig: msstd_time_duration_minus(left: i64, right: i64) -> i64 @domain=time */
int64_t msstd_time_duration_minus(int64_t left, int64_t right);
/* ms-sig: msstd_time_duration_subtract(left: i64, other: i64) -> i64 @domain=time */
int64_t msstd_time_duration_subtract(int64_t left, int64_t other);
/* ms-sig: msstd_time_int_milliseconds(n: i64) -> i64 @domain=time */
int64_t msstd_time_int_milliseconds(int64_t n);
/* ms-sig: msstd_time_int_seconds(n: i64) -> i64 @domain=time */
int64_t msstd_time_int_seconds(int64_t n);
/* ms-sig: msstd_time_int_minutes(n: i64) -> i64 @domain=time */
int64_t msstd_time_int_minutes(int64_t n);
/* ms-sig: msstd_time_duration_multiply(value: i64, factor: i64) -> i64 @domain=time */
int64_t msstd_time_duration_multiply(int64_t value, int64_t factor);
/* ms-sig: msstd_time_duration_divide(value: i64, divisor: i64) -> i64 @domain=time */
int64_t msstd_time_duration_divide(int64_t value, int64_t divisor);
/* ms-sig: msstd_time_duration_negate(value: i64) -> i64 @domain=time */
int64_t msstd_time_duration_negate(int64_t value);
/* ms-sig: msstd_time_duration_abs(value: i64) -> i64 @domain=time */
int64_t msstd_time_duration_abs(int64_t value);
/* ms-sig: msstd_time_duration_compare(left: i64, other: i64) -> i64 @domain=time */
int64_t msstd_time_duration_compare(int64_t left, int64_t other);
/* ms-sig: msstd_time_duration_to_microseconds(value: i64) -> i64 @domain=time */
int64_t msstd_time_duration_to_microseconds(int64_t value);
/* ms-sig: msstd_time_duration_to_milliseconds(value: i64) -> i64 @domain=time */
int64_t msstd_time_duration_to_milliseconds(int64_t value);
/* ms-sig: msstd_time_duration_to_seconds(value: i64) -> f64 @domain=time */
double msstd_time_duration_to_seconds(int64_t value);
/* ms-sig: msstd_time_duration_to_minutes(value: i64) -> f64 @domain=time */
double msstd_time_duration_to_minutes(int64_t value);
/* ms-sig: msstd_time_duration_to_hours(value: i64) -> f64 @domain=time */
double msstd_time_duration_to_hours(int64_t value);

/* ms-sig: msstd_time_instant_shift(value: *const Instant, duration: i64, out: *mut Instant) @domain=time */
void msstd_time_instant_shift(const MsInstant *value, int64_t duration, MsInstant *out);
/* ms-sig: msstd_time_instant_unshift(value: *const Instant, duration: i64, out: *mut Instant) @domain=time */
void msstd_time_instant_unshift(const MsInstant *value, int64_t duration, MsInstant *out);
/* ms-sig: msstd_time_instant_difference(left: *const Instant, other: *const Instant) -> i64 @domain=time */
int64_t msstd_time_instant_difference(const MsInstant *left, const MsInstant *other);
/* ms-sig: msstd_time_instant_compare(left: *const Instant, other: *const Instant) -> i64 @domain=time */
int64_t msstd_time_instant_compare(const MsInstant *left, const MsInstant *other);
/* ms-sig: msstd_time_instant_equal(left: *const Instant, other: *const Instant) -> u8 @domain=time */
uint8_t msstd_time_instant_equal(const MsInstant *left, const MsInstant *other);
/* ms-sig: msstd_time_clock_now(out: *mut Instant) @domain=time */
void msstd_time_clock_now(MsInstant *out);
/* ms-sig: msstd_time_wall_clock_now(out: *mut Timestamp) @domain=time */
void msstd_time_wall_clock_now(MsTimestamp *out);

/* ms-sig: msstd_time_parse_timestamp(text: *const StrVal, out: *mut Timestamp) -> u8 @domain=time */
uint8_t msstd_time_parse_timestamp(const MsString *text, MsTimestamp *out);
/* ms-sig: msstd_time_timestamp_to_string(value: *const Timestamp, out: *mut StrVal) @domain=time */
void msstd_time_timestamp_to_string(const MsTimestamp *value, MsString *out);
/* ms-sig: msstd_time_timestamp_calendar(value: *const Timestamp, offset: i64, zone: *const StrVal, out: *mut
 * CalendarOut) @domain=time */
void msstd_time_timestamp_calendar(const MsTimestamp *value, int64_t offset, const MsString *zone,
                                   MsCalendar *out);
/* ms-sig: msstd_time_timestamp_format(value: *const Timestamp, pattern: *const StrVal, offset: i64, zone:
 * *const StrVal, out: *mut StrVal) @domain=time */
void msstd_time_timestamp_format(const MsTimestamp *value, const MsString *pattern, int64_t offset,
                                 const MsString *zone, MsString *out);
/* ms-sig: msstd_time_local_from_calendar(year: i64, month: i64, day: i64, hour: i64, minute: i64, second:
 * i64, nanosecond: i64, out: *mut i64) -> u8 @domain=time */
uint8_t msstd_time_local_from_calendar(int64_t year, int64_t month, int64_t day, int64_t hour, int64_t minute,
                                       int64_t second, int64_t nanosecond, int64_t *out);
/* ms-sig: msstd_time_from_local(local: i64, nanosecond: i64, offset: i64, out: *mut Timestamp) -> u8
 * @domain=time */
uint8_t msstd_time_from_local(int64_t local, int64_t nanosecond, int64_t offset, MsTimestamp *out);
/* ms-sig: msstd_time_system_zone(out: *mut StrVal) @domain=time */
void msstd_time_system_zone(MsString *out);
/* ms-sig: msstd_time_system_zone_file(out: *mut VecVal) -> u8 @domain=time */
uint8_t msstd_time_system_zone_file(MsList *out);
/* ms-sig: msstd_time_zone_data(name: *const StrVal, out: *mut VecVal) @domain=time */
void msstd_time_zone_data(const MsString *name, MsList *out);
/* ms-sig: msstd_time_error_message(status: u8, out: *mut StrVal) @domain=time */
void msstd_time_error_message(uint8_t status, MsString *out);

#endif
