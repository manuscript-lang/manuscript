+++
title = "tasks"
+++

# @std/tasks.ms

Import each required symbol with `import Name from "@std/tasks.ms"`.

## ExecutionError {data-api-kind="Alternative"}

Why a task or task group did not complete successfully.

```manuscript
type ExecutionError:
    case Timeout
    case Cancelled
    case Crashed(operation: OperationId, message: String)
```

```manuscript
impl Error for ExecutionError:
    fn message() -> String:
```

## OperationId {data-api-kind="Native type"}

Opaque identifier used to inspect, cancel, or restart scheduled work.

```manuscript
type OperationId:
```

## Scheduler {data-api-kind="Native type"}

Runs immediate, delayed, and repeating operations with explicit cancellation.

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

A scheduled operation that returned an error or raised a fault.

```manuscript
type SchedulerFailure:
    case Failed(operation: OperationId, cause: String)
    case Crashed(operation: OperationId, message: String)
```

## StartError {data-api-kind="Alternative"}

Why a scheduler could not start an operation.

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

A handle to a child task. Join it to collect its result and observe failures.

```manuscript
type Task[T]:
    fn join() -> Result[T, ExecutionError]:
```

## TaskGroup {data-api-kind="Native type"}

Starts child tasks and joins them together with an optional group timeout.

```manuscript
type TaskGroup:
    timeout: Optional[Duration] = none
    fn start[T](operation: fn() -> T) -> Task[T]:
    fn join() -> Result[Unit, ExecutionError]:
    fn close() -> Unit:
```

## WorkStatus {data-api-kind="Alternative"}

Current or final state of a scheduled operation.

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

Raises the cancellation fault when the current task has been cancelled.

```manuscript
fn check_cancelled() -> Unit:
```

## yield_now {data-api-kind="Function"}

Suspends the current task briefly so other ready work can run.

```manuscript
fn yield_now() -> Unit:
```

