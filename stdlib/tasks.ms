from "@std/channels.ms" import Channel, ChannelError, Transport
from "@std/collections.ms" import range
from "@std/core.ms" import Closeable, panic
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
from "@std/time.ms" import Duration

extern def msrt_scope_new() -> Int

extern def msrt_scope_spawn(
    scope: Int,
    work: Callable[[], Unit],
    task_limit_ns: Int,
    scope_limit_ns: Int
) -> Int

extern def msrt_scope_contain(scope: Int) -> Unit

extern def msrt_scope_fault_message() -> String

extern def msrt_scope_started() -> Unit

extern def msrt_task_cancel_requested() -> Int

extern def msrt_scope_join(scope: Int, handle: Int, keep: Int) -> Int

extern def msrt_scope_wait(scope: Int) -> Int

extern def msrt_scope_close(scope: Int) -> Unit

extern def msrt_channel_token() -> Int

extern def msrt_channel_park(token: Int) -> Unit

extern def msrt_channel_post(token: Int) -> Unit

# Why a task produced no result.
export type TaskError:
    # The task's timeout (or its group's) passed before it finished, and it was cancelled.
    case TimedOut
    # The task was cancelled before it finished.
    case Cancelled
    # The task's group was closed, or its result was already collected.
    case Closed
    # The task faulted in a group that contains faults. Carries the fault report.
    case Faulted(
        # The fault report from the task: its message and stack.
        message: String
    )

impl Error for TaskError:
    # Returns the fixed diagnostic `task: <reason>`.
    def message() -> String:
        match self:
            case TimedOut: return "task: timed out"
            case Cancelled: return "task: cancelled"
            case Closed: return "task: closed"
            case Faulted(message): return "task: fault: " + message

# Whether the running task was cancelled: its group was closed, its timeout passed, or the program was asked to stop.
# A plain query: it neither waits nor unwinds, so a task can poll it between steps and finish early.
# It stays true inside cleanups (`with` blocks), where a cancelled task should do minimal work.
export def cancelled() -> Bool:
    return msrt_task_cancel_requested() != 0

# Maps a runtime outcome (0 returned, 1 timed out, 2 cancelled, 3 closed or collected, 4 faulted) to a result.
def outcome(code: Int) -> Result[Unit, TaskError]:
    if code == 1:
        return error(TaskError.TimedOut)
    if code == 2:
        return error(TaskError.Cancelled)
    if code == 3:
        return error(TaskError.Closed)
    if code == 4:
        return error(TaskError.Faulted(msrt_scope_fault_message()))

    return ok(())

# A new runtime scope, one that contains task faults when `contain` is set.
def new_scope(contain: Bool) -> Int:
    let scope = msrt_scope_new()
    if contain:
        msrt_scope_contain(scope)
    return scope

# A limit in nanoseconds, or -1 for none.
def nanos(limit: Optional[Duration]) -> Int:
    if let own = limit:
        if own.to_nanoseconds() < 0:
            panic("TaskGroup: a timeout must not be negative")
        return own.to_nanoseconds()

    return -1

# How many unread values one direction of a task channel holds before a send waits.
def room() -> Int:
    return 16

# One direction of a task channel: the values sent and not yet received, and who waits on them.
type Lane[T]:
    # Values to receive next, newest first.
    front: List[T] = []
    # Values sent after `front` was filled, oldest first.
    back: List[T] = []
    # The sending end closed: the receiver reads what is left, then none.
    sender_closed: Bool = False
    # The receiving end closed: sends fail.
    receiver_closed: Bool = False
    # Tokens of tasks waiting on this lane, for a value or for room. A cloned end can have several.
    waiting: List[Int] = []

impl Lane[T]:
    # How many values wait to be received.
    def length() -> Int:
        return self.front.length() + self.back.length()

    # Takes the oldest value.
    var def pop() -> Optional[T]:
        if self.front.is_empty():
            let count = self.back.length()
            for index in range(0, count):
                if let value = self.back.pop():
                    self.front.append(value)

        return self.front.pop()

    # Drops every unread value.
    var def clear() -> Unit:
        self.front = List[T]()
        self.back = List[T]()

    # Wakes every task waiting on this lane; each looks again at what it waits for.
    var def wake() -> Unit:
        for token in self.waiting:
            msrt_channel_post(token)
        self.waiting = List[Int]()

