# Child processes that run a function of this program and talk to it over a channel.
#
# `ProcessGroup.spawn(entry)` starts this executable again in a new process, at `entry` instead
# of `main`. The entry gets its end of a two-way channel, a `Channel[Out, In]`; the returned
# `Process` holds the other end in its `channel` field. Values cross as JSON, so they are copied,
# and the entry's return value comes back through `Process.result`. Each process is isolated: a
# fault in the child ends only the child, and the parent sees its exit status.
from "@std/bytes.ms" import Bytes, read_integer, write_integer
from "@std/channels.ms" import Channel, ChannelError, Transport
from "@std/collections.ms" import range
from "@std/core.ms" import Closeable
from "@std/io.ms" import ReadStream, WriteStream
from "@std/json.ms" import parse, stringify
from "@std/process.ms" import CommandError, Stdio
from "@std/shared.ms" import Shared, share
from "@std/time.ms" import Duration

# A running child, owned by its `Process`.
export extern type NativeProcess

# One end of a process's IPC pipe.
export extern type NativeLink

extern def msstd_process_fork(
    runner: Callable[[], Unit],
    stdin: Stdio,
    stdout: Stdio,
    stderr: Stdio
) -> Result[NativeProcess, CommandError]

extern def msstd_process_forked_link(process: NativeProcess) -> NativeLink

extern def msstd_process_forked_stdin(process: NativeProcess) -> WriteStream

extern def msstd_process_forked_output(process: NativeProcess, which: Int) -> ReadStream

extern def msstd_process_forked_wait(
    process: NativeProcess,
    timeout_ns: Int
) -> Result[Int, CommandError]

extern def msstd_process_forked_signal(process: NativeProcess, force: Bool) -> Unit

extern def msstd_process_forked_close(process: NativeProcess) -> Unit

extern def msstd_process_ipc_child() -> NativeLink

extern def msstd_process_ipc_read(link: NativeLink, max: Int) -> Bytes

extern def msstd_process_ipc_write(link: NativeLink, data: Bytes) -> Bool

extern def msstd_process_ipc_close(link: NativeLink) -> Unit

# Frame kinds: a message, the end of the sender's messages, and the entry's result.
let MESSAGE = 0
let CLOSE = 1
let RESULT = 2
# The largest frame body, 16 MiB; a larger frame breaks the channel.
let FRAME_LIMIT = 16777216

# Why a process gave no result.
export type ProcessError:
    # The process ended before its entry returned, with this exit status: 70 after a fault, -1
    # when a signal ended it.
    case Exited(
        # The exit status the parent observed: 70 after a fault in the child, -1 after a signal.
        code: Int
    )
    # What the process sent could not be read.
    case Broken(
        # Why the frames could not be read, for example an oversized or non-UTF-8 frame.
        reason: String
    )

impl Error for ProcessError:
    # Returns the fixed diagnostic `process: exited with status <code>` or `process: broken: <reason>`.
    def message() -> String:
        match self:
            case Exited(code): return "process: exited with status " + code.to_string()
            case Broken(reason): return "process: broken: " + reason

# A value inside a frame body, so values with no JSON form of their own, such as `Unit`, cross too.
type Envelope[T]:
    value: T

# One frame read from the pipe.
type Frame:
    kind: Int
    body: String

# Internal state of one end of a process channel: what it has read and seen, shared by its handles.
export type Inbox:
    # Bytes read from the pipe and not yet framed.
    pending: Bytes = "".to_bytes()
    # The other end sent `close` or its result: no more messages come.
    finished: Bool = False
    # The body of the result frame, once read.
    result: Optional[String] = none
    # This end sent `close`.
    closed: Bool = False

def frame(kind: Int, body: String) -> Bytes:
    let data = body.to_bytes()

    match write_integer(data.length(), 4, False, True):
        case ok(size):
            return (
                size
                .concat(
                    write_integer(kind, 1, False, True).get(
                        "".to_bytes()
                    )
                )
                .concat(data)
            )
        case error(_):
            return "".to_bytes()

def encode[T](value: T) -> Result[String, ChannelError]:
    match stringify(Envelope[T](value: value)):
        case ok(text): return ok(text)
        case error(e): return error(
            ChannelError.Broken("cannot encode the value: " + e.message())
        )

def decode[T](body: String) -> Result[T, ChannelError]:
    match parse[Envelope[T]](body):
        case ok(envelope):
            let {value} = envelope
            return ok(value)
        case error(e): return error(
            ChannelError.Broken("cannot decode the value: " + e.message())
        )

