import Data, panic from "@std/core.ms"
import msstd_time_duration_add, msstd_time_duration_subtract, msstd_time_duration_multiply, msstd_time_duration_divide, msstd_time_duration_negate, msstd_time_duration_abs, msstd_time_duration_to_microseconds, msstd_time_duration_to_milliseconds, msstd_time_duration_to_seconds, msstd_time_duration_to_minutes, msstd_time_duration_to_hours, msstd_time_local_zone, msstd_time_sleep, msstd_time_instant_shift, msstd_time_instant_unshift, msstd_time_instant_difference, msstd_time_instant_compare, msstd_time_timestamp_to_string, msstd_time_timestamp_shift, msstd_time_timestamp_difference, msstd_time_timestamp_compare, msstd_time_timestamp_calendar, msstd_time_timestamp_format, msstd_time_parse_timestamp, msstd_time_from_calendar, msstd_time_timestamp, msstd_time_clock, msstd_time_wall_clock from "@std/internal/time.ms"

# Errors returned by timestamp parsing, arithmetic, or range conversion.
export type TimeError:
    # Reserved for invalid time arguments; the current native time operations do not return it.
    case InvalidInput
    # Reserved for time operations on a closed resource; the current native time operations do not return it.
    case Closed
    # The text is not an RFC 3339 timestamp with a four-digit year, full date and time, and an explicit `Z` or `+hh:mm` offset.
    case InvalidData
    # A nanosecond component is outside 0 through 999999999, or the result falls outside years 1 through 9999 or cannot be represented as a Duration.
    case OutOfRange

# A monotonic clock whose readings are suitable for measuring elapsed time.
interface Clock:
    # Returns the current reading of this monotonic clock.
    # Readings are only comparable with others from the same clock and do not correspond to a calendar date.
    fn now() Instant

# A span of elapsed time, counted in signed nanoseconds.
export type Duration:
    # The signed count of nanoseconds; `nanoseconds(n)` and the unit constructors build one.
    nanos: Int

impl Duration:
    # Adds signed nanoseconds; a result outside Duration's representable range faults.
    fn add(other: Duration) Duration:
        return Duration(nanos: msstd_time_duration_add(self.nanos, other.nanos))

    # Subtracts signed nanoseconds; a result outside Duration's representable range faults.
    fn subtract(other: Duration) Duration:
        return Duration(nanos: msstd_time_duration_subtract(self.nanos, other.nanos))

    # Multiplies by an integer factor; overflow faults.
    fn multiply(factor: Int) Duration:
        return Duration(nanos: msstd_time_duration_multiply(self.nanos, factor))

    # Divides by a nonzero integer, truncating toward zero; zero faults.
    fn divide(divisor: Int) Duration:
        return Duration(nanos: msstd_time_duration_divide(self.nanos, divisor))

    # Negates this duration; the minimum Duration faults.
    fn negate() Duration:
        return Duration(nanos: msstd_time_duration_negate(self.nanos))

    # Returns the absolute value; the minimum Duration faults.
    fn abs() Duration:
        return Duration(nanos: msstd_time_duration_abs(self.nanos))

    # Returns -1, 0, or 1.
    fn compare(other: Duration) Int:
        if self.nanos < other.nanos:
            return -1
        if self.nanos > other.nanos:
            return 1

        return 0

    # Returns the lesser of this value and `other`, or this value when they compare equal.
    fn min(other: Duration) Duration:
        if other.compare(self) < 0:
            return other

        return self.clone()

    # Returns the greater of this value and `other`, or this value when they compare equal.
    fn max(other: Duration) Duration:
        if other.compare(self) > 0:
            return other

        return self.clone()

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    fn clamp(low: Duration, high: Duration) Duration:
        if low.compare(high) > 0:
            panic("clamp: low must not be greater than high")
        if self.compare(low) < 0:
            return low
        if self.compare(high) > 0:
            return high

        return self.clone()

    # Converts this duration to an integer number of nanoseconds.
    fn to_nanoseconds() Int:
        return self.nanos

    # Converts this duration to an integer number of microseconds.
    fn to_microseconds() Int:
        return msstd_time_duration_to_microseconds(self.nanos)

    # Converts this duration to an integer number of milliseconds.
    fn to_milliseconds() Int:
        return msstd_time_duration_to_milliseconds(self.nanos)

    # Returns human text such as `1m30.5s`, `250ms`, `1.5µs`, `-2h`, or `0s`; string interpolation uses it too.
    fn to_string() String:
        let total = self.to_nanoseconds()
        if total == 0:
            return "0s"

        # Work on magnitudes of the truncated parts so the minimum Duration, which has no positive counterpart, formats too.
        let step = if total < 0: -1 else: 1

        let sign = if total < 0: "-" else: ""

        let whole = total / 1000000000 * step
        let sub = total % 1000000000 * step
        if whole == 0 and sub < 1000:
            return "{sign}{sub}ns"
        if whole == 0 and sub < 1000000:
            return "{sign}{duration_decimal(sub / 1000, sub % 1000, 3)}µs"
        if whole == 0:
            return "{sign}{duration_decimal(sub / 1000000, sub % 1000000, 6)}ms"

        let hours = whole / 3600
        let minutes = whole % 3600 / 60

        let clock = if hours == 0: "" else: "{hours}h"

        let minute_part = if hours == 0 and minutes == 0: "" else: "{minutes}m"

        let seconds_part = duration_decimal(whole % 60, sub, 9)
        return "{sign}{clock}{minute_part}{seconds_part}s"

    # Converts this duration to floating-point seconds.
    fn to_seconds() Float:
        return msstd_time_duration_to_seconds(self.nanos)

    # Converts this duration to floating-point minutes.
    fn to_minutes() Float:
        return msstd_time_duration_to_minutes(self.nanos)

    # Converts this duration to floating-point hours.
    fn to_hours() Float:
        return msstd_time_duration_to_hours(self.nanos)

