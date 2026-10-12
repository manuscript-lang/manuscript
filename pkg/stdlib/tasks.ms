# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Duration from "@std/time.ms"
import Result from "@std/result.ms"

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

export type SchedulerFailure:
    case Failed(operation: OperationId, cause: String)
    case Crashed(operation: OperationId, message: String)

export type ExecutionError:
    case TimedOut
    case Cancelled
    case Crashed(operation: OperationId, message: String)

export type OperationId:

export type StartError:
    case Closed
    case Full
    case InvalidInput

export type WorkStatus:
    case Running
    case Succeeded
    case Failed
    case Cancelled
    case Crashed
    case Unknown

export fn check_cancelled() -> Unit:

export fn yield_now() -> Unit:

export type TaskGroup:
    timeout: Optional[Duration] = none
    fn start[T](operation: fn() -> T) -> Task[T]:
    fn join() -> Result[Unit, ExecutionError]:
    fn close() -> Unit:

export type Task[T]:
    fn join() -> Result[T, ExecutionError]:

impl Error for ExecutionError:
    fn message() -> String:

impl Error for StartError:
    fn message() -> String:
