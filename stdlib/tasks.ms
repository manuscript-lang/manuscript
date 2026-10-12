# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Result from "@std/result.ms"

export type Background:
    fn cancel(id: OperationId) -> Unit
    fn close() -> Unit
    fn start(operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]
    fn status(id: OperationId) -> WorkStatus

export type BackgroundFailure:
    case Failed(operation: OperationId, cause: String)
    case Crashed(operation: OperationId, message: String)

export type ExecutionError:
    case TimedOut
    case Crashed(operation: OperationId, message: String)

export type OperationId

export type StartError:
    case Closed
    case Full

export type WorkStatus:
    case Running
    case Succeeded
    case Failed
    case Cancelled
    case Crashed
    case Unknown

export fn check_cancelled() -> Unit

# compiler binding: parallel (heterogeneous callable/result packs)


impl Error for ExecutionError:
    fn message() -> String

impl Error for StartError:
    fn message() -> String
