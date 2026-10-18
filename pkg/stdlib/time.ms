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
    fn now() Instant

# A span of elapsed time.
export type Duration:

impl Duration:
    # Adds signed nanoseconds; a result outside Duration's representable range faults.
    fn add(other: Duration) Duration:

    # Subtracts signed nanoseconds; a result outside Duration's representable range faults.
    fn subtract(other: Duration) Duration:

    # Multiplies by an integer factor; overflow faults.
    fn multiply(factor: Int) Duration:

    # Divides by a nonzero integer, truncating toward zero; zero faults.
    fn divide(divisor: Int) Duration:

    # Negates this duration; the minimum Duration faults.
    fn negate() Duration:

    # Returns the absolute value; the minimum Duration faults.
    fn abs() Duration:

    # Returns -1, 0, or 1.
    fn compare(other: Duration) Int:

    # Converts this duration to an integer number of nanoseconds.
    fn to_nanoseconds() Int:

    # Converts this duration to an integer number of microseconds.
    fn to_microseconds() Int:

    # Converts this duration to an integer number of milliseconds.
    fn to_milliseconds() Int:

    # Converts this duration to floating-point seconds.
    fn to_seconds() Float:

    # Converts this duration to floating-point minutes.
    fn to_minutes() Float:

    # Converts this duration to floating-point hours.
    fn to_hours() Float:

# An instant on a monotonic clock; it is not a calendar timestamp.
export type Instant:

impl Instant:
    # Shifts this monotonic instant by a duration.
    fn shift(duration: Duration) Instant:

    # Returns the elapsed duration from `right` to this instant.
    fn difference(other: Instant) Duration:

    # Returns -1, 0, or 1; instants from different clock domains fault.
    fn compare(other: Instant) Int:

# A wall-clock time with Unix seconds and nanoseconds.
export type Timestamp:

impl Timestamp:
    # Formats this timestamp in RFC 3339 form.
    fn to_string() String:

    # Returns the whole Unix seconds represented by this timestamp.
    fn unix_seconds() Int:

    # Returns this timestamp's nanosecond component.
    fn nanoseconds() Int:

    # Adds a duration to this wall-clock timestamp.
    fn shift(duration: Duration) Result[Timestamp, TimeError]:

    # Returns `self - right` as a duration.
    fn difference(other: Timestamp) Result[Duration, TimeError]:

    # Returns -1, 0, or 1 across the full calendar range.
    fn compare(other: Timestamp) Int:

    # Breaks this timestamp into calendar fields in a time zone: `"UTC"`, `"Local"`, an IANA name such as `"America/New_York"`, or a fixed offset such as `"+05:30"`.
    # An unknown zone returns InvalidInput.
    fn calendar(zone: String) Result[Calendar, TimeError]:

    # Formats this timestamp in a zone with a token pattern.
    # Tokens are `YYYY`, `MM`, `DD`, `HH`, `mm`, `ss`, `SSS` (milliseconds), `ZZ` (offset such as `+05:30`), and `zone` (abbreviation); other text is copied.
    # An unknown zone returns InvalidInput.
    fn format(pattern: String, zone: String) Result[String, TimeError]:

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
    fn now() Timestamp

# Constructs a duration from a number of nanoseconds.
export fn duration(nanoseconds: Int) Duration:

# Parses an RFC 3339 timestamp with an explicit time zone.
export fn parse_timestamp(text: String) Result[Timestamp, TimeError]:

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
) Result[Timestamp, TimeError]:

# Returns the host's local time zone name, or `UTC` when it cannot be determined.
export fn local_zone() String:

# Suspends the current task for at least the requested duration.
export fn sleep(duration: Duration) Unit:

# Constructs a timestamp from Unix seconds and a nanosecond adjustment.
export fn timestamp(seconds: Int, nanoseconds: Int) Result[Timestamp, TimeError]:

impl Error for TimeError:
    # Returns the fixed diagnostic `time: <reason>`, such as `time: value out of range`, without echoing the input text.
    fn message() String:

# Returns the monotonic clock used for elapsed-time measurements.
export fn clock() Clock:

# Returns the wall clock used for calendar timestamps.
export fn wall_clock() WallClock:
