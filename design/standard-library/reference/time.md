+++
title = "time"
+++

# @std/time.ms

Import each required symbol with `import Name from "@std/time.ms"`.

## Clock

Kind: interface.

```text
Clock: Clock
operation now: fn()->Instant
```

## Duration

Kind: native.

```text
Duration: Duration
```

## Instant

Kind: native.

```text
Instant: Instant
```

## TimeError

Kind: alternative.

```text
TimeError: TimeError
implements: Error
case InvalidData
case OutOfRange
operation message: fn()->String
```

## Timestamp

Kind: native.

```text
Timestamp: Timestamp
```

## WallClock

Kind: interface.

```text
WallClock: WallClock
operation now: fn()->Timestamp
```

## difference

Kind: fn.

```text
difference: fn(left: Timestamp, right: Timestamp)->Result[Duration, TimeError]
```

## format_timestamp

Kind: fn.

```text
format_timestamp: fn(value: Timestamp)->String
```

## nanoseconds

Kind: fn.

```text
nanoseconds: fn(value: Timestamp)->Int
```

## parse_timestamp

Kind: fn.

```text
parse_timestamp: fn(text: String)->Result[Timestamp, TimeError]
```

## shift

Kind: fn.

```text
shift: fn(value: Timestamp, duration: Duration)->Result[Timestamp, TimeError]
```

## sleep

Kind: fn.

```text
sleep: fn(duration: Duration)->Unit
```

## timestamp

Kind: fn.

```text
timestamp: fn(seconds: Int, nanoseconds: Int)->Result[Timestamp, TimeError]
```

## unix_seconds

Kind: fn.

```text
unix_seconds: fn(value: Timestamp)->Int
```

