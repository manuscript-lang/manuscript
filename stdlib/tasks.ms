from "@std/collections.ms" import range
from "@std/core.ms" import Closeable, panic
from "@std/shared.ms" import Shared, share
from "@std/time.ms" import Duration

extern def msrt_scope_new() -> Int

extern def msrt_scope_spawn(
    scope: Int,
    work: Callable[[], Unit],
    task_limit_ns: Int,
    scope_limit_ns: Int
) -> Int

extern def msrt_scope_join(handle: Int, keep: Int) -> Int

extern def msrt_scope_wait(scope: Int) -> Int

extern def msrt_scope_close(scope: Int) -> Unit

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

# Maps a runtime outcome (0 returned, 1 timed out, 2 cancelled) to a result.
def outcome(code: Int) -> Result[Unit, TaskError]:
    if code == 1:
        return error(TaskError.TimedOut)
    if code == 2:
        return error(TaskError.Cancelled)

    if code == 3:
        panic("Task: its result was already collected or its group was closed")
    return ok(())

# A limit in nanoseconds, or -1 for none.
def nanos(limit: Optional[Duration]) -> Int:
    if let own = limit:
        if own.to_nanoseconds() < 0:
            panic("TaskGroup: a timeout must not be negative")
        return own.to_nanoseconds()

    return -1

# The body of a task: runs `work` and stores its one result in `slot`.
def run[T](work: Callable[[], T], slot: Shared[List[T]]) -> Unit:
    let value = work()
    var held = slot.take()
    held.append(value)
    slot.put(held)

# A started task that returns a `T`. `result` waits for it.
export type Task[T]:
    # Internal state: the runtime handle of the task.
    handle: Int
    # Internal state: empty until the task returns, then its one result.
    values: Shared[List[T]]

impl Task[T]:
    # Waits for the task and returns its result, or why it has none. Takes the result, so call it once.
    def result() -> Result[T, TaskError]:
        try outcome(msrt_scope_join(self.handle, 0))

        var finished = self.values.take()
        if let value = finished.pop():
            return ok(value)

        panic("Task: the result was already taken")

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
    # Internal state: the runtime scope that owns the tasks.
    scope: Int = msrt_scope_new()
    # Internal state: the tasks in start order, changed through the shared handle so the group works as a `with` binding.
    tasks: Shared[List[Task[T]]] = share([])

impl TaskGroup[T]:
    # Starts `work` as a task and returns its handle. It first runs when the caller waits.
    # `timeout` limits this task; the group's own limit still applies if it ends sooner.
    def spawn(work: Callable[[], T], timeout: Optional[Duration] = none) -> Task[T]:
        let values: Shared[List[T]] = share([])
        let slot = values
        let handle = msrt_scope_spawn(
            self.scope, lambda: run(work, slot), nanos(timeout), nanos(self.timeout)
        )
        let task = Task(handle, values)
        var started = self.tasks.take()
        started.append(Task(handle, values))
        self.tasks.put(started)
        return task

    # Waits for every started task and returns their results in start order, or the first task's error.
    def results() -> Result[List[T], TaskError]:
        let count = self.tasks.get().length()
        var values = List[T]()
        for index in range(0, count):
            values.append(try self.tasks.get().get(index).result())
        return ok(values)

    # Waits for every started task to end. Returns `TimedOut` or `Cancelled` if any task ended without a result.
    def wait() -> Result[Unit, TaskError]:
        return outcome(msrt_scope_wait(self.scope))

impl Closeable for TaskGroup[T]:
    # Cancels tasks that have not ended and waits for them. Safe to call again.
    var def close() -> Unit:
        msrt_scope_close(self.scope)
