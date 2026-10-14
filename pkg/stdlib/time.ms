# Canonical standard-library declarations. Implementations are native.

# Errors returned by timestamp parsing, arithmetic, or range conversion.
export type TimeError:
    case InvalidInput
    case Closed
    case InvalidData
    case OutOfRange

# A monotonic clock whose readings are suitable for measuring elapsed time.
export interface Clock:
    fn now() -> Instant

# A span of elapsed time.
export type Duration:
    # Adds signed nanoseconds; a result outside Duration's representable range faults.
    fn add(other: Duration) -> Duration:
    # Subtracts signed nanoseconds; a result outside Duration's representable range faults.
    fn subtract(other: Duration) -> Duration:
    # Multiplies by an integer factor; overflow faults.
    fn multiply(factor: Int) -> Duration:
    # Divides by a nonzero integer, truncating toward zero; zero faults.
    fn divide(divisor: Int) -> Duration:
    # Negates this duration; the minimum Duration faults.
    fn negate() -> Duration:
    # Returns the absolute value; the minimum Duration faults.
    fn abs() -> Duration:
    # Returns -1, 0, or 1.
    fn compare(other: Duration) -> Int:
    # Converts this duration to an integer number of nanoseconds.
    fn to_nanoseconds() -> Int:
    # Converts this duration to an integer number of microseconds.
    fn to_microseconds() -> Int:
    # Converts this duration to an integer number of milliseconds.
    fn to_milliseconds() -> Int:
    # Converts this duration to floating-point seconds.
    fn to_seconds() -> Float:
    # Converts this duration to floating-point minutes.
    fn to_minutes() -> Float:
    # Converts this duration to floating-point hours.
    fn to_hours() -> Float:

# An instant on a monotonic clock; it is not a calendar timestamp.
export type Instant:
    # Shifts this monotonic instant by a duration.
    fn shift(duration: Duration) -> Instant:
    # Returns the elapsed duration from `right` to this instant.
    fn difference(other: Instant) -> Duration:
    # Returns -1, 0, or 1; instants from different clock domains fault.
    fn compare(other: Instant) -> Int:

# A wall-clock time with Unix seconds and nanoseconds.
export type Timestamp:
    # Formats this timestamp in RFC 3339 form.
    fn to_string() -> String:
    # Returns the whole Unix seconds represented by this timestamp.
    fn unix_seconds() -> Int:
    # Returns this timestamp's nanosecond component.
    fn nanoseconds() -> Int:
    # Adds a duration to this wall-clock timestamp.
    fn shift(duration: Duration) -> Result[Timestamp, TimeError]:
    # Returns `self - right` as a duration.
    fn difference(other: Timestamp) -> Result[Duration, TimeError]:
    # Returns -1, 0, or 1 across the full calendar range.
    fn compare(other: Timestamp) -> Int:

# A clock that reports calendar time.
export interface WallClock:
    fn now() -> Timestamp

# Constructs a duration from a number of nanoseconds.
export fn duration(nanoseconds: Int) -> Duration:

# Parses an RFC 3339 timestamp with an explicit time zone.
export fn parse_timestamp(text: String) -> Result[Timestamp, TimeError]:

# Suspends the current task for at least the requested duration.
export fn sleep(duration: Duration) -> Unit:

# Constructs a timestamp from Unix seconds and a nanosecond adjustment.
export fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, TimeError]:

impl Error for TimeError:
    fn message() -> String:

# Returns the monotonic clock used for elapsed-time measurements.
export fn clock() -> Clock:

# Returns the wall clock used for calendar timestamps.
export fn wall_clock() -> WallClock:
