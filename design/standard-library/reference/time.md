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
    case InvalidData
    case OutOfRange
```

```manuscript
impl Error for TimeError:
    fn message() -> String
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

## difference {data-api-kind="Function"}

```manuscript
fn difference(left: Timestamp, right: Timestamp) -> Result[Duration, TimeError]
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

