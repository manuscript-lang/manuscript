import Duration from "@std/time.ms"

# Runs immediate, delayed, and repeating operations with explicit cancellation.
export type Scheduler:
    # Maximum number of operations running at once; `start`, `after`, and `every` return Full beyond it. Must be at least 1.
    # Also bounds queued failure reports awaiting the reporter. none leaves both unbounded.
    limit: Optional[Int] = none
    # How many finished operations keep a queryable final status. none keeps every one, and 0 keeps none, so `status` reports Unknown and `restart` rejects the id once the operation ends.
    # A positive count evicts the oldest finished operation first.
    history_limit: Optional[Int] = none
    # How long `close` lets running operations finish on their own before cancelling them. none or a zero duration cancels immediately. A negative duration faults.
    drain: Optional[Duration] = none
    # Called with a SchedulerFailure for each operation that returns an error or faults, one report at a time and in completion order.
    # none writes a one-line diagnostic to standard error instead. A reporter fault is also written to standard error, and the reporter cannot close its own scheduler.
    reporter: Optional[fn(failure: SchedulerFailure) -> Unit] = none

impl Scheduler:
    # Runs `operation` once after `duration` has elapsed and returns its OperationId. A zero duration runs it as soon as it is scheduled.
    # A negative duration returns InvalidInput; a closing scheduler returns Closed and a full one returns Full. Cancelling during the wait prevents the call.
    fn after(
        duration: Duration,
        operation: fn() -> Result[Unit, Error]
    ) -> Result[OperationId, StartError]:

    # Runs `operation` repeatedly, sleeping `interval` before the first run and again after each run finishes, so runs never overlap.
    # It stops after the first operation that returns an error, which is reported as Failed. A zero or negative interval returns InvalidInput; Closed and Full apply as for `after`.
    fn every(
        interval: Duration,
        operation: fn() -> Result[Unit, Error]
    ) -> Result[OperationId, StartError]:

    # Cancels the operation `id` if it is still running, waits for it to stop, and schedules a new run with the same delay, repeat mode, and callback. Returns the new OperationId; the old id keeps its final status.
    # Only work created by `after` or `every` can restart. An unknown, evicted, or `start`-created id returns InvalidInput, and a closing scheduler returns Closed. An operation of this scheduler calling restart faults.
    fn restart(id: OperationId) -> Result[OperationId, StartError]:

    # Requests cancellation of a running operation and returns without waiting for it to stop; the final status becomes Cancelled.
    # An unknown or already finished id is ignored.
    fn cancel(id: OperationId) -> Unit:

    # Stops accepting work, waits up to `drain` for running operations, cancels the rest, and waits for them and for pending failure reports to finish.
    # Calling it again waits for the first close to complete. An operation or reporter of this scheduler calling close faults.
    fn close() -> Unit:

    # Runs `operation` right away as a background task and returns its OperationId.
    # Returns Closed after `close` begins and Full when `limit` operations are already running. An Err result is reported as Failed and a fault as Crashed.
    fn start(operation: fn() -> Result[Unit, Error]) -> Result[OperationId, StartError]:

    # Returns the operation's current status, or its final status once it has ended.
    # Unknown means the id was never issued by this scheduler, was evicted by `history_limit`, or finished while `history_limit` was 0.
    fn status(id: OperationId) -> WorkStatus:

# A scheduled operation that returned an error or raised a fault.
export type SchedulerFailure:
    # The operation returned `Err`; delivered to the scheduler's reporter.
    case Failed(
        # Id of the failed operation, as returned when it was started.
        operation: OperationId,
        # The error the operation returned.
        cause: Error
    )
    # The operation raised a fault, such as an index error or failed precondition, instead of returning.
    case Crashed(
        # Id of the operation that faulted.
        operation: OperationId,
        # Text of the fault that ended the operation.
        message: String
    )

# Why a task or task group did not complete successfully.
export type ExecutionError:
    # The group's `timeout` elapsed while tasks were still running, and they were cancelled.
    case Timeout
    # The group was closed or the surrounding task was cancelled before all tasks completed.
    case Cancelled
    # A task raised a fault. It takes precedence over Timeout and Cancelled when several failures occur.
    case Crashed(
        # Id of the task that faulted.
        operation: OperationId,
        # Text of the fault that ended the task.
        message: String
    )

# Opaque identifier used to inspect, cancel, or restart scheduled work.
export type OperationId:

# Why a scheduler could not start an operation.
export type StartError:
    # The scheduler is closing or closed and accepts no more work.
    case Closed
    # The scheduler already has `limit` operations running.
    case Full
    # A delay is negative, a repeat interval is not positive, or a restart id is unknown or not restartable.
    case InvalidInput

# Current or final state of a scheduled operation.
export type WorkStatus:
    # The operation has started and not yet finished.
    case Running
    # The operation returned `Ok`.
    case Succeeded
    # The operation returned `Err`; the error was sent to the reporter.
    case Failed
    # The operation was cancelled by `cancel`, `restart`, `close`, or the surrounding task before it finished.
    case Cancelled
    # The operation raised a fault; the fault was sent to the reporter.
    case Crashed
    # The id was not issued by this scheduler or its final status was not retained under `history_limit`.
    case Unknown

# Raises the cancellation fault when the current task has been cancelled.
export fn check_cancelled() -> Unit:

# Suspends the current task briefly so other ready work can run.
export fn yield_now() -> Unit:

# Starts child tasks and joins them together with an optional group timeout.
export type TaskGroup:
    # Time budget for all tasks in the group, measured from the first `start`. When it elapses with tasks still running, they are cancelled and `join` returns Timeout.
    # A zero duration expires immediately, none sets no limit, and a negative duration faults.
    timeout: Optional[Duration] = none

impl TaskGroup:
    # Starts `operation` as a concurrent child task and returns its handle without waiting.
    # Starting after `join` or `close` faults. After the group has failed or been cancelled, the operation is not run and its handle reports the group failure.
    fn start[T](operation: fn() -> T) -> Task[T]:

    # Seals the group against new tasks and waits for every task to finish, including cleanup. Returns Ok when all succeeded, or the group's first failure, with Crashed taking precedence.
    # A task or descendant calling join on its own group faults.
    fn join() -> Result[Unit, ExecutionError]:

    # Cancels unfinished tasks, waits for them, and releases the group; calling it again waits for the first close.
    # A task fault no `join` has observed is raised as a fault here, unless the surrounding task is itself being cancelled. A task of this group calling close faults.
    fn close() -> Unit:

# A handle to a child task. Join it to collect its result and observe failures.
export type Task[T]:

impl Task[T]:
    # Waits for the task and returns its result. If the task did not complete, returns the group's failure after sibling tasks finish cleanup.
    # Joining from inside the same group faults.
    fn join() -> Result[T, ExecutionError]:

impl Error for ExecutionError:
    # Returns the fault text verbatim for Crashed, and otherwise the fixed diagnostic `task execution: <reason>`, such as `task execution: operation timed out`.
    fn message() -> String:

impl Error for StartError:
    # Returns the fixed diagnostic `scheduler: <reason>`, such as `scheduler: capacity exhausted`.
    fn message() -> String:
