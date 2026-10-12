+++
title = "time"
+++

# @std/time.ms

Import each required symbol with `import Name from "@std/time.ms"`.

## Clock

Kind: interface.

```manuscript
Clock: Clock
operation now: fn()->Instant
```

## Duration

Kind: native.

```manuscript
Duration: Duration
```

## Instant

Kind: native.

```manuscript
Instant: Instant
```

## Timestamp

Kind: native.

```manuscript
Timestamp: Timestamp
```

## WallClock

Kind: interface.

```manuscript
WallClock: WallClock
operation now: fn()->Timestamp
```

## difference

Kind: fn.

```manuscript
difference: fn(left: Timestamp, right: Timestamp)->Result[Duration, LibraryError]
```

## format_timestamp

Kind: fn.

```manuscript
format_timestamp: fn(value: Timestamp)->String
```

## nanoseconds

Kind: fn.

```manuscript
nanoseconds: fn(value: Timestamp)->Int
```

## parse_timestamp

Kind: fn.

```manuscript
parse_timestamp: fn(text: String)->Result[Timestamp, LibraryError]
```

## shift

Kind: fn.

```manuscript
shift: fn(value: Timestamp, duration: Duration)->Result[Timestamp, LibraryError]
```

## sleep

Kind: fn.

```manuscript
sleep: fn(duration: Duration)->Unit
```

## timestamp

Kind: fn.

```manuscript
timestamp: fn(seconds: Int, nanoseconds: Int)->Result[Timestamp, LibraryError]
```

## unix_seconds

Kind: fn.

```manuscript
unix_seconds: fn(value: Timestamp)->Int
```

