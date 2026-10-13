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

### Duration.add

Adds signed nanoseconds; a result outside Duration's representable range faults.

```manuscript
fn add(right: Duration) -> Duration:
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

## Timestamp {data-api-kind="Native type"}

A wall-clock time with Unix seconds and nanoseconds.

```manuscript
type Timestamp:
    fn to_string() -> String:
    fn format(layout: String) -> String:
    fn unix_seconds() -> Int:
    fn nanoseconds() -> Int:
    fn shift(duration: Duration) -> Result[Timestamp, TimeError]:
    fn difference(right: Timestamp) -> Result[Duration, TimeError]:
    fn compare(right: Timestamp) -> Int:
```

### Timestamp.difference

Returns `self - right` as a duration.

```manuscript
fn difference(right: Timestamp) -> Result[Duration, TimeError]:
```

### Timestamp.format

Formats this timestamp in UTC using Go's reference-time layout: Mon Jan 2 15:04:05 MST 2006.
For example, "2006-01-02" selects a calendar date and "15:04:05.000000000" preserves nanoseconds.

```manuscript
fn format(layout: String) -> String:
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

## parse_timestamp_format {data-api-kind="Function"}

Parses a timestamp using Go's reference-time layout: Mon Jan 2 15:04:05 MST 2006.
Missing zones use UTC; offsets are normalized to UTC. Empty layouts return InvalidInput,
malformed text returns InvalidData, and UTC years outside 1..9999 return OutOfRange.

```manuscript
fn parse_timestamp_format(text: String, layout: String) -> Result[Timestamp, TimeError]:
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