# The next whole frame, waiting for more bytes as needed; `none` once the other process closed
# the pipe or is gone.
def next_frame(
    link: NativeLink,
    inbox: Shared[Inbox]
) -> Result[Optional[Frame], ChannelError]:
    while True:
        var state = inbox.take()
        let available = state.pending.length()

        if available >= 5:
            let size = read_integer(state.pending, 0, 4, False, True).get(0)

            if size > FRAME_LIMIT:
                inbox.put(state)
                return error(ChannelError.Broken("a frame is larger than 16 MiB"))

            if available >= 5 + size:
                let kind = state.pending.get(4)
                let body = state.pending.slice(5, 5 + size).get("".to_bytes())
                state.pending = (
                    state
                    .pending
                    .slice(5 + size, available)
                    .get("".to_bytes())
                )
                inbox.put(state)
                if let text = body.decode_utf8():
                    return ok(some(Frame(kind: kind, body: text)))

                return error(ChannelError.Broken("a frame is not UTF-8"))

        inbox.put(state)

        let chunk = msstd_process_ipc_read(link, 65536)
        if chunk.is_empty():
            return ok(none)

        var more = inbox.take()
        more.pending = more.pending.concat(chunk)
        inbox.put(more)

    return ok(none)

# Marks that the other end sent no more messages, keeping the result body if this was it.
def finish(inbox: Shared[Inbox], result: Optional[String]) -> Unit:
    var state = inbox.take()
    state.finished = True
    if result.is_some():
        state.result = result
    inbox.put(state)

# Sends `close` from this end once.
def close_end(link: NativeLink, inbox: Shared[Inbox]) -> Unit:
    var state = inbox.take()
    let first = not state.closed
    state.closed = True
    inbox.put(state)
    if first:
        msstd_process_ipc_write(link, frame(CLOSE, ""))

# One end of a process channel: JSON frames over the IPC pipe.
type ProcessTransport[In, Out]:
    link: NativeLink
    inbox: Shared[Inbox]

impl Transport[In, Out] for ProcessTransport[In, Out]:
    var def send(value: In) -> Result[Unit, ChannelError]:
        let state = self.inbox.get()
        if state.closed or state.finished:
            return error(ChannelError.Closed)

        let text = try encode(value)
        if not msstd_process_ipc_write(self.link, frame(MESSAGE, text)):
            return error(ChannelError.Broken("the other process exited"))

        return ok(())

    var def receive() -> Result[Optional[Out], ChannelError]:
        let state = self.inbox.get()
        if state.closed:
            return error(ChannelError.Closed)
        if state.finished:
            return ok(none)

        while True:
            let next = try next_frame(self.link, self.inbox)
            if next.is_none():
                return error(ChannelError.Broken("the other process exited"))

            let frame = next.get(Frame(kind: -1, body: ""))
            if frame.kind == MESSAGE:
                return ok(some(try decode[Out](frame.body)))

            if frame.kind == CLOSE:
                finish(self.inbox, none)
                return ok(none)

            if frame.kind == RESULT:
                finish(self.inbox, some(frame.body.clone()))
                return ok(none)

            return error(ChannelError.Broken("a frame has an unknown kind"))

        return ok(none)

    var def close() -> Unit:
        close_end(self.link, self.inbox)

# The child's side: runs `entry` on the child's end of the channel, then sends `close` (if the
# entry did not) and the result, and closes the pipe.
def serve[T, In, Out](entry: Callable[[Channel[Out, In]], T]) -> Unit:
    let link = msstd_process_ipc_child()
    let inbox: Shared[Inbox] = share(Inbox())
    let value = entry(
        Channel[Out, In](
            transport: ProcessTransport[Out, In](link: link, inbox: inbox)
        )
    )
    close_end(link, inbox)

    match encode(value):
        case ok(text): msstd_process_ipc_write(link, frame(RESULT, text))
        case error(_): msstd_process_ipc_write(link, frame(RESULT, ""))

    msstd_process_ipc_close(link)

def nanos(limit: Optional[Duration]) -> Int:
    if let d = limit:
        return d.to_nanoseconds()

    return -1

# A child process started by `ProcessGroup.spawn` at an entry returning `T`, with the parent's
# end of its channel.
export type Process[T, In = Unit, Out = Unit]:
    # Internal state: the running child.
    native: NativeProcess
    # Internal state: the parent's end of the IPC pipe.
    link: NativeLink
    # Internal state: what the parent's end has read.
    inbox: Shared[Inbox]
    # The parent's end of the channel: sends `In` to the child and receives the `Out` it sends.
    channel: Channel[In, Out]

