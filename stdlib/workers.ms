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
#     var ch = worker_channel[Int, Int]()
#     while True:
#         let received = ch.receive().get(none)
#         if received.is_none(): return
#         let _ = ch.send(received.get() * 2)
# ```
import Bytes from "@std/bytes.ms"
import {Channel, ChannelError, Transport} from "@std/channels.ms"
import Closeable from "@std/core.ms"
import {parse, stringify} from "@std/json.ms"
import {Shared, share} from "@std/shared.ms"
import lock from "@std/sync.ms"

extern fn msrt_pipe_new() Int

extern fn msrt_pipe_peer(end: Int) Int

extern fn msrt_pipe_send(end: Int, message: String) Int

extern fn msrt_pipe_receive(end: Int) Result[String, PipeEnd]

extern fn msrt_pipe_send_bytes(end: Int, message: Bytes) Int

extern fn msrt_pipe_receive_bytes(end: Int) Result[Bytes, PipeEnd]

extern fn msrt_pipe_close(end: Int) Unit

extern fn msrt_worker_start(entry: fn() Unit, end: Int) Int

extern fn msrt_worker_end() Int

extern fn msrt_worker_cancel(handle: Int) Unit

extern fn msrt_worker_wait(handle: Int) String

# Why a read from the pipe gave no message. The native side numbers these cases from 1 (1 + declaration index).
type PipeEnd:
    # This end is closed.
    case Closed
    # The other end closed and every message was read.
    case Ended

impl Error for PipeEnd:
    # Returns `pipe: closed` or `pipe: ended`.
    fn message() String:
        match self:
            Closed: return "pipe: closed"
            Ended: return "pipe: ended"

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
    fn message() String:
        match self:
            Faulted(report): return "worker: faulted: " + report
            Cancelled: return "worker: cancelled"
            NotStarted: return "worker: not started"

# One end of the in-memory pipe between a group and a worker.
type WorkerTransport[In, Out]:
    # The pipe end this transport sends and receives on.
    end: Int

# What a failed read means for the channel: the other end finishing is the normal end of input.
fn stopped[Out](why: PipeEnd) Result[Optional[Out], ChannelError]:
    match why:
        Ended: return ok(none)
        Closed: return error(ChannelError.Closed)

impl WorkerTransport[In, Out]:
    # Decodes a message, or says it could not be.
    fn decode(text: String) Result[Optional[Out], ChannelError]:
        match parse[Out](text):
            ok(value): return ok(value)
            error(why): return error(
                ChannelError.Broken(
                    "a message could not be decoded: " + why.message()
                )
            )

impl Transport[In, Out] for WorkerTransport[In, Out]:
    var fn send(value: In) Result[Unit, ChannelError]:
        match stringify(value):
            error(why): return error(
                ChannelError.Broken(
                    "a message could not be encoded: " + why.message()
                )
            )
            ok(text):
                if msrt_pipe_send(self.end, text) != 0:
                    return error(ChannelError.Closed)

                return ok(unit)

    var fn receive() Result[Optional[Out], ChannelError]:
        match msrt_pipe_receive(self.end):
            ok(text): return self.decode(text)
            error(why): return stopped(why)

    var fn close() Unit:
        msrt_pipe_close(self.end)

# Returns the worker's end of its channel. The worker sends `Send` values and receives `Receive`
# values, so a group of `WorkerGroup[Receive, Send]` started it. Call it on a worker's thread.
export fn worker_channel[Send, Receive]() Channel[Send, Receive]:
    return Channel[Send, Receive](
        transport: WorkerTransport[Send, Receive](end: msrt_worker_end())
    )

# One end of a worker's pipe carrying raw `Bytes`: each send is copied once into the other side's
# memory, with no JSON encoding. It shares the pipe end with the JSON transport on the same side.
type WorkerBytesTransport:
    # The pipe end this transport sends and receives on.
    end: Int

impl Transport[Bytes, Bytes] for WorkerBytesTransport:
    var fn send(value: Bytes) Result[Unit, ChannelError]:
        if msrt_pipe_send_bytes(self.end, value) != 0:
            return error(ChannelError.Closed)

        return ok(unit)

    var fn receive() Result[Optional[Bytes], ChannelError]:
        match msrt_pipe_receive_bytes(self.end):
            ok(data): return ok(data)
            error(why): return stopped(why)

    var fn close() Unit:
        msrt_pipe_close(self.end)

