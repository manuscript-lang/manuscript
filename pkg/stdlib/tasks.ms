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
    # Waits for the task and returns its result. If the task did not complete, returns the group's failure after sibling tasks finish cleanup.
    # Joining from inside the same group faults.
    fn join() -> Result[T, ExecutionError]:

impl Error for ExecutionError:
    # Returns the fault text verbatim for Crashed, and otherwise the fixed diagnostic `task execution: <reason>`, such as `task execution: operation timed out`.
    fn message() -> String:

impl Error for StartError:
    # Returns the fixed diagnostic `scheduler: <reason>`, such as `scheduler: capacity exhausted`.
    fn message() -> String:
# documentation documentation/concurrency/_index.md
# +++
# title = "Concurrent work"
# weight = 4
# +++
#
# # Concurrent work
#
# Ordinary calls run sequentially. Use a task group or scheduler when operations should run at the same time. Both accept ordinary functions; there is no separate `async` declaration.
#
# Read these pages in order:
#
# 1. [Starting tasks](task-groups.md): run operations together and collect typed results.
# 2. [Waiting for tasks](joining.md): understand success, failure, and group shutdown.
# 3. [Cancellation and timeouts](cancellation.md): request a stop and set time budgets.
# 4. [Scheduling work](scheduling.md): run delayed or repeating work under a service lifetime.
# 5. [Sharing data](sharing.md): distinguish shared references from safe concurrent access.
# 6. [Synchronizing updates](synchronization.md): protect a complete read-and-write operation with a lock.
# 7. [Queues](queues.md): store pending values locally or protect a shared queue.
#
# ## Fixed lifetimes
#
# A task group belongs to the execution that constructs it. Its tasks finish and run cleanup before the group closes. A scheduler likewise keeps its construction lifetime; submitting from another request does not change that relationship.
#
# References to a task, scheduler, or resource do not prolong its lifetime. Keep dependencies open until their work finishes, and acquire per-operation resources inside the operation's own `with` block. See [managing resources](../core-language/cleanup/_index.md).
#
# Compiler contributors can read the [runtime contracts](../contributing/concurrent-runtime.md) for transition and acquisition details.
# end-documentation
# documentation documentation/concurrency/cancellation.md
# +++
# title = "Cancellation and timeouts"
# weight = 3
# +++
#
# # Cancellation and timeouts
#
# Cancellation asks work to stop. It does not mean the work has already stopped; code must reach a checkpoint, leave its scopes, and finish cleanup. Request work follows the request's execution lifetime. Accepted scheduled work follows its scheduler's lifetime.
#
# ## Requests
#
# Hosts signal requests, joined groups signal their operations, and schedulers expose cancellation of admitted work:
#
# ```manuscript
# let id = try background.start(operation: work)
# background.cancel(id: id)
# ```
#
# The submission fragment belongs to a function returning `Result[U, StartError]`; work must have the [standard imports](scheduling.md) callable type. Other application error types need explicit adaptation.
#
# Successful `Scheduler.start` admission yields an `OperationId` through `Result[OperationId, StartError]`. `cancel(id: id)` returns `Unit`, is idempotent for an admitted ID, and requests cancellation without joining. Dropping an ID has no effect. The service retains responsibility for work until it finishes or service shutdown joins it. IDs the service did not admit, including IDs from other services or from joined groups, and IDs whose status has been evicted are harmless no-ops; an ID never identifies unrelated work.
#
# `cancel`, `status`, and `close` are receiver operations of the imported Scheduler service; there are no ambient cancellation or join functions. Using an already-typed service does not require importing its otherwise unused type name. `background.close()` is the waiting boundary: it stops admission and performs the configured drain, cancellation, and joining sequence. A closed service stays closed through all aliases.
#
# Late cancellation cannot overwrite an already committed completion. For scheduled work, the first accepted stop reason determines `WorkStatus`, except that a programming fault during cleanup takes precedence and reports `Crashed`. Joined groups have no per-operation cancellation; their caller-visible outcomes are defined in [joined groups](joining.md#group-lifecycle).
#
# ## Propagation and checkpoints
#
# Cancellation is cooperative: stopped work unwinds at its next checkpoint. These are checkpoints:
#
# - runtime operation entry and completion;
# - blocking I/O and other adapter calls;
# - each loop back-edge, before the next iteration of `for` or `while` starts;
# - an explicit `check_cancelled()` call.
#
# Loop checkpoints make CPU-bound loops respond promptly without source changes; they cost one poll of the context's stop signal per iteration. `check_cancelled()` remains available for long straight-line work. It is an imported standard function, not a language intrinsic:
#
# ```manuscript
# import check_cancelled from "@std/tasks.ms"
# ```
#
# Importing it supplies the operation declaration; the runtime supplies the current execution context when it is called. Cleanup runs under a shielded context, so checkpoints inside cleanup do not observe the initiating cancellation. No checkpoint occurs between `with` acquisition and cleanup registration; see [completion and acquisition](../contributing/concurrent-runtime.md#completion-and-resource-acquisition).
#
# Cancelling a request or current operation cancels its nested groups. Each group joins its operations, each operation runs its registered `with` cleanup, and the caller unwinds.
#
# Scheduler service cancellation reaches the work admitted under that service. Cancellation of a submitting request does not cancel accepted work, because the background lifetime was selected at admission. Cancellation before admission must not start work. Admission and acknowledgement can race with request cancellation; callers must use application idempotency keys if a retried submission must not duplicate work.
#
# Completed external writes remain completed. Cancellation does not provide rollback; a transaction's explicit resource contract does.
#
# Cleanup is shielded from the initiating cancellation and expired work deadline. It may exceed that deadline; it retains capability authority and remains subject to [host escalation](../contributing/concurrent-runtime.md#host-escalation). See [cleanup faults](../core-language/cleanup/cleanup-faults.md).
#
# For native application shutdown, use registered `with` cleanup; observing SIGINT/SIGTERM does not claim the signal or protect code after `SignalStream.next()`. See the [shutdown cookbook](shutdown.md) for a runnable server, cancelled-worker ordering, and current host limitations.
#
# ## Waiting for a synchronized value
#
# `Synchronized.lock()` waits cooperatively and observes cancellation. If cancellation wins before the guard is delivered, the runtime releases that acquisition. Use `with locked = cell.lock()` so a delivered guard is registered for cleanup before another checkpoint.
#
# Cancellation of a lock holder unwinds its `with` scope and closes the guard. It never releases the lock while the holder is still running. Updates already made through `locked.set()` remain committed; releasing the guard does not roll them back. Guard cleanup is idempotent and shielded from the initiating cancellation. See [synchronizing updates](synchronization.md#synchronized).
#
# Cross-task lock cycles wait rather than faulting automatically. Cancellation or a group timeout can stop an ordinary lock waiter, but cannot cancel a shielded cleanup wait or abandon a mandatory cleanup join. Release a held guard before joining work that needs it; deadlines do not guarantee escape from cleanup cycles.
#
# ## Timeouts
#
# Timeouts are named library arguments, not syntax annotations. Duration values come from the standard time API; naming `Duration` requires its own import from `@std/time.ms`.
#
# `TaskGroup(timeout: 2.seconds)` sets one group budget, starting with the first submission. The budget applies across its operations; `timeout` is the only budget argument.
#
# On expiry, unfinished tasks stop and join before a failed task or group join reports Timeout. A timeout bounds ordinary work, not cleanup or joining. Foreign code that does not cooperate can delay joining; [host escalation](../contributing/concurrent-runtime.md#host-escalation) is the final fallback.
#
# To share one budget across sequential steps, submit one callback containing those steps:
#
# ```manuscript
# with tasks = TaskGroup(timeout: 2.seconds):
#     let task = tasks.start(sync)
#     let outcome = try task.join()
# ```
#
# This fragment requires an enclosing Result with ExecutionError. The callback's domain return value remains unchanged. Nested groups inherit cancellation from their fixed parent.
#
# ## Deadlines
#
# Hosts establish deadlines for application, session, CLI, and request execution contexts. Every operation inherits its fixed parent's deadline. A joined group can only shorten it with `timeout`; nothing in source can extend an inherited deadline. The effective deadline is the earliest of the inherited deadline and any group timeout.
#
# Budgets use the runtime's monotonic timer, not a `Clock` capability or calendar time. A test runner may virtualize that timer; a fake `Clock` value does not affect execution budgets.
#
# When the caller's own deadline expires, the caller unwinds after its groups join; it does not receive `Timeout`. Only a group's own timeout produces `Timeout`.
#
# Scheduler work inherits the service's fixed execution context, including that context's deadline. It does not inherit the submitting request's deadline. A service cannot revive cancelled work or extend its host's deadline. Its context is selected at construction, not at each call to `start`.
#
# Deadline configuration is a host operation. Task handles do not expose deadline mutation; there are no deadline annotations on functions or absolute deadline arguments. See [scheduling work](scheduling.md) for drain budgets and [adapter contexts](../contributing/concurrent-runtime.md#adapter-execution-contexts).
# end-documentation
# documentation documentation/concurrency/joining.md
# +++
# title = "Waiting for tasks"
# weight = 2
# +++
#
# # Waiting for tasks
#
# Joining waits for work to finish its body and cleanup. `Task.join()` waits for one successful task; a failed task join waits for its stopped group. `TaskGroup.join()` waits for all submitted work. Closing a group cancels unfinished work and joins it.
#
# ## Terms
#
# | Term | Meaning |
# | --- | --- |
# | Operation | One invocation submitted through `TaskGroup.start` or `Scheduler.start` |
# | Group | Operations submitted to one `TaskGroup` |
# | Parent | The execution that constructed the group; it fixes cancellation and host roots |
# | Joined | Every required operation has finished its body and cleanup |
#
# ## Execution errors
#
# `ExecutionError` and its diagnostic `OperationId` are exported by `@std/tasks.ms`:
#
# ```manuscript
# type ExecutionError:
#     case Timeout
#     case Cancelled
#     case Crashed(operation: OperationId, message: String)
# ```
#
# An operation ID identifies work for diagnostics. It does not grant scheduling, cancellation, or joining authority.
#
# ## Group lifecycle
#
# 1. **Construct.** Store the construction execution as the fixed parent. Register shutdown with that execution's work lifetime; lexical `with` provides an earlier cleanup boundary.
# 2. **Start.** Each `start` prepares its callback and admits one typed task. A group timeout starts with the first submission. A stopped group returns a stopped handle without invoking further callbacks; a joined or closed group rejects submission with a programming fault.
# 3. **Stop.** A task fault, timeout, parent cancellation, or explicit close cancels unfinished work. Returning a domain error is ordinary completion. Task outcomes committed before the stop remain available.
# 4. **Join.** Group joining seals admission and waits for every started operation, including nested service shutdown and cleanup. A successful individual task join leaves admission open; a failed one waits for the stopped group, so it seals admission like a group join and a later `start` is the same programming fault. Joining is never bounded by the timeout.
# 5. **Report.** Group joins and failed task joins use the outcome order below. A successful individual task join returns that task's committed value.
#
# | Condition after joining | Caller observes |
# | --- | --- |
# | The joining caller's own context was cancelled or reached its inherited deadline | The caller unwinds after cancellation and joining; no Result is delivered |
# | A task faulted in its body or cleanup | `error(cause: Crashed(...))` for the first committed fault |
# | The group's timeout expired while work was outstanding | `error(cause: Timeout)` |
# | Explicit close cancelled unfinished work, or the fixed parent stopped while another active execution joined | `error(cause: Cancelled)` |
# | Otherwise | Group join returns `ok(value: unit)`; task join returns its cached value |
#
# A programming fault takes precedence over a timeout or cancellation outcome. Simultaneous task faults have a scheduling-dependent primary. Outcome commitment and acceptance of a stop share an atomic transition. A completed task is not rerun by joining, and its result is not overwritten by a later stop.
#
# Joining from a cancelled caller cancels and waits for unfinished group work before unwinding. Secondary faults during caller cancellation reach diagnostics. Cleanup remains shielded and may exceed any deadline; uncooperative foreign work falls to [host escalation](../contributing/concurrent-runtime.md#host-escalation).
#
# ## Scope cleanup and fault observation
#
# `close()` stops admission, cancels unfinished work, waits for all started operations, and releases the group from its fixed work lifetime. It is safe to close repeatedly or through aliases. Successfully committed task results survive closure; unfinished task handles report cancellation to an active joining execution.
#
# A failed group or task join marks the execution failure observed. Closing a group with an unobserved task programming fault surfaces a cleanup fault, so starting work and dropping its handle cannot silently discard a crash. Returning domain errors does not create a cleanup fault.
#
# Tasks and their descendants cannot join or close their own group or join its task handles. Cross-group cycles are invalid application usage. There is no per-task cancellation; use the group's close boundary or a scheduler's operation-ID cancellation.
#
# See [task groups](task-groups.md), [cancellation](cancellation.md), and [scope cleanup](../core-language/cleanup/exit-order.md).
# end-documentation
# documentation documentation/concurrency/scheduling.md
# +++
# title = "Scheduling work"
# weight = 4
# +++
#
# # Scheduling work
#
# `Scheduler` from `@std/tasks.ms` manages immediate, delayed, and repeating work under one fixed lifetime. Ordinary sequential delays use `sleep` from `@std/time.ms`.
#
# ```manuscript
# import Scheduler from "@std/tasks.ms"
#
# fn send() -> Result[Unit, Error]:
#     return ok(unit)
#
# fn start_work() -> Unit:
#     with scheduler = Scheduler():
#         let immediate = scheduler.start(send)
#         let delayed = scheduler.after(duration: 20.milliseconds, operation: send)
#         let repeated = scheduler.every(interval: 1.seconds, operation: send)
# ```
#
# The three admission operations return `Result[OperationId, StartError]`. They share `status(id)`, `cancel(id)`, failure reporting, and scoped shutdown. `after` accepts a nonnegative delay; `every` requires a positive interval. Invalid durations return `InvalidInput`. A repeating callback runs sequentially and waits its interval after each completion; missed intervals do not accumulate callbacks. A returned failure stops repetition and reaches the reporter as `SchedulerFailure.Failed(operation, cause)`, where `cause` is the callback's `Error` value unchanged. Return a domain error directly, or `TextError.Text("message")` from `@std/errors.ms` when only text is meant; the reporter can match the concrete type or call `category(cause)`. A callback that returned `Result[Unit, String]` must now return an `Error`.
#
# `Scheduler()` has no admission or status-history cap. Supply `limit: n` to bound accepted unfinished operations, or `history_limit: n` to retain only the most recent completed statuses. A supplied admission limit must be positive; history may be zero. Optional `reporter` and `drain` use Optional callback and Duration values. Their defaults are the host diagnostic sink and immediate cancellation on close. Omitted caps and explicit `none` mean unbounded.
#
# Admission checks closure and reserves capacity atomically. Full admission returns `Full` immediately and does not run the operation; completion releases capacity before reporting. A supplied admission limit also bounds pending reports, with overflow sent to host diagnostics. With no limit, reports queue without an imposed cap. Reporter calls run serially outside transition locks; shutdown joins them.
#
# `restart(id)` cancels and joins an active scheduled operation, then starts its original schedule with a fresh ID. It also restarts completed or failed schedules while their history is retained. Immediate-operation IDs and unknown or evicted IDs return `InvalidInput`; closed services return `Closed`. Restarting from the service's own callback or reporter faults because it could join itself. Keep the returned new ID for subsequent status or cancellation.
#
# ## Lifetime and shutdown
#
# Construct a scheduler under the application, component, session, or request lifetime that should own its work. Submitting from another execution does not reparent accepted work. Captured resources must remain usable for the entire operation; references do not extend a resource's `with` lifetime.
#
# `cancel(id)` requests cancellation without joining. Unknown IDs are harmless no-ops. `status(id)` returns `Unknown` for IDs the scheduler did not admit or has evicted. IDs are never reused. Dropping an ID or alias has no effect on work lifetime.
#
# `close()` stops admission, allows the optional drain period, cancels unfinished work, and joins callbacks, their cleanup, and reporting. It is idempotent across aliases. Parent cancellation also cancels accepted work. A callback or reporter cannot close its own scheduler. Close the scheduler before its dependencies.
#
# Scheduling is process-local. Work that must survive a process restart needs durable application storage. Shutdown cannot forcibly terminate uncooperative native code; host escalation is described in [runtime requirements](../contributing/concurrent-runtime.md).
# end-documentation
# documentation documentation/concurrency/task-groups.md
# +++
# title = "Starting tasks"
# weight = 1
# +++
#
# # Starting tasks
#
# Use a `TaskGroup` to start independent operations and retrieve each result through a typed `Task[T]` handle. Ordinary calls remain sequential; `start` explicitly starts concurrent work.
#
# ## Starting and joining tasks
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import { TaskGroup, ExecutionError } from "@std/tasks.ms"
# import panic from "@std/faults.ms"
#
# fn number() -> Int: 42
# fn greeting() -> String: "hello"
#
# fn check() -> Result[Unit, ExecutionError]:
#     with tasks = TaskGroup():
#         let number_task = tasks.start(number)
#         let greeting_task = tasks.start(greeting)
#         let completed = try tasks.join()
#         let value = try number_task.join()
#         let message = try greeting_task.join()
#         if value != 42 or message != "hello":
#             return panic("task results changed")
#         return ok(unit)
#
# test "independent typed results":
#     if check().is_error(): return panic("task group failed")
# ```
#
# `start` infers `T` from its zero-argument callback. The handles above have types `Task[Int]` and `Task[String]`. Naming `Task` in an annotation requires its own import; inferred handles do not. Handles can be stored in records, passed through generic functions, returned, and collected in ordinary homogeneous lists.
#
# `Task.join()` waits for that task's body and cleanup, returning `Result[T, ExecutionError]`. Successful individual joins leave admission open. Repeated joins return the cached outcome without running the callback again. Successfully committed values remain available after the group closes.
#
# `TaskGroup.join()` seals admission and waits for every submitted task and its cleanup, returning `Result[Unit, ExecutionError]`. Repeated group joins are permitted. Starting new work after a group join or close is a programming fault. To retrieve values after joining the group, join each retained handle; those reads are immediate.
#
# ## Preparation
#
# Each `start` evaluates its receiver and callback argument before submitting that operation. Creating a closure snapshots its captures without running its body. Once a `start` succeeds, its operation may run while the caller prepares later submissions. If later preparation fails, the enclosing `with` cancels and joins previously started work.
#
# Passing `load_user()` executes that call during preparation. Pass a function such as `load_user` or an explicitly typed zero-argument closure instead. Function values, bound methods, and contract views retain their ordinary rules; saving generic `start` as a function value requires explicit specialization, such as `tasks.start[Int]`.
#
# Concurrent effect order is nondeterministic. Shared mutable data needs explicit synchronization; see [Synchronized](synchronization.md#synchronized). Capturing a Map, List, or record shares its storage. See the [unsafe and guarded capture examples](sharing.md#captured-mutable-data) and the limits of the MSL105 advisory before mutating captured data.
#
# ## Errors and scope exit
#
# A callback's return value is preserved unchanged. If it returns `Result[User, UserError]`, its handle is `Task[Result[User, UserError]]` and joining returns `Result[Result[User, UserError], ExecutionError]`. A domain error is ordinary completion and does not cancel siblings. Handle execution and domain errors separately; `try` requires the enclosing function's exact error type.
#
# A task fault cancels siblings. A failed task join or group join waits for their cleanup before reporting `ExecutionError.Crashed`. Successfully committed task values remain available independently of a later sibling fault. See [joined group outcomes](joining.md#group-lifecycle).
#
# Use `with tasks = TaskGroup()` to give the work a lexical lifetime. Scope exit calls `close()`, which cancels unfinished tasks and joins them. Closing is idempotent through aliases. A task cancelled by explicit close has an `ExecutionError.Cancelled` outcome. An unobserved task programming fault surfaces from close; joining the failure explicitly marks it observed.
#
# References do not extend work or resource lifetimes. A saved task handle can read a completed result after its group closes, but cannot keep unfinished work running. Resource cleanup remains explicit through `with`; results and captures are not recursively closed.
#
# ## Timeouts
#
# `TaskGroup(timeout: 2.seconds)` applies one budget starting at the first submission. Omitted or `none` timeout adds no limit; inherited cancellation still applies. Negative timeouts fault. A zero timeout starts no callback and yields `Timeout`; an empty group joins successfully. Timeout expiry cancels unfinished work and joins it before reporting failure.
#
# A group's task or descendant must not join or close that same group, or join one of its handles. These operations fault before waiting to prevent self-joining. See [joining](joining.md), [cancellation](cancellation.md), and [runtime contracts](../contributing/concurrent-runtime.md).
# end-documentation
