+++
title = "time"
+++

# @std/time.ms

Import each required symbol with `import Name from "@std/time.ms"`.

## Clock {data-api-kind="Interface"}

```manuscript
interface Clock:
    fn now() -> Instant
```

## Duration {data-api-kind="Native type"}

```manuscript
type Duration
```

## Instant {data-api-kind="Native type"}

```manuscript
type Instant
```

## TimeError {data-api-kind="Alternative"}

```manuscript
type TimeError:
    case InvalidInput
    case Closed
    case InvalidData
    case OutOfRange
```

```manuscript
impl Error for TimeError:
    fn message() -> String
```

## Timer {data-api-kind="Interface"}

```manuscript
interface Timer:
    fn close() -> Unit
    fn restart() -> Result[Unit, TimeError]
    fn status() -> WorkStatus
```

## Timestamp {data-api-kind="Native type"}

```manuscript
type Timestamp
```

## WallClock {data-api-kind="Interface"}

```manuscript
interface WallClock:
    fn now() -> Timestamp
```

## after {data-api-kind="Function"}

```manuscript
fn after(duration: Duration, operation: fn() -> Result[Unit, String]) -> Result[Timer, TimeError]
```

## clock {data-api-kind="Function"}

```manuscript
fn clock() -> Clock
```

## difference {data-api-kind="Function"}

```manuscript
fn difference(left: Timestamp, right: Timestamp) -> Result[Duration, TimeError]
```

## every {data-api-kind="Function"}

```manuscript
fn every(interval: Duration, operation: fn() -> Result[Unit, String]) -> Result[Timer, TimeError]
```

## format_timestamp {data-api-kind="Function"}

```manuscript
fn format_timestamp(value: Timestamp) -> String
```

## nanoseconds {data-api-kind="Function"}

```manuscript
fn nanoseconds(value: Timestamp) -> Int
```

## parse_timestamp {data-api-kind="Function"}

```manuscript
fn parse_timestamp(text: String) -> Result[Timestamp, TimeError]
```

## shift {data-api-kind="Function"}

```manuscript
fn shift(value: Timestamp, duration: Duration) -> Result[Timestamp, TimeError]
```

## sleep {data-api-kind="Function"}

```manuscript
fn sleep(duration: Duration) -> Unit
```

## timestamp {data-api-kind="Function"}

```manuscript
fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, TimeError]
```

## unix_seconds {data-api-kind="Function"}

```manuscript
fn unix_seconds(value: Timestamp) -> Int
```

## wall_clock {data-api-kind="Function"}

```manuscript
fn wall_clock() -> WallClock
```

