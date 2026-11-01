import Channel, ChannelError, Transport from "@std/io/channels.ms"
import Closeable, panic from "@std/core.ms"
import Shared from "@std/concurrency/shared.ms"
import Duration from "@std/os/time.ms"
import msrt_scope_new, msrt_scope_spawn, msrt_scope_contain, msrt_scope_fault_message, msrt_scope_started, msrt_task_cancel_requested, msrt_scope_join, msrt_scope_wait, msrt_scope_close, msrt_channel_token, msrt_channel_park, msrt_channel_post, msrt_obj_share from "@std/internal/tasks.ms"

# Internal lifetime tracker for the group's channels; it never owns its channel leases.
export extern type TaskChannels

# Internal reference-counted lease; its final holder removes it from the group's tracker.
extern type TaskChannelLease

impl TaskChannelLease:
    # Another holder of the same lease: the channel closes when the last holder is released.
    fn clone() TaskChannelLease:
        return msrt_obj_share(self)

extern fn msrt_channel_group_new() TaskChannels

extern fn msrt_channel_group_add(group: TaskChannels, close: fn() Unit) TaskChannelLease

extern fn msrt_channel_group_close(group: TaskChannels) Unit

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
        report: String
    )

impl Error for TaskError:
    # Returns the fixed diagnostic `task: <reason>`.
    fn message() String:
        match self:
            TimedOut: return "task: timed out"
            Cancelled: return "task: cancelled"
            Closed: return "task: closed"
            Faulted(report): return "task: fault: " + report

# Whether the running task was cancelled: its group was closed, its timeout passed, or the program was asked to stop.
# A plain query: it neither waits nor unwinds, so a task can poll it between steps and finish early.
# It stays true inside cleanups (scope-end closes), where a cancelled task should do minimal work.
export fn cancelled() Bool:
    return msrt_task_cancel_requested() != 0

# Maps a runtime outcome (0 returned, 1 timed out, 2 cancelled, 3 closed or collected, 4 faulted) to a result.
fn outcome(code: Int) Unit!TaskError:
    if code == 1:
        return error(TaskError.TimedOut)
    if code == 2:
        return error(TaskError.Cancelled)
    if code == 3:
        return error(TaskError.Closed)
    if code == 4:
        return error(TaskError.Faulted(msrt_scope_fault_message()))

    return ok(unit)

# A new runtime scope, one that contains task faults when `contain` is set.
fn new_scope(contain: Bool) Int:
    let scope = msrt_scope_new()
    if contain:
        msrt_scope_contain(scope)
    return scope

# A limit in nanoseconds, or -1 for none.
fn nanos(limit: Duration?) Int:
    if let own = limit:
        if own.to_nanoseconds() < 0:
            panic("TaskGroup: a timeout must not be negative")
        return own.to_nanoseconds()

    return -1

# How many unread values one direction of a task channel holds before a send waits.
fn room() Int:
    return 16

# One direction of a task channel: the values sent and not yet received, and who waits on them.
type Lane[T]:
    # Values to receive next, newest first.
    front: List[T] = []
    # Values sent after `front` was filled, oldest first.
    back: List[T] = []
    # The sending end closed: the receiver reads what is left, then none.
    sender_closed: Bool = false
    # The receiving end closed: sends fail.
    receiver_closed: Bool = false
    # Tokens of tasks waiting on this lane, for a value or for room. A cloned end can have several.
    waiting: List[Int] = []

impl Lane[T]:
    # How many values wait to be received.
    fn length() Int:
        return self.front.length() + self.back.length()

    # Takes the oldest value.
    var fn pop() T?:
        if self.front.is_empty():
            let count = self.back.length()
            for index in 0..count:
                if let value = self.back.pop():
                    self.front.append(value)

        return self.front.pop()

    # Drops every unread value.
    var fn clear() Unit:
        self.front = List[T]()
        self.back = List[T]()

    # Wakes every task waiting on this lane; each looks again at what it waits for.
    var fn wake() Unit:
        for token in self.waiting:
            msrt_channel_post(token)
        self.waiting = List[Int]()

    # Forgets the wait of `token`, which a cancelled task no longer needs.
    var fn forget_wait(token: Int) Unit:
        for index in 0..self.waiting.length():
            if self.waiting[index] == token:
                self.waiting.remove(index)
                break

        if self.waiting.is_empty():
            self.waiting = List[Int]()

# Closes the end that sends on `outgoing` and receives on `incoming`, waking whoever waits on either.
fn close_end[A, B](var outgoing: Lane[A], var incoming: Lane[B]) Unit:
    outgoing.sender_closed = true
    outgoing.wake()
    incoming.receiver_closed = true
    incoming.clear()
    incoming.wake()

