# Canonical standard-library declarations. Implementations are native.

import WorkStatus from "@std/tasks.ms"
import Duration from "@std/time.ms"
import Error from "@std/errors.ms"
import Result from "@std/result.ms"

export interface Timer:
    fn close() -> Unit
    fn wait() -> Result[Int, TimerError]
    fn refresh() -> Result[Unit, TimerError]

export fn set_timeout(delay: Duration) -> Result[Timer, TimerError]
export fn set_interval(delay: Duration) -> Result[Timer, TimerError]
export fn set_immediate() -> Timer
export fn yield_now() -> Unit
export fn delay[T](duration: Duration, value: T) -> T

export interface ScheduledTimer:
    fn close() -> Unit
    fn refresh() -> Result[Unit, TimerError]
    fn status() -> WorkStatus

export fn schedule_timeout(delay: Duration, operation: fn() -> Result[Unit, String]) -> Result[ScheduledTimer, TimerError]
export fn schedule_interval(delay: Duration, operation: fn() -> Result[Unit, String]) -> Result[ScheduledTimer, TimerError]
export fn schedule_immediate(operation: fn() -> Result[Unit, String]) -> Result[ScheduledTimer, TimerError]

export type TimerError:
    case InvalidInput
    case Closed

impl Error for TimerError:
    fn message() -> String
