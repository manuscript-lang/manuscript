# Canonical standard-library declarations. Implementations are native.

import Duration from "@std/time.ms"

# Runs immediate, delayed, and repeating operations with explicit cancellation.
export type Scheduler:
    limit: Optional[Int] = none
    history_limit: Optional[Int] = none
    drain: Optional[Duration] = none
    reporter: Optional[fn(failure: SchedulerFailure) -> Unit] = none
    fn after(
        duration: Duration,
        operation: fn() -> Result[Unit, String]
    ) -> Result[OperationId, StartError]:
    fn every(
        interval: Duration,
        operation: fn() -> Result[Unit, String]
    ) -> Result[OperationId, StartError]:
    fn restart(id: OperationId) -> Result[OperationId, StartError]:
    fn cancel(id: OperationId) -> Unit:
    fn close() -> Unit:
    fn start(operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]:
    fn status(id: OperationId) -> WorkStatus:

# A scheduled operation that returned an error or raised a fault.
export type SchedulerFailure:
    case Failed(operation: OperationId, cause: String)
    case Crashed(operation: OperationId, message: String)

# Why a task or task group did not complete successfully.
export type ExecutionError:
    case TimedOut
    case Cancelled
    case Crashed(operation: OperationId, message: String)

# Opaque identifier used to inspect, cancel, or restart scheduled work.
export type OperationId:

# Why a scheduler could not start an operation.
export type StartError:
    case Closed
    case Full
    case InvalidInput

# Current or final state of a scheduled operation.
export type WorkStatus:
    case Running
    case Succeeded
    case Failed
    case Cancelled
    case Crashed
    case Unknown

# Raises the cancellation fault when the current task has been cancelled.
export fn check_cancelled() -> Unit:

# Suspends the current task briefly so other ready work can run.
export fn yield_now() -> Unit:

# Starts child tasks and joins them together with an optional group timeout.
export type TaskGroup:
    timeout: Optional[Duration] = none
    fn start[T](operation: fn() -> T) -> Task[T]:
    fn join() -> Result[Unit, ExecutionError]:
    fn close() -> Unit:

# A handle to a child task. Join it to collect its result and observe failures.
export type Task[T]:
    fn join() -> Result[T, ExecutionError]:

impl Error for ExecutionError:
    fn message() -> String:

impl Error for StartError:
    fn message() -> String:
