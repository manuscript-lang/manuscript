# Worker threads: code that runs on another OS thread, with its own memory, and talks to its starter
# over a two-way channel.
#
# A worker is started from a named top-level `def` that takes no arguments and returns `Unit`; it
# gets its end of the channel from `worker_channel`. Nothing is shared between the two sides:
# every value sent through the channel is encoded as JSON and decoded on the other side, so the
# message types are the ones `@std/json.ms` can read and write.
#
# ```manuscript
# def double_all() -> Unit:
#     let ch = worker_channel[Int, Int]()
#     while True:
#         if let n = ch.receive().unwrap():
#             ch.send(n * 2)
#         else:
#             return
# ```
from "@std/channels.ms" import Channel, ChannelError, Transport
from "@std/collections.ms" import range
from "@std/core.ms" import Closeable
from "@std/json.ms" import parse, stringify
from "@std/shared.ms" import Shared, share

extern def msrt_pipe_new() -> Int

extern def msrt_pipe_peer(end: Int) -> Int

extern def msrt_pipe_send(end: Int, message: String) -> Int

extern def msrt_pipe_receive(end: Int) -> Result[String, PipeEnd]

extern def msrt_pipe_close(end: Int) -> Unit

extern def msrt_worker_start(entry: Callable[[], Unit], end: Int) -> Int

extern def msrt_worker_end() -> Int

extern def msrt_worker_cancel(handle: Int) -> Unit

extern def msrt_worker_wait(handle: Int) -> String

# Why a read from the pipe gave no message. The native side numbers these cases from 1 (1 + declaration index).
type PipeEnd:
    # This end is closed.
    case Closed
    # The other end closed and every message was read.
    case Ended

impl Error for PipeEnd:
    # Returns `pipe: closed` or `pipe: ended`.
    def message() -> String:
        match self:
            case Closed: return "pipe: closed"
            case Ended: return "pipe: ended"

# Why a worker did not return normally.
export type WorkerError:
    # The worker stopped a fault; the report is its message and stack.
    case Faulted(
        # The fault report from the worker.
        report: String
    )
    # The worker was cancelled before it returned.
    case Cancelled
    # The worker could not start: too many are running, or the system refused a thread.
    case NotStarted

impl Error for WorkerError:
    # Returns `worker: faulted: <report>`, `worker: cancelled` or `worker: not started`.
    def message() -> String:
        match self:
            case Faulted(report): return "worker: faulted: " + report
            case Cancelled: return "worker: cancelled"
            case NotStarted: return "worker: not started"

# One end of the in-memory pipe between a group and a worker.
type WorkerTransport[In, Out]:
    # The pipe end this transport sends and receives on.
    end: Int

# What a failed read means for the channel: the other end finishing is the normal end of input.
def stopped[Out](why: PipeEnd) -> Result[Optional[Out], ChannelError]:
    match why:
        case Ended: return ok(none)
        case Closed: return error(ChannelError.Closed)

impl WorkerTransport[In, Out]:
    # Decodes a message, or says it could not be.
    def decode(text: String) -> Result[Optional[Out], ChannelError]:
        match parse[Out](text):
            case ok(value): return ok(some(value))
            case error(why): return error(
                ChannelError.Broken(
                    "a message could not be decoded: " + why.message()
                )
            )

impl Transport[In, Out] for WorkerTransport[In, Out]:
    var def send(value: In) -> Result[Unit, ChannelError]:
        match stringify(value):
            case error(why): return error(
                ChannelError.Broken(
                    "a message could not be encoded: " + why.message()
                )
            )
            case ok(text):
                if msrt_pipe_send(self.end, text) != 0:
                    return error(ChannelError.Closed)

                return ok(())

    var def receive() -> Result[Optional[Out], ChannelError]:
        match msrt_pipe_receive(self.end):
            case ok(text): return self.decode(text)
            case error(why): return stopped(why)

    var def close() -> Unit:
        msrt_pipe_close(self.end)

