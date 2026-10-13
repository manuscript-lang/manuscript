+++
title = "tasks"
+++

# @std/tasks.ms

Import each required symbol with `import Name from "@std/tasks.ms"`.

## ExecutionError {data-api-kind="Alternative"}

```manuscript
type ExecutionError:
    case TimedOut
    case Cancelled
    case Crashed(operation: OperationId, message: String)
```

```manuscript
impl Error for ExecutionError:
    fn message() -> String:
```

## OperationId {data-api-kind="Native type"}

```manuscript
type OperationId:
```

## Scheduler {data-api-kind="Native type"}

```manuscript
type Scheduler:
    limit: Optional[Int] = none
    history_limit: Optional[Int] = none
    drain: Optional[Duration] = none
    reporter: Optional[fn(failure: SchedulerFailure) -> Unit] = none
    fn after(duration: Duration, operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]:
    fn every(interval: Duration, operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]:
    fn restart(id: OperationId) -> Result[OperationId, StartError]:
    fn cancel(id: OperationId) -> Unit:
    fn close() -> Unit:
    fn start(operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]:
    fn status(id: OperationId) -> WorkStatus:
```

## SchedulerFailure {data-api-kind="Alternative"}

```manuscript
type SchedulerFailure:
    case Failed(operation: OperationId, cause: String)
    case Crashed(operation: OperationId, message: String)
```

## StartError {data-api-kind="Alternative"}

```manuscript
type StartError:
    case Closed
    case Full
    case InvalidInput
```

```manuscript
impl Error for StartError:
    fn message() -> String:
```

## Task {data-api-kind="Native type"}

```manuscript
type Task[T]:
    fn join() -> Result[T, ExecutionError]:
```

## TaskGroup {data-api-kind="Native type"}

```manuscript
type TaskGroup:
    timeout: Optional[Duration] = none
    fn start[T](operation: fn() -> T) -> Task[T]:
    fn join() -> Result[Unit, ExecutionError]:
    fn close() -> Unit:
```

## WorkStatus {data-api-kind="Alternative"}

```manuscript
type WorkStatus:
    case Running
    case Succeeded
    case Failed
    case Cancelled
    case Crashed
    case Unknown
```

## check_cancelled {data-api-kind="Function"}

```manuscript
fn check_cancelled() -> Unit:
```

## yield_now {data-api-kind="Function"}

```manuscript
fn yield_now() -> Unit:
```

