from "@std/collections.ms" import range
from "@std/core.ms" import Closeable, panic
from "@std/shared.ms" import Shared, share
from "@std/time.ms" import Duration, Instant, clock, duration, sleep

extern def msrt_tasks_spawn(work: Callable[[], Unit]) -> Int

extern def msrt_tasks_join(handle: Int) -> Bool

extern def msrt_tasks_cancel(handle: Int) -> Unit

# Why a task produced no result.
export type TaskError:
    # The task's timeout (or its group's) passed before it finished, and it was cancelled.
    case TimedOut
    # The task was cancelled before it finished.
    case Cancelled

impl Error for TaskError:
    # Returns the fixed diagnostic `task: <reason>`.
    def message() -> String:
        match self:
            case TimedOut: return "task: timed out"
            case Cancelled: return "task: cancelled"

# The scheduler state of one task. Internal state.
export type TaskFlags:
    # Runtime handle of the task.
    handle: Int
    # Runtime handle of the task's timeout watcher, or -1 when it has none.
    watcher: Int
    # True once the task has ended and been collected.
    joined: Bool
    # True once the timeout passed and the task was asked to stop.
    timed_out: Bool
    # True when the task ended by cancellation.
    cancelled: Bool

# A started task that returns a `T`. `result` waits for it.
export type Task[T]:
    # Internal state: the task's scheduler state.
    flags: Shared[TaskFlags]
    # Internal state: empty until the task returns, then its one result.
    values: Shared[List[T]]

impl Task[T]:
    # Waits for the task and returns its result, or why it has none. Takes the result, so call it once.
    # Cancelling the waiting task unwinds it; the group's `close` then cancels this task.
    def result() -> Result[T, TaskError]:
        settle(self.flags)

        let flags = self.flags.get()

        if flags.cancelled:
            if flags.timed_out:
                return error(TaskError.TimedOut)

            return error(TaskError.Cancelled)

        var finished = self.values.take()
        if let value = finished.pop():
            return ok(value)

        panic("Task: the result was already taken")

# The tasks started in a group. Internal state.
export type GroupState[T]:
    # One entry per started task, in start order.
    tasks: List[Task[T]] = []

# Waits for the task to end, stops its watcher, and records how it ended. Does nothing when already done.
def settle(cell: Shared[TaskFlags]) -> Unit:
    if cell.get().joined:
        return

    let handle = cell.get().handle
    let watcher = cell.get().watcher
    let cancelled = msrt_tasks_join(handle)

    if watcher >= 0:
        msrt_tasks_cancel(watcher)
        msrt_tasks_join(watcher)

    let flags = cell.take()
    cell.put(TaskFlags(flags.handle, flags.watcher, True, flags.timed_out, cancelled))

# The body of a watcher task: waits out the limit, then cancels the task it watches.
def watch(cell: Shared[TaskFlags], limit: Duration) -> Unit:
    sleep(limit)

    let flags = cell.take()
    cell.put(
        TaskFlags(
            flags.handle, flags.watcher, flags.joined, True, flags.cancelled
        )
    )
    msrt_tasks_cancel(flags.handle)

# The smaller of two durations.
def shorter(left: Duration, right: Duration) -> Duration:
    if left.compare(right) <= 0:
        return left

    return right

# A scope that owns the tasks started in it. Every task returns a `T` (use `Unit` for effect-only work).
# Open a group with `with`: leaving the block cancels tasks that are still running and waits for all of them.
# Call `results`, `wait` or a task's `result` before the block ends to keep the work.
# `timeout` limits the whole group, counted from its creation; `spawn` can set a shorter limit for one task.
# A task that passes its limit is cancelled and has the result `TimedOut`. There is no limit unless one is given.
# Tasks run on the one runtime thread and switch only when one waits (`result`, `wait`, sleeping, I/O).
# A fault in a task ends the program. A task owns the values its closure captures; return results instead of sharing them.
export type TaskGroup[T]:
    # Limit for every task started in the group, counted from the group's creation; none for no limit.
    timeout: Optional[Duration] = none
    # When the group was created. Internal state.
    started: Instant = clock().now()
    # Internal state: the group's tasks, changed through the shared handle so the group works as a `with` binding.
    state: Shared[GroupState[T]] = share(GroupState[T]())

impl TaskGroup[T]:
    # Starts `work` as a task and returns its handle. It first runs when the caller waits.
    # `timeout` limits this task; the group's own limit still applies if it ends sooner.
    def spawn(work: Callable[[], T], timeout: Optional[Duration] = none) -> Task[T]:
        let values: Shared[List[T]] = share([])
        let flags = share(TaskFlags(-1, -1, False, False, False))
        let task_values = values

        let handle = msrt_tasks_spawn(
            lambda:
                let value = work()
                let empty = task_values.take()
                task_values.put([value])
        )

        var limit = timeout

        if let overall = self.timeout:
            let left = overall.subtract(clock().now().difference(self.started))

            if let own = limit:
                limit = some(shorter(own, left))
            else:
                limit = some(left)

        var watcher = -1

        if let wait_for = limit:
            if wait_for.compare(duration(0)) < 0:
                panic("TaskGroup: a timeout must not be negative")

            let watched = flags
            watcher = msrt_tasks_spawn(lambda: watch(watched, wait_for))

        let started_flags = flags.take()
        flags.put(TaskFlags(handle, watcher, False, False, False))

        let task = Task(flags, values)
        let current = self.state.take()
        self.state.put(GroupState[T](current.tasks.concat([Task(flags, values)])))
        return task

    # Waits for every started task and returns their results in start order, or the first task's error.
    def results() -> Result[List[T], TaskError]:
        let count = self.state.get().tasks.length()
        var values = List[T]()

        for index in range(0, count):
            let task = self.state.get().tasks.get(index)
            values.append(try task.result())

        return ok(values)

    # Waits for every started task to end. Returns `TimedOut` or `Cancelled` if any task ended without a result.
    def wait() -> Result[Unit, TaskError]:
        let count = self.state.get().tasks.length()
        var timed_out = False
        var cancelled = False

        for index in range(0, count):
            let cell = self.state.get().tasks.get(index).flags
            settle(cell)

            if cell.get().cancelled:
                if cell.get().timed_out:
                    timed_out = True
                else:
                    cancelled = True

        if timed_out:
            return error(TaskError.TimedOut)
        if cancelled:
            return error(TaskError.Cancelled)

        return ok(())

impl Closeable for TaskGroup[T]:
    # Cancels tasks that have not ended and waits for them. Safe to call again.
    var def close() -> Unit:
        let count = self.state.get().tasks.length()

        for index in range(0, count):
            let cell = self.state.get().tasks.get(index).flags
            if not cell.get().joined:
                msrt_tasks_cancel(cell.get().handle)

        for index in range(0, count):
            settle(self.state.get().tasks.get(index).flags)