# A `Channel[Bytes, Bytes]` over the pipe end `end`, sending each message as raw bytes.
fn bytes_channel(end: Int) Channel[Bytes, Bytes]:
    return Channel[Bytes, Bytes](transport: WorkerBytesTransport(end: end))

# Returns the worker's end of its pipe as a `Channel[Bytes, Bytes]`, for large payloads that
# should not be encoded as JSON. It shares the pipe, and so the order and the 16-message room,
# with the channel from `worker_channel`: read each message with the kind that was sent, and
# closing either closes the shared end. Call it on a worker's thread.
export fn worker_bytes() Channel[Bytes, Bytes]:
    return bytes_channel(msrt_worker_end())

# A started worker, with the group's end of its channel.
export type Worker[In, Out]:
    # Internal state: the runtime handle of the worker.
    handle: Int
    # The group's end of the worker's channel: sends `In` to the worker and receives the `Out` it sends.
    channel: Channel[In, Out]
    # Internal state: the group's pipe end, shared with `channel`.
    end: Int
    # Internal state: empty until the worker was collected, then how it ended.
    ended: Shared[List[Result[Unit, WorkerError]]]

impl Worker[In, Out]:
    # Closes the group's end of the channel, waits for the worker to end, and returns how it ended.
    # A worker that is still reading ends once its input is closed; call `cancel` first to stop one that is not.
    # Safe to call again: later calls return the same outcome.
    var fn wait() Result[Unit, WorkerError]:
        with var held = lock(self.ended):
            if held.value.length() > 0:
                return held.value[0].clone()

            # A stop request unwinds the wait and the guard puts the payload back, so the cleanup joins again.
            self.channel.close()

            let report = msrt_worker_wait(self.handle)
            let outcome = outcome_of(report)
            held.value.append(outcome.clone())
            return outcome

    # Returns the group's end of the pipe as a `Channel[Bytes, Bytes]`, to move large payloads
    # without JSON. It shares the pipe with `channel`, as `worker_bytes` describes.
    fn bytes() Channel[Bytes, Bytes]:
        return bytes_channel(self.end)

    # Asks the worker to stop: its next wait or check for cancellation unwinds it.
    fn cancel() Unit:
        msrt_worker_cancel(self.handle)

# How a worker ended, from the status digit and report the runtime returns.
fn outcome_of(report: String) Result[Unit, WorkerError]:
    if report.starts_with("1"):
        return error(WorkerError.Faulted(report.slice(1, report.length()).get("")))
    if report.starts_with("2"):
        return error(WorkerError.Cancelled)

    return ok(unit)

# A group of workers. Every worker's channel sends `In` to it and receives `Out` from it.
# Open a group with `with`: leaving the block cancels workers that are still running and waits for them.
# Manuscript faults caught by the worker runtime are reported through `wait` as `Faulted`.
# Worker threads are not a process-crash isolation boundary.
export type WorkerGroup[In = Unit, Out = Unit]:
    # Internal state: the workers in start order, changed through the shared handle so the group works as a `with` binding.
    workers: Shared[List[Worker[In, Out]]] = share([])

impl WorkerGroup[In, Out]:
    # Starts `entry`, a named top-level `def`, on a new thread and returns its handle. The handle's
    # `channel` is this side of the worker's two-way channel; the worker takes the other from
    # `worker_channel`.
    fn spawn(entry: fn() Unit) Result[Worker[In, Out], WorkerError]:
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
        let worker = Worker(handle, channel, near, ended)
        with var started = lock(self.workers):
            started.value.append(worker.clone())
        return ok(worker)

impl Closeable for WorkerGroup[In, Out]:
    # Cancels workers that have not ended, closes their channels, and waits for them. Safe to call again.
    var fn close() Unit:
        with var started = lock(self.workers):
            for index in 0..started.value.length():
                started.value[index].cancel()

                let _ = started.value[index].wait()
