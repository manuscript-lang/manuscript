+++
title = "time"
+++

# @std/time.ms

Import each required symbol with `import Name from "@std/time.ms"`.

## Clock {data-api-kind="Interface"}

A monotonic clock whose readings are suitable for measuring elapsed time.

```manuscript
interface Clock:
    fn now() -> Instant
```

### Clock.now

Returns the current reading of this monotonic clock.
Readings are only comparable with others from the same clock and do not correspond to a calendar date.

```manuscript
fn now() -> Instant
```

## Duration {data-api-kind="Native type"}

A span of elapsed time.

```manuscript
type Duration:
    fn add(right: Duration) -> Duration:
    fn subtract(right: Duration) -> Duration:
    fn multiply(factor: Int) -> Duration:
    fn divide(divisor: Int) -> Duration:
    fn negate() -> Duration:
    fn abs() -> Duration:
    fn compare(right: Duration) -> Int:
    fn to_nanoseconds() -> Int:
    fn to_microseconds() -> Int:
    fn to_milliseconds() -> Int:
    fn to_seconds() -> Float:
    fn to_minutes() -> Float:
    fn to_hours() -> Float:
```

### Duration.abs

Returns the absolute value; the minimum Duration faults.

```manuscript
fn abs() -> Duration:
```

### Duration.add

Adds signed nanoseconds; a result outside Duration's representable range faults.

```manuscript
fn add(right: Duration) -> Duration:
```

### Duration.compare

Returns -1, 0, or 1.

```manuscript
fn compare(right: Duration) -> Int:
```

### Duration.divide

Divides by a nonzero integer, truncating toward zero; zero faults.

```manuscript
fn divide(divisor: Int) -> Duration:
```

### Duration.multiply

Multiplies by an integer factor; overflow faults.

```manuscript
fn multiply(factor: Int) -> Duration:
```

### Duration.negate

Negates this duration; the minimum Duration faults.

```manuscript
fn negate() -> Duration:
```

### Duration.subtract

Subtracts signed nanoseconds; a result outside Duration's representable range faults.

```manuscript
fn subtract(right: Duration) -> Duration:
```

### Duration.to_hours

Converts this duration to floating-point hours.

```manuscript
fn to_hours() -> Float:
```

### Duration.to_microseconds

Converts this duration to an integer number of microseconds.

```manuscript
fn to_microseconds() -> Int:
```

### Duration.to_milliseconds

Converts this duration to an integer number of milliseconds.

```manuscript
fn to_milliseconds() -> Int:
```

### Duration.to_minutes

Converts this duration to floating-point minutes.

```manuscript
fn to_minutes() -> Float:
```

### Duration.to_nanoseconds

Converts this duration to an integer number of nanoseconds.

```manuscript
fn to_nanoseconds() -> Int:
```

### Duration.to_seconds

Converts this duration to floating-point seconds.

```manuscript
fn to_seconds() -> Float:
```

## Instant {data-api-kind="Native type"}

An instant on a monotonic clock; it is not a calendar timestamp.

```manuscript
type Instant:
    fn shift(duration: Duration) -> Instant:
    fn difference(right: Instant) -> Duration:
    fn compare(right: Instant) -> Int:
```

### Instant.compare

Returns -1, 0, or 1; instants from different clock domains fault.

```manuscript
fn compare(right: Instant) -> Int:
```

### Instant.difference

Returns the elapsed duration from `right` to this instant.

```manuscript
fn difference(right: Instant) -> Duration:
```

### Instant.shift

Shifts this monotonic instant by a duration.

```manuscript
fn shift(duration: Duration) -> Instant:
```

## TimeError {data-api-kind="Alternative"}

Errors returned by timestamp parsing, arithmetic, or range conversion.

```manuscript
type TimeError:
    case InvalidInput
    case Closed
    case InvalidData
    case OutOfRange
```

```manuscript
impl Error for TimeError:
    fn message() -> String:
```

### TimeError.Closed

Reserved for time operations on a closed resource; the current native time operations do not return it.

```manuscript
case Closed
```

### TimeError.InvalidData

The text is not an RFC 3339 timestamp with a four-digit year, full date and time, and an explicit `Z` or `+hh:mm` offset.

```manuscript
case InvalidData
```

### TimeError.InvalidInput

Reserved for invalid time arguments; the current native time operations do not return it.

```manuscript
case InvalidInput
```

### TimeError.OutOfRange

A nanosecond component is outside 0 through 999999999, or the result falls outside years 1 through 9999 or cannot be represented as a Duration.

```manuscript
case OutOfRange
```

### TimeError.Error.message

Returns the fixed diagnostic `time: <reason>`, such as `time: value out of range`, without echoing the input text.

```manuscript
fn message() -> String:
```

## Timestamp {data-api-kind="Native type"}

A wall-clock time with Unix seconds and nanoseconds.

```manuscript
type Timestamp:
    fn to_string() -> String:
    fn unix_seconds() -> Int:
    fn nanoseconds() -> Int:
    fn shift(duration: Duration) -> Result[Timestamp, TimeError]:
    fn difference(right: Timestamp) -> Result[Duration, TimeError]:
    fn compare(right: Timestamp) -> Int:
```

### Timestamp.compare

Returns -1, 0, or 1 across the full calendar range.

```manuscript
fn compare(right: Timestamp) -> Int:
```

### Timestamp.difference

Returns `self - right` as a duration.

```manuscript
fn difference(right: Timestamp) -> Result[Duration, TimeError]:
```

### Timestamp.nanoseconds

Returns this timestamp's nanosecond component.

```manuscript
fn nanoseconds() -> Int:
```

### Timestamp.shift

Adds a duration to this wall-clock timestamp.

```manuscript
fn shift(duration: Duration) -> Result[Timestamp, TimeError]:
```

### Timestamp.to_string

Formats this timestamp in RFC 3339 form.

```manuscript
fn to_string() -> String:
```

### Timestamp.unix_seconds

Returns the whole Unix seconds represented by this timestamp.

```manuscript
fn unix_seconds() -> Int:
```

## WallClock {data-api-kind="Interface"}

A clock that reports calendar time.

```manuscript
interface WallClock:
    fn now() -> Timestamp
```

### WallClock.now

Returns the current calendar time as a UTC Timestamp with nanosecond precision.
It can jump when the system clock is adjusted, so use Clock for elapsed time.

```manuscript
fn now() -> Timestamp
```

## clock {data-api-kind="Function"}

Returns the monotonic clock used for elapsed-time measurements.

```manuscript
fn clock() -> Clock:
```

## duration {data-api-kind="Function"}

Constructs a duration from a number of nanoseconds.

```manuscript
fn duration(nanoseconds: Int) -> Duration:
```

## parse_timestamp {data-api-kind="Function"}

Parses an RFC 3339 timestamp with an explicit time zone.

```manuscript
fn parse_timestamp(text: String) -> Result[Timestamp, TimeError]:
```

## sleep {data-api-kind="Function"}

Suspends the current task for at least the requested duration.

```manuscript
fn sleep(duration: Duration) -> Unit:
```

## timestamp {data-api-kind="Function"}

Constructs a timestamp from Unix seconds and a nanosecond adjustment.

```manuscript
fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, TimeError]:
```

## wall_clock {data-api-kind="Function"}

Returns the wall clock used for calendar timestamps.

```manuscript
fn wall_clock() -> WallClock:
```

