extern def msstd_time_duration_to_nanoseconds(value: Duration) -> Int

extern def msstd_time_timestamp_unix_seconds(value: Timestamp) -> Int

extern def msstd_time_timestamp_nanoseconds(value: Timestamp) -> Int

extern def msstd_time_duration_add(value: Duration, other: Duration) -> Duration

extern def msstd_time_duration_subtract(value: Duration, other: Duration) -> Duration

extern def msstd_time_duration_multiply(value: Duration, factor: Int) -> Duration

extern def msstd_time_duration_divide(value: Duration, divisor: Int) -> Duration

extern def msstd_time_duration_negate(value: Duration) -> Duration

extern def msstd_time_duration_abs(value: Duration) -> Duration

extern def msstd_time_duration_compare(value: Duration, other: Duration) -> Int

extern def msstd_time_duration_to_microseconds(value: Duration) -> Int

extern def msstd_time_duration_to_milliseconds(value: Duration) -> Int

extern def msstd_time_duration_to_string(value: Duration) -> String

extern def msstd_time_duration_to_seconds(value: Duration) -> Float

extern def msstd_time_duration_to_minutes(value: Duration) -> Float

extern def msstd_time_duration_to_hours(value: Duration) -> Float

extern def msstd_time_instant_shift(value: Instant, duration: Duration) -> Instant

extern def msstd_time_instant_difference(value: Instant, other: Instant) -> Duration

extern def msstd_time_instant_compare(value: Instant, other: Instant) -> Int

extern def msstd_time_timestamp_to_string(value: Timestamp) -> String

extern def msstd_time_timestamp_shift(
    value: Timestamp,
    duration: Duration
) -> Result[Timestamp, TimeError]

extern def msstd_time_timestamp_difference(
    value: Timestamp,
    other: Timestamp
) -> Result[Duration, TimeError]

extern def msstd_time_timestamp_compare(value: Timestamp, other: Timestamp) -> Int

extern def msstd_time_timestamp_calendar(
    value: Timestamp,
    zone: String
) -> Result[Calendar, TimeError]

extern def msstd_time_timestamp_format(
    value: Timestamp,
    pattern: String,
    zone: String
) -> Result[String, TimeError]

extern def msstd_time_duration(nanoseconds: Int) -> Duration

extern def msstd_time_parse_timestamp(text: String) -> Result[Timestamp, TimeError]

extern def msstd_time_from_calendar(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    nanosecond: Int,
    zone: String
) -> Result[Timestamp, TimeError]

extern def msstd_time_local_zone() -> String

extern def msstd_time_sleep(duration: Duration) -> Unit

extern def msstd_time_timestamp(
    seconds: Int,
    nanoseconds: Int
) -> Result[Timestamp, TimeError]

extern def msstd_time_clock() -> Clock

extern def msstd_time_wall_clock() -> WallClock

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
export interface Clock:
    # Returns the current reading of this monotonic clock.
    # Readings are only comparable with others from the same clock and do not correspond to a calendar date.
    def now() -> Instant

# A span of elapsed time.
export extern type Duration

impl Duration:
    # Adds signed nanoseconds; a result outside Duration's representable range faults.
    def add(other: Duration) -> Duration:
        return msstd_time_duration_add(self, other)

    # Subtracts signed nanoseconds; a result outside Duration's representable range faults.
    def subtract(other: Duration) -> Duration:
        return msstd_time_duration_subtract(self, other)

    # Multiplies by an integer factor; overflow faults.
    def multiply(factor: Int) -> Duration:
        return msstd_time_duration_multiply(self, factor)

    # Divides by a nonzero integer, truncating toward zero; zero faults.
    def divide(divisor: Int) -> Duration:
        return msstd_time_duration_divide(self, divisor)

    # Negates this duration; the minimum Duration faults.
    def negate() -> Duration:
        return msstd_time_duration_negate(self)

    # Returns the absolute value; the minimum Duration faults.
    def abs() -> Duration:
        return msstd_time_duration_abs(self)

    # Returns -1, 0, or 1.
    def compare(other: Duration) -> Int:
        return msstd_time_duration_compare(self, other)

    # Converts this duration to an integer number of nanoseconds.
    def to_nanoseconds() -> Int:
        return msstd_time_duration_to_nanoseconds(self)

    # Converts this duration to an integer number of microseconds.
    def to_microseconds() -> Int:
        return msstd_time_duration_to_microseconds(self)

    # Converts this duration to an integer number of milliseconds.
    def to_milliseconds() -> Int:
        return msstd_time_duration_to_milliseconds(self)

    # Returns human text such as `1m30.5s`, `250ms`, `1.5µs`, `-2h`, or `0s`; string interpolation uses it too.
    def to_string() -> String:
        return msstd_time_duration_to_string(self)

    # Converts this duration to floating-point seconds.
    def to_seconds() -> Float:
        return msstd_time_duration_to_seconds(self)

    # Converts this duration to floating-point minutes.
    def to_minutes() -> Float:
        return msstd_time_duration_to_minutes(self)

    # Converts this duration to floating-point hours.
    def to_hours() -> Float:
        return msstd_time_duration_to_hours(self)

# An instant on a monotonic clock; it is not a calendar timestamp.
export extern type Instant