# Closes the end that sends on `outgoing` and receives on `incoming`, waking whoever waits on either.
def close_end[A, B](outgoing: Shared[Lane[A]], incoming: Shared[Lane[B]]) -> Unit:
    with var sending = lock(outgoing):
        sending.value.sender_closed = True
        sending.value.wake()

    with var receiving = lock(incoming):
        receiving.value.receiver_closed = True
        receiving.value.clear()
        receiving.value.wake()

# One end of a channel between tasks on the runtime thread. Values move from one end to the other;
# a task that must wait parks until the other end posts its token.
type TaskTransport[In, Out]:
    # Values this end sends.
    outgoing: Shared[Lane[In]]
    # Values this end receives.
    incoming: Shared[Lane[Out]]

impl TaskTransport[In, Out]:
    # Waits until `outgoing` has room. Nothing runs between this returning and the caller's send.
    def wait_for_room() -> Result[Unit, ChannelError]:
        while True:
            var token = 0

            with var lane = lock(self.outgoing):
                if lane.value.sender_closed or lane.value.receiver_closed:
                    return error(ChannelError.Closed)
                if lane.value.length() < room():
                    return ok(())

                token = msrt_channel_token()
                lane.value.waiting.append(token)

            msrt_channel_park(token)

        return ok(())

impl Transport[In, Out] for TaskTransport[In, Out]:
    var def send(value: In) -> Result[Unit, ChannelError]:
        try self.wait_for_room()

        with var lane = lock(self.outgoing):
            lane.value.back.append(value)
            lane.value.wake()

        return ok(())

    var def receive() -> Result[Optional[Out], ChannelError]:
        while True:
            var token = 0

            with var lane = lock(self.incoming):
                if lane.value.receiver_closed:
                    return error(ChannelError.Closed)

                if let value = lane.value.pop():
                    lane.value.wake()
                    return ok(some(value))

                if lane.value.sender_closed:
                    return ok(none)

                token = msrt_channel_token()
                lane.value.waiting.append(token)

            msrt_channel_park(token)

        return ok(none)

    var def close() -> Unit:
        close_end(self.outgoing, self.incoming)

impl Closeable for TaskTransport[In, Out]:
    # Closes this end. Safe to call again.
    var def close() -> Unit:
        close_end(self.outgoing, self.incoming)

# The body of a task: runs `entry` on the task's end of its channel and stores its one result in
# `slot`. The end closes when the task ends, however it ends.
def run[T, In, Out](
    entry: Callable[[Channel[Out, In]], T],
    up: Shared[Lane[Out]],
    down: Shared[Lane[In]],
    slot: Shared[List[T]]
) -> Unit:
    with let end = TaskTransport[Out, In](outgoing: up, incoming: down):
        msrt_scope_started()

        let value = entry(
            Channel[Out, In](
                transport: TaskTransport[Out, In](
                    outgoing: up, incoming: down
                )
            )
        )
        with var held = lock(slot):
            held.value.append(value)

# The group's end of a task channel.
def group_end[In, Out](
    down: Shared[Lane[In]],
    up: Shared[Lane[Out]]
) -> Channel[In, Out]:
    return Channel[In, Out](
        transport: TaskTransport[In, Out](outgoing: down, incoming: up)
    )

# What a group keeps of a task until it is collected: enough to wait for it and close its channel.
export type Entry[T, In, Out]:
    # Internal state: the runtime handle of the task.
    handle: Int
    # Internal state: empty until the task returns, then its one result.
    values: Shared[List[T]]
    # Internal state: the group's end of the task's channel.
    channel: Channel[In, Out]

# Drops the entry of the collected task `handle`, so the group holds nothing for it.
def forget[T, In, Out](
    registry: Shared[Map[Int, Entry[T, In, Out]]],
    handle: Int
) -> Unit:
    with var entries = lock(registry):
        entries.value.remove(handle)

# Waits for the task `handle` of `scope` and takes its result from `values`. The task is collected
# even when it has no result, so the runtime and the group let go of it.
def collect[T](scope: Int, handle: Int, values: Shared[List[T]]) -> Result[T, TaskError]:
    try outcome(msrt_scope_join(scope, handle, 0))
    with var finished = lock(values):
        if let value = finished.value.pop():
            return ok(value)
    panic("Task: the result was already taken")

# A started task that returns a `T`, with the group's end of its channel.
export type Task[T, In = Unit, Out = Unit]:
    # Internal state: the runtime scope of the task.
    scope: Int
    # Internal state: the runtime handle of the task.
    handle: Int
    # Internal state: the group's uncollected tasks by handle, in start order.
    registry: Shared[Map[Int, Entry[T, In, Out]]]
    # Internal state: empty until the task returns, then its one result.
    values: Shared[List[T]]
    # The group's end of the task's channel: sends `In` to the task and receives the `Out` it sends.
    channel: Channel[In, Out]

