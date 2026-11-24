import (
	Bytes from "@std/bytes.ms",
	Date, Instant, Timestamp from "@std/time.ms",
)

export extern fn msstd_time_duration_add(value Int, other Int) Int

export extern fn msstd_time_duration_subtract(value Int, other Int) Int

export extern fn msstd_time_duration_multiply(value Int, factor Int) Int

export extern fn msstd_time_duration_divide(value Int, divisor Int) Int

export extern fn msstd_time_duration_negate(value Int) Int

export extern fn msstd_time_duration_abs(value Int) Int

export extern fn msstd_time_duration_to_microseconds(value Int) Int

export extern fn msstd_time_duration_to_milliseconds(value Int) Int

export extern fn msstd_time_duration_to_seconds(value Int) Float

export extern fn msstd_time_duration_to_minutes(value Int) Float

export extern fn msstd_time_duration_to_hours(value Int) Float

// The bundled zone database's entry for an exact name (a TZif version 2+ block, or an
// IANA name for
// `windows/<key>`), or empty Bytes when there is null.
export extern fn msstd_time_zone_data(name String) move Bytes

// How the host names its zone: `tz:NAME` from the TZ setting, `link:NAME` from
// /etc/localtime, `windows:KEY` from the system setting, or `` when it does not.
export extern fn msstd_time_system_zone() move String

// The whole of the system zone file (/etc/localtime), or empty Bytes when there is
// null.
export extern fn msstd_time_system_zone_file() move Bytes!

// Validates calendar fields and returns their local seconds (the fields read as UTC); a
// field out of its range returns `ERANGE`.
export extern fn msstd_time_local_from_calendar(
	year Int,
	month Int,
	day Int,
	hour Int,
	minute Int,
	second Int,
	nanosecond Int,
) Int!

// The timestamp of local seconds in a zone `offset` seconds east of UTC; outside years
// 1 to 9999 returns
// `ERANGE`.
export extern fn msstd_time_from_local(
	local Int,
	nanosecond Int,
	offset Int,
) move Timestamp!

export extern fn msstd_time_instant_shift(value Instant, duration Int) Instant

export extern fn msstd_time_instant_difference(value Instant, other Instant) Int

export extern fn msstd_time_instant_compare(value Instant, other Instant) Int

export extern fn msstd_time_timestamp_to_string(value Timestamp) move String

export extern fn msstd_time_timestamp_calendar(
	value Timestamp,
	offset Int,
	zone String,
) move Date

export extern fn msstd_time_timestamp_format(
	value Timestamp,
	pattern String,
	offset Int,
	zone String,
) move String

export extern fn msstd_time_parse_timestamp(text String) move Timestamp!

export extern fn msstd_time_clock_now() Instant

export extern fn msstd_time_wall_clock_now() move Timestamp
