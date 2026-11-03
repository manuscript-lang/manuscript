import Calendar, Clock, Instant, Timestamp, WallClock from "@std/os/time.ms"

export extern fn msstd_time_duration_add(value: Int, other: Int) Int

export extern fn msstd_time_duration_subtract(value: Int, other: Int) Int

export extern fn msstd_time_duration_multiply(value: Int, factor: Int) Int

export extern fn msstd_time_duration_divide(value: Int, divisor: Int) Int

export extern fn msstd_time_duration_negate(value: Int) Int

export extern fn msstd_time_duration_abs(value: Int) Int

export extern fn msstd_time_duration_to_microseconds(value: Int) Int

export extern fn msstd_time_duration_to_milliseconds(value: Int) Int

export extern fn msstd_time_duration_to_seconds(value: Int) Float

export extern fn msstd_time_duration_to_minutes(value: Int) Float

export extern fn msstd_time_duration_to_hours(value: Int) Float

export extern fn msstd_time_local_zone() String

export extern fn msstd_time_sleep(duration: Int) Unit

export extern fn msstd_time_instant_shift(value: Instant, duration: Int) Instant

export extern fn msstd_time_instant_unshift(value: Instant, duration: Int) Instant

export extern fn msstd_time_instant_difference(value: Instant, other: Instant) Int

export extern fn msstd_time_instant_compare(value: Instant, other: Instant) Int

export extern fn msstd_time_timestamp_to_string(value: Timestamp) String

export extern fn msstd_time_timestamp_shift(value: Timestamp, duration: Int) Timestamp!

export extern fn msstd_time_timestamp_difference(
    value: Timestamp,
    other: Timestamp
) Int!

export extern fn msstd_time_timestamp_compare(value: Timestamp, other: Timestamp) Int

export extern fn msstd_time_timestamp_calendar(value: Timestamp, zone: String) Calendar!

export extern fn msstd_time_timestamp_format(
    value: Timestamp,
    pattern: String,
    zone: String
) String!

export extern fn msstd_time_parse_timestamp(text: String) Timestamp!

export extern fn msstd_time_from_calendar(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    nanosecond: Int,
    zone: String
) Timestamp!

export extern fn msstd_time_timestamp(seconds: Int, nanoseconds: Int) Timestamp!

export extern fn msstd_time_clock() Clock

export extern fn msstd_time_wall_clock() WallClock