impl Task[T, In, Out]:
    # Waits for the task and returns its result, or why it has none. Takes the result, so call it once.
    def result() -> Result[T, TaskError]:
        let collected = collect(self.scope, self.handle, self.values)
        forget(self.registry, self.handle)
        return collected

# A scope that owns the tasks started in it. Every task returns a `T` (use `Unit` for effect-only work).
# Each task has a two-way channel to the group: it sends `Out` values and receives `In` values, both `Unit` unless given.
# Open a group with `with`: leaving the block cancels tasks that are still running and waits for all of them.
# Call `results`, `wait` or a task's `result` before the block ends to keep the work.
# Collecting a task (`result`, or `results`) makes the group forget it, so a long-lived group holds only
# tasks that are running or uncollected.
# `timeout` limits the whole group, counted from its creation; `spawn` can set a shorter limit for one task.
# A task that passes its limit is cancelled and has the result `TimedOut`. There is no limit unless one is given. A cancelled task releases the values its functions own.
# Tasks run on the one runtime thread and switch only when one waits (`result`, `wait`, a channel, sleeping, I/O).
# A fault in a task ends the program, unless `contain_faults` is set: then the task ends with the result `Faulted(report)`, its siblings keep running, and values its frames owned are not released. A task owns the values its closure captures; return results instead of sharing them.
export type TaskGroup[T, In = Unit, Out = Unit]:
    # Limit for every task started in the group, counted from the group's creation; none for no limit.
    timeout: Optional[Duration] = none
    # Whether a fault in a task ends only that task (`Faulted`) instead of the program. A fault never collected is dropped by `close`.
    contain_faults: Bool = False
    # Internal state: the runtime scope that owns the tasks, set to contain faults when asked.
    scope: Int = new_scope(contain_faults)
    # Internal state: the uncollected tasks in start order, changed through the shared handle so the group works as a `with` binding.
    tasks: Shared[Map[Int, Entry[T, In, Out]]] = share(Map[Int, Entry[T, In, Out]]())

impl TaskGroup[T, In, Out]:
    # Starts `entry` as a task and returns its handle. The task gets its end of a new channel, and the
    # handle's `channel` is the group's end. The task's end closes when `entry` returns.
    # The task first runs when the caller waits.
    # `timeout` limits this task; the group's own limit still applies if it ends sooner.
    def spawn(
        entry: Callable[[Channel[Out, In]], T],
        timeout: Optional[Duration] = none
    ) -> Task[T, In, Out]:
        let down: Shared[Lane[In]] = share(Lane[In]())
        let up: Shared[Lane[Out]] = share(Lane[Out]())
        let values: Shared[List[T]] = share([])
        let task_up = up
        let task_down = down
        let slot = values
        let handle = msrt_scope_spawn(
            self.scope, lambda: run(entry, task_up, task_down, slot), nanos(timeout),
            nanos(self.timeout)
        )

        if handle < 0:
            # The group is closed, so the task never runs.
            close_end(down, up)
            close_end(up, down)

        # The group keeps a second handle on its end, so closing the group closes it.
        with var started = lock(self.tasks):
            started.value[handle] = Entry(handle, values, group_end(down, up))
        return Task(self.scope, handle, self.tasks, values, group_end(down, up))

    # Waits for every uncollected task and returns their results in start order, or the first task's error.
    # Tasks already collected with `result` are not included; the ones returned are collected.
    def results() -> Result[List[T], TaskError]:
        if msrt_scope_wait(self.scope) == 3:
            return error(TaskError.Closed)

        var values = List[T]()

        for handle in self.tasks.get().keys():
            if let next = self.tasks.get().get(handle):
                let value = collect(self.scope, handle, next.values)
                forget(self.tasks, handle)
                values.append(try value)

        return ok(values)

    # Waits for every started task to end. Returns `TimedOut` or `Cancelled` if any task ended without a result.
    def wait() -> Result[Unit, TaskError]:
        return outcome(msrt_scope_wait(self.scope))

impl Closeable for TaskGroup[T, In, Out]:
    # Cancels tasks that have not ended, waits for them, and closes every channel. Safe to call again.
    var def close() -> Unit:
        msrt_scope_close(self.scope)
        with var started = lock(self.tasks):
            for handle in started.value.keys():
                if var entry = started.value.get(handle):
                    entry.channel.close()
