+++
title = "time"
+++

# @std/time.ms

Import each required symbol with `import Name from "@std/time.ms"`.

## Clock {data-api-kind="Interface"}

```manuscript
Clock: Clock
operation now: fn()->Instant
```

## Duration {data-api-kind="Native type"}

```manuscript
Duration: Duration
```

## Instant {data-api-kind="Native type"}

```manuscript
Instant: Instant
```

## Timestamp {data-api-kind="Native type"}

```manuscript
Timestamp: Timestamp
```

## WallClock {data-api-kind="Interface"}

```manuscript
WallClock: WallClock
operation now: fn()->Timestamp
```

## difference {data-api-kind="Function"}

```manuscript
difference: fn(left: Timestamp, right: Timestamp)->Result[Duration, LibraryError]
```

## format_timestamp {data-api-kind="Function"}

```manuscript
format_timestamp: fn(value: Timestamp)->String
```

## nanoseconds {data-api-kind="Function"}

```manuscript
nanoseconds: fn(value: Timestamp)->Int
```

## parse_timestamp {data-api-kind="Function"}

```manuscript
parse_timestamp: fn(text: String)->Result[Timestamp, LibraryError]
```

## shift {data-api-kind="Function"}

```manuscript
shift: fn(value: Timestamp, duration: Duration)->Result[Timestamp, LibraryError]
```

## sleep {data-api-kind="Function"}

```manuscript
sleep: fn(duration: Duration)->Unit
```

## timestamp {data-api-kind="Function"}

```manuscript
timestamp: fn(seconds: Int, nanoseconds: Int)->Result[Timestamp, LibraryError]
```

## unix_seconds {data-api-kind="Function"}

```manuscript
unix_seconds: fn(value: Timestamp)->Int
```