# Returns the worker's end of its channel. The worker sends `Send` values and receives `Receive`
# values, so a group of `WorkerGroup[Receive, Send]` started it. Call it on a worker's thread.
export def worker_channel[Send, Receive]() -> Channel[Send, Receive]:
    return Channel[Send, Receive](
        transport: WorkerTransport[Send, Receive](end: msrt_worker_end())
    )

# A started worker, with the group's end of its channel.
export type Worker[In, Out]:
    # Internal state: the runtime handle of the worker.
    handle: Int
    # The group's end of the worker's channel: sends `In` to the worker and receives the `Out` it sends.
    channel: Channel[In, Out]
    # Internal state: empty until the worker was collected, then how it ended.
    ended: Shared[List[Result[Unit, WorkerError]]]

impl Worker[In, Out]:
    # Closes the group's end of the channel, waits for the worker to end, and returns how it ended.
    # A worker that is still reading ends once its input is closed; call `cancel` first to stop one that is not.
    # Safe to call again: later calls return the same outcome.
    var def join() -> Result[Unit, WorkerError]:
        var held = self.ended.take()

        if held.length() > 0:
            let first = held[0]
            self.ended.put(held)
            return first.clone()

        # Put the payload back while waiting: a stop request unwinds the wait, and the cleanup joins again.
        self.ended.put(held)
        self.channel.close()

        let report = msrt_worker_wait(self.handle)
        let outcome = outcome_of(report)
        var again = self.ended.take()
        again.append(outcome.clone())
        self.ended.put(again)
        return outcome

    # Asks the worker to stop: its next wait or check for cancellation unwinds it.
    def cancel() -> Unit:
        msrt_worker_cancel(self.handle)

# How a worker ended, from the status digit and report the runtime returns.
def outcome_of(report: String) -> Result[Unit, WorkerError]:
    if report.starts_with("1"):
        return error(WorkerError.Faulted(report.slice(1, report.length()).get("")))
    if report.starts_with("2"):
        return error(WorkerError.Cancelled)

    return ok(())

# A group of workers. Every worker's channel sends `In` to it and receives `Out` from it.
# Open a group with `with`: leaving the block cancels workers that are still running and waits for them.
# Manuscript faults caught by the worker runtime are reported through `join` as `Faulted`.
# Worker threads are not a process-crash isolation boundary.
export type WorkerGroup[In = Unit, Out = Unit]:
    # Internal state: the workers in start order, changed through the shared handle so the group works as a `with` binding.
    workers: Shared[List[Worker[In, Out]]] = share([])

impl WorkerGroup[In, Out]:
    # Starts `entry`, a named top-level `def`, on a new thread and returns its handle. The handle's
    # `channel` is this side of the worker's two-way channel; the worker takes the other from
    # `worker_channel`.
    def spawn(entry: Callable[[], Unit]) -> Result[Worker[In, Out], WorkerError]:
        let near = msrt_pipe_new()
        if near == 0:
            return error(WorkerError.NotStarted)

        let far = msrt_pipe_peer(near)
        let handle = msrt_worker_start(entry, far)

        if handle == 0:
            msrt_pipe_close(near)
            msrt_pipe_close(far)
            return error(WorkerError.NotStarted)

        let channel = Channel[In, Out](transport: WorkerTransport[In, Out](end: near))
        let ended: Shared[List[Result[Unit, WorkerError]]] = share([])
        let worker = Worker(handle, channel, ended)
        var started = self.workers.take()
        started.append(worker.clone())
        self.workers.put(started)
        return ok(worker)

impl Closeable for WorkerGroup[In, Out]:
    # Cancels workers that have not ended, closes their channels, and waits for them. Safe to call again.
    var def close() -> Unit:
        var started = self.workers.take()

        for index in range(0, started.length()):
            started[index].cancel()
            started[index].join()

        self.workers.put(started)