impl Instant:
    # Shifts this monotonic instant by a duration.
    def shift(duration: Duration) -> Instant:
        return msstd_time_instant_shift(self, duration)

    # Returns the elapsed duration from `right` to this instant.
    def difference(other: Instant) -> Duration:
        return msstd_time_instant_difference(self, other)

    # Returns -1, 0, or 1; instants from different clock domains fault.
    def compare(other: Instant) -> Int:
        return msstd_time_instant_compare(self, other)

# A wall-clock time with Unix seconds and nanoseconds.
export extern type Timestamp

impl Timestamp:
    # Formats this timestamp in RFC 3339 form.
    def to_string() -> String:
        return msstd_time_timestamp_to_string(self)

    # Returns the whole Unix seconds represented by this timestamp.
    def unix_seconds() -> Int:
        return msstd_time_timestamp_unix_seconds(self)

    # Returns this timestamp's nanosecond component.
    def nanoseconds() -> Int:
        return msstd_time_timestamp_nanoseconds(self)

    # Adds a duration to this wall-clock timestamp.
    def shift(duration: Duration) -> Result[Timestamp, TimeError]:
        return msstd_time_timestamp_shift(self, duration)

    # Returns `self - right` as a duration.
    def difference(other: Timestamp) -> Result[Duration, TimeError]:
        return msstd_time_timestamp_difference(self, other)

    # Returns -1, 0, or 1 across the full calendar range.
    def compare(other: Timestamp) -> Int:
        return msstd_time_timestamp_compare(self, other)

    # Breaks this timestamp into calendar fields in a time zone: `"UTC"`, `"Local"`, an IANA name such as `"America/New_York"`, or a fixed offset such as `"+05:30"`.
    # An unknown zone returns InvalidInput.
    def calendar(zone: String) -> Result[Calendar, TimeError]:
        return msstd_time_timestamp_calendar(self, zone)

    # Formats this timestamp in a zone with a token pattern.
    # Tokens are `YYYY`, `MM`, `DD`, `HH`, `mm`, `ss`, `SSS` (milliseconds), `ZZ` (offset such as `+05:30`), and `zone` (abbreviation); other text is copied.
    # An unknown zone returns InvalidInput.
    def format(pattern: String, zone: String) -> Result[String, TimeError]:
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
export interface WallClock:
    # Returns the current calendar time as a UTC Timestamp with nanosecond precision.
    # It can jump when the system clock is adjusted, so use Clock for elapsed time.
    def now() -> Timestamp

# Constructs a duration from a number of nanoseconds.
export def duration(nanoseconds: Int) -> Duration:
    return msstd_time_duration(nanoseconds)

# Constructs a duration from a number of nanoseconds, like `duration`.
export def nanoseconds(n: Int) -> Duration:
    return duration(nanoseconds: n)

# Constructs a duration of `n` microseconds; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export def microseconds(n: Int) -> Duration:
    return duration(nanoseconds: n * 1000)

# Constructs a duration of `n` milliseconds; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export def milliseconds(n: Int) -> Duration:
    return duration(nanoseconds: n * 1000000)

# Constructs a duration of `n` seconds, as in `sleep(seconds(2))`; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export def seconds(n: Int) -> Duration:
    return duration(nanoseconds: n * 1000000000)

# Constructs a duration of `n` minutes, as in `clock().now().difference(start).compare(minutes(5)) > 0` to test an elapsed span; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export def minutes(n: Int) -> Duration:
    return duration(nanoseconds: n * 60000000000)

# Constructs a duration of `n` hours; `n` may be negative, and a nanosecond count outside Int faults like any Int multiplication.
export def hours(n: Int) -> Duration:
    return duration(nanoseconds: n * 3600000000000)

# Parses an RFC 3339 timestamp with an explicit time zone.
export def parse_timestamp(text: String) -> Result[Timestamp, TimeError]:
    return msstd_time_parse_timestamp(text)

# Builds a timestamp from calendar fields interpreted in a time zone (see `Timestamp.calendar` for zone names).
# Fields outside their calendar range, such as month 13 or February 30, return OutOfRange; an unknown zone returns InvalidInput.
# A local time skipped or repeated by a daylight-saving change resolves to the earlier valid offset.
export def from_calendar(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    nanosecond: Int,
    zone: String
) -> Result[Timestamp, TimeError]:
    return msstd_time_from_calendar(
        year, month, day, hour, minute, second, nanosecond, zone
    )

# Returns the host's local time zone name, or `UTC` when it cannot be determined.
export def local_zone() -> String:
    return msstd_time_local_zone()

# Suspends the current task for at least the requested duration.
export def sleep(duration: Duration) -> Unit:
    msstd_time_sleep(duration)

# Constructs a timestamp from Unix seconds and a nanosecond adjustment.
export def timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, TimeError]:
    return msstd_time_timestamp(seconds, nanoseconds)

impl Error for TimeError:
    # Returns the fixed diagnostic `time: <reason>`, such as `time: value out of range`, without echoing the input text.
    def message() -> String:
        match self:
            case InvalidInput: return "time: invalid input"
            case Closed: return "time: resource is closed"
            case InvalidData: return "time: invalid data"
            case OutOfRange: return "time: value out of range"

# Returns the monotonic clock used for elapsed-time measurements.
export def clock() -> Clock:
    return msstd_time_clock()

# Returns the wall clock used for calendar timestamps.
export def wall_clock() -> WallClock:
    return msstd_time_wall_clock()
