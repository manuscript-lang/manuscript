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

### ExecutionError.Cancelled

The group was closed or the surrounding task was cancelled before all tasks completed.

```manuscript
case Cancelled
```

### ExecutionError.Crashed

A task raised a fault. It takes precedence over Timeout and Cancelled when several failures occur.

```manuscript
case Crashed(operation: OperationId, message: String)
```

### ExecutionError.Timeout

The group's `timeout` elapsed while tasks were still running, and they were cancelled.

```manuscript
case Timeout
```

### ExecutionError.Crashed.message

Text of the fault that ended the task.

```manuscript
message: String
```

### ExecutionError.Crashed.operation

Id of the task that faulted.

```manuscript
operation: OperationId
```

### ExecutionError.Error.message

Returns the fault text verbatim for Crashed, and otherwise the fixed diagnostic `task execution: <reason>`, such as `task execution: operation timed out`.

```manuscript
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
    fn after(duration: Duration, operation: fn() -> Result[Unit, Error]) -> Result[OperationId, StartError]:
    fn every(interval: Duration, operation: fn() -> Result[Unit, Error]) -> Result[OperationId, StartError]:
    fn restart(id: OperationId) -> Result[OperationId, StartError]:
    fn cancel(id: OperationId) -> Unit:
    fn close() -> Unit:
    fn start(operation: fn() -> Result[Unit, Error]) -> Result[OperationId, StartError]:
    fn status(id: OperationId) -> WorkStatus:
```

### Scheduler.drain

How long `close` lets running operations finish on their own before cancelling them. none or a zero duration cancels immediately. A negative duration faults.

```manuscript
drain: Optional[Duration] = none
```

### Scheduler.history_limit

How many finished operations keep a queryable final status. none keeps every one, and 0 keeps none, so `status` reports Unknown and `restart` rejects the id once the operation ends.
A positive count evicts the oldest finished operation first.

```manuscript
history_limit: Optional[Int] = none
```

### Scheduler.limit

Maximum number of operations running at once; `start`, `after`, and `every` return Full beyond it. Must be at least 1.
Also bounds queued failure reports awaiting the reporter. none leaves both unbounded.

```manuscript
limit: Optional[Int] = none
```

### Scheduler.reporter

Called with a SchedulerFailure for each operation that returns an error or faults, one report at a time and in completion order.
none writes a one-line diagnostic to standard error instead. A reporter fault is also written to standard error, and the reporter cannot close its own scheduler.

```manuscript
reporter: Optional[fn(failure: SchedulerFailure) -> Unit] = none
```

### Scheduler.after

Runs `operation` once after `duration` has elapsed and returns its OperationId. A zero duration runs it as soon as it is scheduled.
A negative duration returns InvalidInput; a closing scheduler returns Closed and a full one returns Full. Cancelling during the wait prevents the call.

```manuscript
fn after(duration: Duration, operation: fn() -> Result[Unit, Error]) -> Result[OperationId, StartError]:
```

### Scheduler.cancel

Requests cancellation of a running operation and returns without waiting for it to stop; the final status becomes Cancelled.
An unknown or already finished id is ignored.

```manuscript
fn cancel(id: OperationId) -> Unit:
```

### Scheduler.close

Stops accepting work, waits up to `drain` for running operations, cancels the rest, and waits for them and for pending failure reports to finish.
Calling it again waits for the first close to complete. An operation or reporter of this scheduler calling close faults.

```manuscript
fn close() -> Unit:
```

### Scheduler.every

Runs `operation` repeatedly, sleeping `interval` before the first run and again after each run finishes, so runs never overlap.
It stops after the first operation that returns an error, which is reported as Failed. A zero or negative interval returns InvalidInput; Closed and Full apply as for `after`.

```manuscript
fn every(interval: Duration, operation: fn() -> Result[Unit, Error]) -> Result[OperationId, StartError]:
```

### Scheduler.restart

Cancels the operation `id` if it is still running, waits for it to stop, and schedules a new run with the same delay, repeat mode, and callback. Returns the new OperationId; the old id keeps its final status.
Only work created by `after` or `every` can restart. An unknown, evicted, or `start`-created id returns InvalidInput, and a closing scheduler returns Closed. An operation of this scheduler calling restart faults.

```manuscript
fn restart(id: OperationId) -> Result[OperationId, StartError]:
```

### Scheduler.start