# Removes this wait's token on every exit without disturbing other tasks on the lane.
type WaitTicket[T]:
    # The lane holding this wait's token.
    lane: Shared[Lane[T]]
    # The token that this wait registered.
    token: Int

impl Closeable for WaitTicket[T]:
    # A normal wake already cleared the entry. Cancellation must remove it here instead.
    var fn close() Unit!:
        self.lane.forget_wait(self.token)
        return ok(unit)

# One end of a channel between tasks on the runtime thread. Values move from one end to the other;
# a task that must wait parks until the other end posts its token.
type TaskTransport[In, Out]:
    # Values this end sends.
    outgoing: Shared[Lane[In]]
    # Values this end receives.
    incoming: Shared[Lane[Out]]
    # Only group ends hold a lease; copies share its lifetime without the group retaining them.
    lifetime: TaskChannelLease?

# What one look at `outgoing` found: room to send, a closed lane, or the token to park on.
type Reserved:
    case Ready
    case Shut
    case Wait(token: Int)

impl Lane[T]:
    # Looks for room to send, or registers a wait.
    var fn claim_room() Reserved:
        if self.sender_closed or self.receiver_closed:
            return Reserved.Shut
        if self.length() < room():
            return Reserved.Ready

        let token = msrt_channel_token()
        self.waiting.append(token)
        return Reserved.Wait(token)

impl TaskTransport[In, Out]:
    # Waits until `outgoing` has room. Nothing runs between this returning and the caller's send.
    var fn wait_for_room() Unit!ChannelError:
        while true:
            match self.outgoing.claim_room():
                Reserved.Ready:
                    return ok(unit)
                Reserved.Shut:
                    return error(ChannelError.Closed)
                Reserved.Wait(token):
                    let ticket = WaitTicket[In](lane: self.outgoing, token: token)
                    msrt_channel_park(token)

        return ok(unit)

impl Transport[In, Out] for TaskTransport[In, Out]:
    var fn send(value: In) Unit!ChannelError:
        try self.wait_for_room()
        self.outgoing.back.append(value)
        self.outgoing.wake()
        return ok(unit)

    var fn receive() Out?!ChannelError:
        while true:
            if self.incoming.receiver_closed:
                return error(ChannelError.Closed)

            if let value = self.incoming.pop():
                self.incoming.wake()
                return ok(value)

            if self.incoming.sender_closed:
                return ok(none)

            let token = msrt_channel_token()
            self.incoming.waiting.append(token)

            let ticket = WaitTicket[Out](lane: self.incoming, token: token)
            msrt_channel_park(token)

        return ok(none)

    var fn close() Unit:
        close_end(var self.outgoing, var self.incoming)

impl Closeable for TaskTransport[In, Out]:
    # Closes this end. Safe to call again.
    var fn close() Unit!:
        close_end(var self.outgoing, var self.incoming)
        return ok(unit)

# The body of a task: runs `entry` on the task's end of its channel and returns its one result. The
# end closes when the task ends, however it ends.
fn run[T, In: Clonable, Out: Clonable](
    entry: fn(var Channel[Out, In]) T,
    up: Shared[Lane[Out]],
    down: Shared[Lane[In]]
) T:
    let end = TaskTransport[Out, In](outgoing: up, incoming: down)
    msrt_scope_started()

    var channel = Channel[Out, In](
        transport: TaskTransport[Out, In](outgoing: up, incoming: down)
    )
    return entry(var channel)

# The group's end of a task channel.
fn group_end[In: Clonable, Out: Clonable](
    down: Shared[Lane[In]],
    up: Shared[Lane[Out]],
    lifetime: TaskChannelLease
) Channel[In, Out]:
    return Channel[In, Out](
        transport: TaskTransport[In, Out](
            outgoing: down, incoming: up, lifetime: lifetime
        )
    )

# What a group keeps of a task until it is collected: enough to wait for it and close its channel.
export type Entry[T, In: Clonable, Out: Clonable]:
    # Internal state: the runtime handle of the task.
    handle: Int
    # Internal state: empty until the task returns, then its one result.
    values: Shared[List[T]]
    # Internal state: the group's end of the task's channel.
    channel: Channel[In, Out]

impl Entry[T, In, Out]:
    # Waits for the task in `scope` and takes its result. The task is collected even when it has no
    # result, so the runtime lets go of it.
    var fn collect(scope: Int) T!TaskError:
        try outcome(msrt_scope_join(scope, self.handle, 0))
        return ok(take_result(var self.values))

# Takes the one result a finished task left in `values`.
fn take_result[T](var values: List[T]) T:
    if let value = values.pop():
        return value

    panic("Task: the result was already taken")

# A started task that returns a `T`, with the group's end of its channel.
export type Task[T, In: Clonable = Unit, Out: Clonable = Unit]:
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
    var fn result() T!TaskError:
        let ended = outcome(msrt_scope_join(self.scope, self.handle, 0))
        self.registry.remove(self.handle)

        let _joined = try ended
        return ok(take_result(var self.values))