# An instant on a monotonic clock; it is not a calendar timestamp.
export type Instant:
    # The clock the reading belongs to; instants from different domains do not compare.
    domain: Int
    # Nanoseconds on that clock.
    tick: Int

impl Instant:
    # Shifts this monotonic instant by a duration.
    fn shift(duration: Duration) Instant:
        return msstd_time_instant_shift(self, duration.nanos)

    # Shifts this monotonic instant back by a duration.
    fn unshift(duration: Duration) Instant:
        return msstd_time_instant_unshift(self, duration.nanos)

    # Returns the elapsed duration from `right` to this instant.
    fn difference(other: Instant) Duration:
        return Duration(nanos: msstd_time_instant_difference(self, other))

    # Returns -1, 0, or 1; instants from different clock domains fault.
    fn compare(other: Instant) Int:
        return msstd_time_instant_compare(self, other)

    # Returns the lesser of this value and `other`, or this value when they compare equal.
    fn min(other: Instant) Instant:
        if other.compare(self) < 0:
            return other

        return self.clone()

    # Returns the greater of this value and `other`, or this value when they compare equal.
    fn max(other: Instant) Instant:
        if other.compare(self) > 0:
            return other

        return self.clone()

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    fn clamp(low: Instant, high: Instant) Instant:
        if low.compare(high) > 0:
            panic("clamp: low must not be greater than high")
        if self.compare(low) < 0:
            return low
        if self.compare(high) > 0:
            return high

        return self.clone()

# A wall-clock time with Unix seconds and nanoseconds.
export type Timestamp:
    # Whole seconds since the Unix epoch.
    seconds: Int
    # The nanosecond within the second, 0 through 999999999.
    nanos: Int

impl Timestamp:
    # Formats this timestamp in RFC 3339 form.
    fn to_string() String:
        return msstd_time_timestamp_to_string(self)

    # Returns the whole Unix seconds represented by this timestamp.
    fn unix_seconds() Int:
        return self.seconds

    # Returns this timestamp's nanosecond component.
    fn nanoseconds() Int:
        return self.nanos

    # Adds a duration to this wall-clock timestamp.
    fn shift(duration: Duration) Timestamp!TimeError:
        return msstd_time_timestamp_shift(self, duration.nanos)

    # Returns `self - right` as a duration.
    fn difference(other: Timestamp) Duration!TimeError:
        let nanos = try msstd_time_timestamp_difference(self, other)
        return ok(Duration(nanos: nanos))

    # Returns -1, 0, or 1 across the full calendar range.
    fn compare(other: Timestamp) Int:
        return msstd_time_timestamp_compare(self, other)

    # Returns the lesser of this value and `other`, or this value when they compare equal.
    fn min(other: Timestamp) Timestamp:
        if other.compare(self) < 0:
            return other

        return self.clone()

    # Returns the greater of this value and `other`, or this value when they compare equal.
    fn max(other: Timestamp) Timestamp:
        if other.compare(self) > 0:
            return other

        return self.clone()

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    fn clamp(low: Timestamp, high: Timestamp) Timestamp:
        if low.compare(high) > 0:
            panic("clamp: low must not be greater than high")
        if self.compare(low) < 0:
            return low
        if self.compare(high) > 0:
            return high

        return self.clone()

    # Breaks this timestamp into calendar fields in a time zone: `"UTC"`, `"Local"`, an IANA name such as `"America/New_York"`, or a fixed offset such as `"+05:30"`.
    # An unknown zone returns InvalidInput.
    fn calendar(zone: String) Calendar!TimeError:
        return msstd_time_timestamp_calendar(self, zone)

    # Formats this timestamp in a zone with a token pattern.
    # Tokens are `YYYY`, `MM`, `DD`, `HH`, `mm`, `ss`, `SSS` (milliseconds), `ZZ` (offset such as `+05:30`), and `zone` (abbreviation); other text is copied.
    # An unknown zone returns InvalidInput.
    fn format(pattern: String, zone: String) String!TimeError:
        return msstd_time_timestamp_format(self, pattern, zone)

