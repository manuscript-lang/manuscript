+++
title = "timers"
+++

# @std/timers.ms

Import each required symbol with `import Name from "@std/timers.ms"`.

## ScheduledTimer {data-api-kind="Interface"}

```manuscript
interface ScheduledTimer:
    fn close() -> Unit
    fn refresh() -> Result[Unit, TimerError]
    fn status() -> WorkStatus
```

## Timer {data-api-kind="Interface"}

```manuscript
interface Timer:
    fn close() -> Unit
    fn wait() -> Result[Int, TimerError]
    fn refresh() -> Result[Unit, TimerError]
```

## TimerError {data-api-kind="Alternative"}

```manuscript
type TimerError:
    case InvalidInput
    case Closed
```

```manuscript
impl Error for TimerError:
    fn message() -> String
```

## delay {data-api-kind="Function"}

```manuscript
fn delay[T](duration: Duration, value: T) -> T
```

## schedule_immediate {data-api-kind="Function"}

```manuscript
fn schedule_immediate(operation: fn() -> Result[Unit, String]) -> Result[ScheduledTimer, TimerError]
```

## schedule_interval {data-api-kind="Function"}

```manuscript
fn schedule_interval(delay: Duration, operation: fn() -> Result[Unit, String]) -> Result[ScheduledTimer, TimerError]
```

## schedule_timeout {data-api-kind="Function"}

```manuscript
fn schedule_timeout(delay: Duration, operation: fn() -> Result[Unit, String]) -> Result[ScheduledTimer, TimerError]
```

## set_immediate {data-api-kind="Function"}

```manuscript
fn set_immediate() -> Timer
```

## set_interval {data-api-kind="Function"}

```manuscript
fn set_interval(delay: Duration) -> Result[Timer, TimerError]
```

## set_timeout {data-api-kind="Function"}

```manuscript
fn set_timeout(delay: Duration) -> Result[Timer, TimerError]
```

## yield_now {data-api-kind="Function"}

```manuscript
fn yield_now() -> Unit
```