# A scope that owns the tasks started in it. Every task returns a `T` (use `Unit` for effect-only work).
# Each task has a two-way channel to the group: it sends `Out` values and receives `In` values, both `Unit` unless given.
# Bind a group to a local: when its scope ends it cancels tasks that are still running and waits for all of them.
# Call `results`, `wait` or a task's `result` before the block ends to keep the work.
# Collecting a task (`result`, or `results`) makes the group forget it, so a long-lived group holds only
# tasks that are running or uncollected.
# Retained channels may drain buffered values after collection; group close closes them too and drops unread values.
# `timeout` limits the whole group, counted from its creation; `spawn` can set a shorter limit for one task.
# A task that passes its limit is cancelled and has the result `TimedOut`. There is no limit unless one is given. A cancelled task releases the values its functions own.
# Tasks run on the one runtime thread and switch only when one waits (`result`, `wait`, a channel, sleeping, I/O).
# A fault in a task ends the program, unless `contain_faults` is set: then the task ends with the result `Faulted(report)`, its siblings keep running, and values its frames owned are not released. A task owns the values its closure captures; return results instead of sharing them.
export type TaskGroup[T, In: Clonable = Unit, Out: Clonable = Unit]:
    # Limit for every task started in the group, counted from the group's creation; none for no limit.
    timeout: Duration?
    # Whether a fault in a task ends only that task (`Faulted`) instead of the program. A fault never collected is dropped by `close`.
    contain_faults: Bool = false
    # Internal state: the runtime scope that owns the tasks, set to contain faults when asked.
    scope: Int = new_scope(contain_faults)
    # Internal state: the uncollected tasks in start order, changed through the shared handle so the group closes when its scope ends.
    tasks: Shared[Map[Int, Entry[T, In, Out]]] = Shared(Map[Int, Entry[T, In, Out]]())
    # Internal state: weak tracking of handed-out channels, including collected tasks.
    channels: TaskChannels = msrt_channel_group_new()

impl TaskGroup[T, In, Out]:
    # Starts `entry` as a task and returns its handle. The task gets its end of a new channel, and the
    # handle's `channel` is the group's end. The task's end closes when `entry` returns.
    # The task first runs when the caller waits.
    # `timeout` limits this task; the group's own limit still applies if it ends sooner.
    var fn spawn(entry: fn(var Channel[Out, In]) T, timeout: Duration?) Task[T, In, Out]:
        var down = Shared(Lane[In]())
        var up = Shared(Lane[Out]())
        let values = Shared(List[T]())
        let task_up = up
        let task_down = down
        var slot = values
        let handle = msrt_scope_spawn(
            self.scope, fn: slot.append(run(entry, task_up, task_down)), nanos(timeout),
            nanos(self.timeout)
        )

        if handle < 0:
            # The group is closed, so the task never runs.
            close_end(var down, var up)
            close_end(var up, var down)

        var close_down = down
        var close_up = up
        let lifetime = msrt_channel_group_add(
            self.channels, fn: close_end(var close_down, var close_up)
        )

        # The group keeps a second handle on its end, so closing the group closes it.
        self.tasks[handle] = Entry(
            handle, values, group_end(down, up, lifetime.clone())
        )
        return Task(
            self.scope, handle, self.tasks, values, group_end(down, up, lifetime)
        )

    # Waits for every uncollected task and returns their results in start order, or the first task's error.
    # Tasks already collected with `result` are not included; the ones returned are collected.
    var fn results() List[T]!TaskError:
        if msrt_scope_wait(self.scope) == 3:
            return error(TaskError.Closed)

        var values = List[T]()

        for handle in self.tasks.keys():
            if let found = self.tasks.get(handle):
                var next = found
                let value = next.collect(self.scope)
                self.tasks.remove(handle)
                values.append(try value)

        return ok(values)

    # Waits for every started task to end. Returns `TimedOut`, `Cancelled`, `Closed` or `Faulted` if any task ended without a result.
    fn wait() Unit!TaskError:
        return outcome(msrt_scope_wait(self.scope))

impl Closeable for TaskGroup[T, In, Out]:
    # Cancels tasks that have not ended, waits for them, and closes every channel. Safe to call again.
    var fn close() Unit!:
        msrt_scope_close(self.scope)
        msrt_channel_group_close(self.channels)
        close_channels(var self.tasks)
        return ok(unit)

# Closes the group's end of every task channel in `tasks`.
fn close_channels[T, In: Clonable, Out: Clonable](
    var tasks: Map[Int, Entry[T, In, Out]]
) Unit:
    for handle in tasks.keys():
        if var entry = tasks[handle]?:
            entry.channel.close()
