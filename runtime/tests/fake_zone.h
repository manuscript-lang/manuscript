/* Weak stand-ins for the zone database the time natives call (crates/ms-std-time): every named zone is unknown.
 * A test that needs zones defines the two functions itself. */
#ifndef MS_TEST_FAKE_ZONE_H
#define MS_TEST_FAKE_ZONE_H
#include <stdint.h>

uint8_t msstd_time_zone_info(const void *zone, int64_t unix_seconds, void *out);
uint8_t msstd_time_zone_local_offset(const void *zone, int64_t year, int64_t month, int64_t day, int64_t hour,
                                     int64_t minute, int64_t second, int64_t nanosecond, int64_t *offset);

__attribute__((weak)) uint8_t msstd_time_zone_info(const void *zone, int64_t unix_seconds, void *out) {
    (void)zone;
    (void)unix_seconds;
    (void)out;
    return 1;
}
__attribute__((weak)) uint8_t msstd_time_zone_local_offset(const void *zone, int64_t year, int64_t month, int64_t day,
                                                           int64_t hour, int64_t minute, int64_t second,
                                                           int64_t nanosecond, int64_t *offset) {
    (void)zone;
    (void)year;
    (void)month;
    (void)day;
    (void)hour;
    (void)minute;
    (void)second;
    (void)nanosecond;
    (void)offset;
    return 1;
}
#endif