# Calendar fields of a timestamp in one time zone.
export type Calendar:
    # The year, 1 through 9999 in UTC and nearby values in other zones.
    year: Int
    # The month, 1 (January) through 12.
    month: Int
    # The day of the month, starting at 1.
    day: Int
    # The hour, 0 through 23.
    hour: Int
    # The minute, 0 through 59.
    minute: Int
    # The second, 0 through 59.
    second: Int
    # The nanosecond within the second, 0 through 999999999.
    nanosecond: Int
    # The day of the week, 0 (Sunday) through 6 (Saturday).
    weekday: Int
    # The day of the year, starting at 1.
    day_of_year: Int
    # The zone's offset from UTC in seconds at this moment; positive is east.
    offset_seconds: Int
    # The zone abbreviation at this moment, such as `UTC` or `EST`.
    zone: String

# A clock that reports calendar time.
interface WallClock:
    # Returns the current calendar time as a UTC Timestamp with nanosecond precision.
    # It can jump when the system clock is adjusted, so use Clock for elapsed time.
    fn now() Timestamp

# Writes `whole` with the digits of a fractional part `frac` of `width` places, trailing zeros dropped.
fn duration_decimal(whole: Int, frac: Int, width: Int) String:
    if frac == 0:
        return "{whole}"

    var rest = frac
    var places = width

    while rest % 10 == 0:
        rest = rest / 10
        places -= 1

    var digits = ""

    while places > 0:
        digits = "{rest % 10}{digits}"
        rest = rest / 10
        places -= 1

    return "{whole}.{digits}"

# Constructs a duration of `n` nanoseconds, the unit `Duration` counts in; `n` may be negative.
export fn nanoseconds(n: Int) Duration:
    return Duration(nanos: n)

# Constructs a duration of `n` microseconds; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export fn microseconds(n: Int) Duration:
    return nanoseconds(n * 1000)

# Constructs a duration of `n` milliseconds; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export fn milliseconds(n: Int) Duration:
    return nanoseconds(n * 1000000)

# Constructs a duration of `n` seconds, as in `sleep(seconds(2))`; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export fn seconds(n: Int) Duration:
    return nanoseconds(n * 1000000000)

# Constructs a duration of `n` minutes, as in `clock().now().difference(start).compare(minutes(5)) > 0` to test an elapsed span; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export fn minutes(n: Int) Duration:
    return nanoseconds(n * 60000000000)

# Constructs a duration of `n` hours; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export fn hours(n: Int) Duration:
    return nanoseconds(n * 3600000000000)

# Parses an RFC 3339 timestamp with an explicit time zone.
export fn parse_timestamp(text: String) Timestamp!TimeError:
    return msstd_time_parse_timestamp(text)

# Builds a timestamp from calendar fields interpreted in a time zone (see `Timestamp.calendar` for zone names).
# Fields outside their calendar range, such as month 13 or February 30, return OutOfRange; an unknown zone returns InvalidInput.
# A local time skipped or repeated by a daylight-saving change resolves to the earlier valid offset.
export fn from_calendar(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    nanosecond: Int,
    zone: String
) Timestamp!TimeError:
    return msstd_time_from_calendar(
        year, month, day, hour, minute, second, nanosecond, zone
    )

# Returns the host's local time zone name, or `UTC` when it cannot be determined.
export fn local_zone() String:
    return msstd_time_local_zone()

# Suspends the current task for at least the requested duration.
export fn sleep(duration: Duration) Unit:
    msstd_time_sleep(duration.nanos)

# Constructs a timestamp from Unix seconds and a nanosecond adjustment.
export fn timestamp(seconds: Int, nanoseconds: Int) Timestamp!TimeError:
    return msstd_time_timestamp(seconds, nanoseconds)

impl Error for TimeError:
    # Returns the fixed diagnostic `time: <reason>`, such as `time: value out of range`, without echoing the input text.
    fn message() String:
        match self:
            InvalidInput: return "time: invalid input"
            Closed: return "time: resource is closed"
            InvalidData: return "time: invalid data"
            OutOfRange: return "time: value out of range"

# Returns the current reading of the monotonic clock, for measuring elapsed time.
# Readings are only comparable with others from this clock and do not correspond to a calendar date.
export fn monotonic() Instant:
    return msstd_time_clock().now()

# Returns the current calendar time as a UTC Timestamp with nanosecond precision.
# It can jump when the system clock is adjusted, so use `monotonic` for elapsed time.
export fn now() Timestamp:
    return msstd_time_wall_clock().now()
