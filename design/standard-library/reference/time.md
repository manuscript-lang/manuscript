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
fn difference(left: Timestamp, right: Timestamp) -> Result[Duration, LibraryError]
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
fn parse_timestamp(text: String) -> Result[Timestamp, LibraryError]
```

## shift {data-api-kind="Function"}

```manuscript
fn shift(value: Timestamp, duration: Duration) -> Result[Timestamp, LibraryError]
```

## sleep {data-api-kind="Function"}

```manuscript
fn sleep(duration: Duration) -> Unit
```

## timestamp {data-api-kind="Function"}

```manuscript
fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, LibraryError]
```

## unix_seconds {data-api-kind="Function"}

```manuscript
fn unix_seconds(value: Timestamp) -> Int
```

