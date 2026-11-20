/* What the @std/time sources share (ms_rt/time.h is the ABI): calendar arithmetic, zones and clocks. */
#ifndef MS_STD_TIME_INTERNAL_H
#define MS_STD_TIME_INTERNAL_H

#include "ms_rt/time.h"

enum {
    MS_NANOS_PER_SECOND = 1000000000,
    MS_SECONDS_PER_DAY = 86400,
    /* Timestamps cover 0001-01-01T00:00:00Z to 9999-12-31T23:59:59Z. */
};
#define MS_MIN_SECONDS (-INT64_C(62135596800))
#define MS_MAX_SECONDS INT64_C(253402300799)

/* ---- calendar (time_civil.c): the proleptic Gregorian calendar on Unix seconds ---- */

/* Calendar fields of a local time. */
typedef struct MsCivil {
    int64_t year, month, day, hour, minute, second, nanosecond;
    int64_t weekday;     /* Sunday is 0 */
    int64_t day_of_year; /* January 1 is 1 */
} MsCivil;

int64_t ms_days_in_month(int64_t year, int64_t month);
/* Breaks local seconds (Unix seconds plus a zone offset; wraps like the offset sum does) into fields. */
MsCivil ms_civil_of(int64_t local_seconds, int64_t nanosecond);
/* Local seconds of a civil date (month 1..12, day within the month) and time of day. */
int64_t ms_local_seconds(int64_t year, int64_t month, int64_t day, int64_t hour, int64_t minute, int64_t second);

/* ---- zones (time_zone.c) ---- */

/* What a zone says about one instant. `name` is an owned string; release it with ms_zone_info_release. */
typedef struct MsZoneInfo {
    int64_t offset; /* seconds east of UTC */
    ms_str name;    /* the abbreviation, or the zone's own text for a fixed offset */
} MsZoneInfo;

/* Resolves UTC, "" (UTC), `+hh:mm` offsets, `Local` and IANA names (case-sensitive). */
MS_NODISCARD bool ms_zone_info_at(const ms_str *zone, int64_t unix_seconds, MsZoneInfo *out);
/* The offset for validated local fields; the earlier offset applies in a gap or a fold. False for an unknown
 * zone. */
MS_NODISCARD bool ms_zone_local_offset(const ms_str *zone, const MsCivil *local, int64_t *offset);
void ms_zone_info_release(MsZoneInfo *info);
/* Whether `zone` names a zone ms_zone_info_at resolves. */
bool ms_zone_known(const ms_str *zone);

/* The zone database, still read in Rust (crates/ms-std-time) and listed in rt_symbols.txt: returns a status, and
 * writes *out only on success (MS_STATUS_INVALID_INPUT for an unknown zone). */
uint8_t msstd_time_zone_info(const ms_str *zone, int64_t unix_seconds, MsZoneInfo *out);
uint8_t msstd_time_zone_local_offset(const ms_str *zone, int64_t year, int64_t month, int64_t day, int64_t hour,
                                     int64_t minute, int64_t second, int64_t nanosecond, int64_t *offset);

/* ---- clocks (time_clock.c) ---- */

MsTimestamp ms_clock_realtime(void);
/* Nanoseconds since the first reading in this process. */
int64_t ms_clock_monotonic_since_start(void);

#endif
