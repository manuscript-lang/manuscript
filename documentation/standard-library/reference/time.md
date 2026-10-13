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

## Instant {data-api-kind="Native type"}

An instant on a monotonic clock; it is not a calendar timestamp.

```manuscript
type Instant:
    fn shift(duration: Duration) -> Instant:
    fn difference(right: Instant) -> Duration:
    fn compare(right: Instant) -> Int:
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
    fn unix_seconds() -> Int:
    fn nanoseconds() -> Int:
    fn shift(duration: Duration) -> Result[Timestamp, TimeError]:
    fn difference(right: Timestamp) -> Result[Duration, TimeError]:
    fn compare(right: Timestamp) -> Int:
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