impl Process[T, In, Out]:
    # Waits for the entry to return and gives its result, or `Exited` with the status of a child
    # that ended first. Messages the child sent and the parent has not received are dropped.
    def result() -> Result[T, ProcessError]:
        while True:
            if let body = self.inbox.get().result.clone():
                match decode[T](body):
                    case ok(value): return ok(value)
                    case error(e): return error(ProcessError.Broken(e.message()))

            match next_frame(self.link, self.inbox):
                case ok(next):
                    if next.is_none():
                        let code = msstd_process_forked_wait(self.native, -1).get(-1)
                        return error(ProcessError.Exited(code))

                    let frame = next.get(Frame(kind: -1, body: ""))

                    if frame.kind == RESULT:
                        finish(self.inbox, some(frame.body.clone()))
                    elif frame.kind == CLOSE:
                        finish(self.inbox, none)
                case error(e):
                    return error(ProcessError.Broken(e.message()))

        return error(ProcessError.Exited(-1))

    # The child's standard input, when spawned with `stdin: Stdio.Pipe`; otherwise already closed,
    # so writes return `Closed`. Closing it delivers end of input to the child.
    def stdin() -> WriteStream:
        return msstd_process_forked_stdin(self.native)

    # The child's standard output, when spawned with `stdout: Stdio.Pipe`; otherwise already
    # closed. Read it while the child runs: a child whose pipe is full waits until it is read.
    def stdout() -> ReadStream:
        return msstd_process_forked_output(self.native, 1)

    # The child's standard error, when spawned with `stderr: Stdio.Pipe`; otherwise already
    # closed. Read it like `stdout`.
    def stderr() -> ReadStream:
        return msstd_process_forked_output(self.native, 2)

    # Waits for the child to exit and returns its exit status. Returns `Timeout` if `timeout`
    # elapses first, leaving the child running.
    def wait(timeout: Optional[Duration] = none) -> Result[Int, CommandError]:
        return msstd_process_forked_wait(self.native, nanos(timeout))

    # Asks the child to stop (SIGTERM on Unix; Windows ends the whole tree). Does not wait.
    def terminate() -> Unit:
        msstd_process_forked_signal(self.native, False)

    # Kills the child and the processes it started. Does not wait.
    def kill() -> Unit:
        msstd_process_forked_signal(self.native, True)

impl Closeable for Process[T, In, Out]:
    # Closes the channel, then stops and joins the child. Call `result` first to keep it. Safe to call again.
    var def close() -> Unit:
        close_end(self.link, self.inbox)
        msstd_process_forked_close(self.native)

# A scope that owns the child processes started in it. Each runs an entry returning `T` and has a
# two-way channel to the group: the child sends `Out` values and receives `In` values, both
# `Unit` unless given. Open a group with `with`: leaving the block stops every child still running.
# `In`, `Out` and `T` cross as JSON, so use plain data: records, alternatives, lists, maps,
# strings and numbers.
export type ProcessGroup[T, In = Unit, Out = Unit]:
    # Internal state: the processes in start order, changed through the shared handle so the
    # group works as a `with` binding.
    processes: Shared[List[Process[T, In, Out]]] = share([])

impl ProcessGroup[T, In, Out]:
    # Starts this executable again in a new process at `entry`, a top-level `def`, and returns the
    # process. The child gets its end of a new channel, and the process's `channel` is the
    # group's end. `stdin`, `stdout` and `stderr` each choose the parent's own stream (the
    # default), the null device, or a pipe the process's `stdin()`, `stdout()` or `stderr()`
    # reaches.
    def spawn(
        entry: Callable[[Channel[Out, In]], T],
        stdin: Stdio = Stdio.Inherit,
        stdout: Stdio = Stdio.Inherit,
        stderr: Stdio = Stdio.Inherit
    ) -> Result[Process[T, In, Out], CommandError]:
        let runner: Callable[[], Unit] = lambda: serve(entry)
        let native = try msstd_process_fork(runner, stdin, stdout, stderr)
        let link = msstd_process_forked_link(native)
        let inbox: Shared[Inbox] = share(Inbox())
        let started = Process[T, In, Out](
            native: native,
            link: link,
            inbox: inbox,
            channel: Channel[In, Out](
                transport: ProcessTransport[In, Out](
                    link: link, inbox: inbox
                )
            )
        )
        var all = self.processes.take()
        all.append(started)
        self.processes.put(all)
        return ok(
            Process[T, In, Out](
                native: native,
                link: link,
                inbox: inbox,
                channel: Channel[In, Out](
                    transport: ProcessTransport[In, Out](
                        link: link, inbox: inbox
                    )
                )
            )
        )

    # Waits for every process's result in start order, or returns the first error.
    def results() -> Result[List[T], ProcessError]:
        let count = self.processes.get().length()
        var values = List[T]()
        for index in range(0, count):
            values.append(try self.processes.get().get(index).result())
        return ok(values)

impl Closeable for ProcessGroup[T, In, Out]:
    # Closes every process: its channel, then the child, which is stopped and joined. Safe to call again.
    var def close() -> Unit:
        var all = self.processes.take()
        for index in range(0, all.length()):
            all[index].close()
        self.processes.put(all)