Runs `operation` right away as a background task and returns its OperationId.
Returns Closed after `close` begins and Full when `limit` operations are already running. An Err result is reported as Failed and a fault as Crashed.

```manuscript
fn start(operation: fn() -> Result[Unit, Error]) -> Result[OperationId, StartError]:
```

### Scheduler.status

Returns the operation's current status, or its final status once it has ended.
Unknown means the id was never issued by this scheduler, was evicted by `history_limit`, or finished while `history_limit` was 0.

```manuscript
fn status(id: OperationId) -> WorkStatus:
```

## SchedulerFailure {data-api-kind="Alternative"}

A scheduled operation that returned an error or raised a fault.

```manuscript
type SchedulerFailure:
    case Failed(operation: OperationId, cause: Error)
    case Crashed(operation: OperationId, message: String)
```

### SchedulerFailure.Crashed

The operation raised a fault, such as an index error or failed precondition, instead of returning.

```manuscript
case Crashed(operation: OperationId, message: String)
```

### SchedulerFailure.Failed

The operation returned `Err`; delivered to the scheduler's reporter.

```manuscript
case Failed(operation: OperationId, cause: Error)
```

### SchedulerFailure.Crashed.message

Text of the fault that ended the operation.

```manuscript
message: String
```

### SchedulerFailure.Crashed.operation

Id of the operation that faulted.

```manuscript
operation: OperationId
```

### SchedulerFailure.Failed.cause

The error the operation returned.

```manuscript
cause: Error
```

### SchedulerFailure.Failed.operation

Id of the failed operation, as returned when it was started.

```manuscript
operation: OperationId
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

### StartError.Closed

The scheduler is closing or closed and accepts no more work.

```manuscript
case Closed
```

### StartError.Full

The scheduler already has `limit` operations running.

```manuscript
case Full
```

### StartError.InvalidInput

A delay is negative, a repeat interval is not positive, or a restart id is unknown or not restartable.

```manuscript
case InvalidInput
```

### StartError.Error.message

Returns the fixed diagnostic `scheduler: <reason>`, such as `scheduler: capacity exhausted`.

```manuscript
fn message() -> String:
```

## Task {data-api-kind="Native type"}

A handle to a child task. Join it to collect its result and observe failures.

```manuscript
type Task[T]:
    fn join() -> Result[T, ExecutionError]:
```

### Task.join

Waits for the task and returns its result. If the task did not complete, returns the group's failure after sibling tasks finish cleanup.
Joining from inside the same group faults.

```manuscript
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

### TaskGroup.timeout

Time budget for all tasks in the group, measured from the first `start`. When it elapses with tasks still running, they are cancelled and `join` returns Timeout.
A zero duration expires immediately, none sets no limit, and a negative duration faults.

```manuscript
timeout: Optional[Duration] = none
```

### TaskGroup.close

Cancels unfinished tasks, waits for them, and releases the group; calling it again waits for the first close.
A task fault no `join` has observed is raised as a fault here, unless the surrounding task is itself being cancelled. A task of this group calling close faults.

```manuscript
fn close() -> Unit:
```

### TaskGroup.join

Seals the group against new tasks and waits for every task to finish, including cleanup. Returns Ok when all succeeded, or the group's first failure, with Crashed taking precedence.
A task or descendant calling join on its own group faults.

```manuscript
fn join() -> Result[Unit, ExecutionError]:
```

### TaskGroup.start[T]

Starts `operation` as a concurrent child task and returns its handle without waiting.
Starting after `join` or `close` faults. After the group has failed or been cancelled, the operation is not run and its handle reports the group failure.

```manuscript
fn start[T](operation: fn() -> T) -> Task[T]:
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

### WorkStatus.Cancelled

The operation was cancelled by `cancel`, `restart`, `close`, or the surrounding task before it finished.

```manuscript
case Cancelled
```

### WorkStatus.Crashed

The operation raised a fault; the fault was sent to the reporter.

```manuscript
case Crashed
```

### WorkStatus.Failed

The operation returned `Err`; the error was sent to the reporter.

```manuscript
case Failed
```

### WorkStatus.Running

The operation has started and not yet finished.

```manuscript
case Running
```

### WorkStatus.Succeeded

The operation returned `Ok`.

```manuscript
case Succeeded
```

### WorkStatus.Unknown

The id was not issued by this scheduler or its final status was not retained under `history_limit`.

```manuscript
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

