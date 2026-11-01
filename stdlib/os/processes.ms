# Child processes that run a function of this program and talk to it over a channel.
#
# `ProcessGroup.spawn(entry)` starts this executable again in a new process, at `entry` instead
# of `main`. The entry gets its end of a two-way channel, a `Channel[Out, In]`; the returned
# `Process` holds the other end in its `channel` field. Values cross as JSON, so they are copied,
# and the entry's return value comes back through `Process.result`. Each process is isolated: a
# fault in the child ends only the child, and the parent sees its exit status.
import Bytes, BytesBuilder from "@std/bytes.ms"
import Channel, ChannelError, Transport from "@std/io/channels.ms"
import Closeable, Data from "@std/core.ms"
import ReadStream, WriteStream from "@std/io/io.ms"
import parse, stringify from "@std/data/json.ms"
import CommandError, Stdio from "@std/os/process.ms"
import Shared from "@std/concurrency/shared.ms"
import Duration from "@std/os/time.ms"
import msrt_obj_share from "@std/internal/processes.ms"

# A running child, owned by its `Process`.
export extern type NativeProcess

impl NativeProcess:
    # Another holder of the same child handle.
    fn clone() NativeProcess:
        return msrt_obj_share(self)

# One end of a process's IPC pipe.
export extern type NativeLink

impl NativeLink:
    # Another holder of the same pipe end; the pipe closes with `msstd_process_ipc_close`.
    fn clone() NativeLink:
        return msrt_obj_share(self)

extern fn msstd_process_fork(
    runner: fn() Unit,
    stdin: Stdio,
    stdout: Stdio,
    stderr: Stdio
) NativeProcess!CommandError

extern fn msstd_process_forked_link(process: NativeProcess) NativeLink

extern fn msstd_process_forked_stdin(process: NativeProcess) WriteStream

extern fn msstd_process_forked_output(process: NativeProcess, which: Int) ReadStream

extern fn msstd_process_forked_wait(
    process: NativeProcess,
    timeout_ns: Int
) Int!CommandError

extern fn msstd_process_forked_signal(process: NativeProcess, force: Bool) Unit

extern fn msstd_process_forked_close(process: NativeProcess) Unit

extern fn msstd_process_ipc_child() NativeLink

extern fn msstd_process_ipc_read(link: NativeLink, max: Int) Bytes

extern fn msstd_process_ipc_wait_reader(link: NativeLink) Bool

extern fn msstd_process_ipc_write(link: NativeLink, data: Bytes) Bool

extern fn msstd_process_ipc_close(link: NativeLink) Unit

# Frame kinds: a message, the end of the sender's messages, and the entry's result.
let MESSAGE = 0
let CLOSE = 1
let RESULT = 2
# Not a wire kind: `next_frame` waited for another task's read, so the caller re-checks the inbox.
let RETRY = -2
# The largest frame body, 16 MiB; a larger frame breaks the channel.
let FRAME_LIMIT = 16777216

# Why a process gave no result.
export type ProcessError:
    # The process ended before its entry returned, with this exit status: 67 after a fault, -1
    # when a signal ended it.
    case Exited(
        # The exit status the parent observed: 67 after a fault in the child, -1 after a signal.
        code: Int
    )
    # What the process sent could not be read.
    case Broken(
        # Why the frames could not be read, for example an oversized or non-UTF-8 frame.
        reason: String
    )
    # The process could not start; `cause` is the host's reason.
    case NotStarted(
        # Why the host refused to start the child, from the command runner.
        cause: CommandError
    )

impl Error for ProcessError:
    # Returns `process: exited with status <code>`, `process: broken: <reason>` or `process: not started: <cause>`.
    fn message() String:
        match self:
            Exited(code): return "process: exited with status " + code.to_string()
            Broken(reason): return "process: broken: " + reason
            NotStarted(cause): return "process: not started: " + cause.message()

# Wraps a start failure as the group's error.
fn not_started(cause: CommandError) ProcessError:
    return ProcessError.NotStarted(cause)

# A value inside a frame body, so values with no JSON form of their own, such as `Unit`, cross too.
type Envelope[T: Data]:
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
    finished: Bool = false
    # The body of the result frame, once read.
    result: String?
    # This end sent `close`.
    closed: Bool = false

fn frame(kind: Int, body: String) Bytes:
    let data = body.to_bytes()
    var out = BytesBuilder()
    out.append_uint32_le(data.length().to_uint32().get(0))
    out.append(kind.to_uint8().get(0))
    out.append_bytes(data)
    return out.build()

fn encode[T: Data](value: T) String!ChannelError:
    match stringify(Envelope[T](value: value)):
        ok(text): return ok(text)
        error(e): return error(
            ChannelError.Broken("cannot encode the value: " + e.message())
        )

fn decode[T: Data](body: String) T!ChannelError:
    match parse[Envelope[T]](body):
        ok(envelope):
            let {value} = envelope
            return ok(value)
        error(e): return error(
            ChannelError.Broken("cannot decode the value: " + e.message())
        )

# One end's IPC pipe, with what that end has read from it.
type PipeEnd:
    link: NativeLink
    inbox: Shared[Inbox]

impl PipeEnd:
    # The next whole frame, waiting for more bytes as needed; `none` once the other process closed
    # the pipe or is gone. One task reads the pipe at a time: another waits, then returns a `RETRY`
    # frame so its caller sees what the reader recorded (a `RESULT` or `CLOSE`) before reading again.
    fn next_frame() Frame?!ChannelError:
        while true:
            let available = self.inbox.pending.length()

            if available >= 5:
                let size = self.inbox.pending.uint32_le(0).get(0).to_int()
                if size > FRAME_LIMIT:
                    return error(ChannelError.Broken("a frame is larger than 16 MiB"))

                if available >= 5 + size:
                    let kind = self.inbox.pending.get(4).to_int()
                    let body = self.inbox.pending.slice(5, 5 + size).get("".to_bytes())
                    self.inbox.pending = self.inbox.pending.slice(
                        5 + size, available
                    ).get("".to_bytes())
                    if let text = body.decode_utf8():
                        return ok(Frame(kind: kind, body: text))

                    return error(ChannelError.Broken("a frame is not UTF-8"))

            if msstd_process_ipc_wait_reader(self.link):
                return ok(Frame(kind: RETRY, body: ""))

            let chunk = msstd_process_ipc_read(self.link, 65536)
            if chunk.is_empty():
                return ok(none)

            self.inbox.pending = self.inbox.pending.concat(chunk)

        return ok(none)

    # Marks that the other end sent no more messages, keeping the result body if this was it.
    fn finish(result: String?) Unit:
        self.inbox.finished = true
        if result.is_some():
            self.inbox.result = result

    # Marks this end closed and sends `close` once unless `notify` is False (a parent about to kill
    # the child: the write could wait forever on a full pipe the child never reads).
    fn shut(notify: Bool = true) Unit:
        let first = not self.inbox.closed
        self.inbox.closed = true
        if first and notify:
            msstd_process_ipc_write(self.link, frame(CLOSE, ""))

    # Waits for the entry to return and gives its result, or `Exited` with the status of a child that ended first.
    fn result[T: Data](native: NativeProcess) T!ProcessError:
        while true:
            if let body = self.inbox.result.clone():
                match decode[T](body):
                    ok(value): return ok(value)
                    error(e): return error(ProcessError.Broken(e.message()))

            match self.next_frame():
                ok(next):
                    if next.is_none():
                        let code = msstd_process_forked_wait(native, -1).get(-1)
                        return error(ProcessError.Exited(code))

                    let frame = next.get(Frame(kind: -1, body: ""))

                    if frame.kind == RESULT:
                        self.finish(frame.body.clone())
                    else if frame.kind == CLOSE:
                        self.finish(none)
                error(e):
                    return error(ProcessError.Broken(e.message()))

        return error(ProcessError.Exited(-1))

# One end of a process channel: JSON frames over the IPC pipe.
type ProcessTransport[In: Data, Out: Data]:
    link: NativeLink
    inbox: Shared[Inbox]

impl Transport[In, Out] for ProcessTransport[In, Out]:
    fn send(value: In) Unit!ChannelError:
        if self.inbox.closed or self.inbox.finished:
            return error(ChannelError.Closed)

        let text = try encode(value)
        if not msstd_process_ipc_write(self.link, frame(MESSAGE, text)):
            return error(ChannelError.Broken("the other process exited"))

        return ok(unit)

    fn receive() Out?!ChannelError:
        if self.inbox.closed:
            return error(ChannelError.Closed)
        if self.inbox.finished:
            return ok(none)

        let end = PipeEnd(self.link.clone(), self.inbox)

        while true:
            let next = try end.next_frame()
            if next.is_none():
                return error(ChannelError.Broken("the other process exited"))

            let frame = next.get(Frame(kind: -1, body: ""))

            if frame.kind == RETRY:
                if self.inbox.finished:
                    return ok(none)

                continue

            if frame.kind == MESSAGE:
                return ok(try decode[Out](frame.body))

            if frame.kind == CLOSE:
                end.finish(none)
                return ok(none)

            if frame.kind == RESULT:
                end.finish(frame.body.clone())
                return ok(none)

            return error(ChannelError.Broken("a frame has an unknown kind"))

        return ok(none)

    var fn close() Unit:
        PipeEnd(self.link.clone(), self.inbox).shut()

# The child's side: runs `entry` on the child's end of the channel, then sends `close` (if the
# entry did not) and the result, and closes the pipe.
fn serve[T: Data, In: Data, Out: Data](entry: fn(Channel[Out, In]) T) Unit:
    let link = msstd_process_ipc_child()
    let inbox = Shared(Inbox())
    let value = entry(
        Channel[Out, In](
            transport: ProcessTransport[Out, In](
                link: link.clone(), inbox: inbox
            )
        )
    )
    PipeEnd(link.clone(), inbox).shut()

    match encode(value):
        ok(text): msstd_process_ipc_write(link, frame(RESULT, text))
        error(_): msstd_process_ipc_write(link, frame(RESULT, ""))

    msstd_process_ipc_close(link)

fn nanos(limit: Duration?) Int:
    if let d = limit:
        return d.to_nanoseconds()

    return -1

# What a group keeps of a process until it is closed: enough to close its channel and stop the child.
export type Open:
    # Internal state: the process's number in its group.
    id: Int
    # Internal state: the running child.
    native: NativeProcess
    # Internal state: the parent's end of the IPC pipe.
    link: NativeLink
    # Internal state: what the parent's end has read.
    inbox: Shared[Inbox]

# Closes the channel, then stops and joins the child.
fn stop_child(link: NativeLink, inbox: Shared[Inbox], native: NativeProcess) Unit:
    PipeEnd(link.clone(), inbox).shut(false)
    msstd_process_forked_close(native)

# A child process started by `ProcessGroup.spawn` at an entry returning `T`, with the parent's
# end of its channel.
export type Process[T: Data, In: Data = Unit, Out: Data = Unit]:
    # Internal state: the running child.
    native: NativeProcess
    # Internal state: the parent's end of the IPC pipe.
    link: NativeLink
    # Internal state: what the parent's end has read.
    inbox: Shared[Inbox]
    # The parent's end of the channel: sends `In` to the child and receives the `Out` it sends.
    channel: Channel[In, Out]
    # Internal state: the process's number in its group.
    id: Int
    # Internal state: the group's list of open processes, which `close` leaves.
    registry: Shared[List[Open]]

impl Process[T, In, Out]:
    # Waits for the entry to return and gives its result, or `Exited` with the status of a child
    # that ended first. Another task may receive from the channel meanwhile; one task reads the
    # pipe at a time and the other waits. Messages the child sent and the parent has not received are dropped.
    fn result() T!ProcessError:
        return PipeEnd(self.link.clone(), self.inbox).result[T](self.native)

    # The child's standard input, when spawned with `stdin: Stdio.Pipe`; otherwise already closed,
    # so writes return `Closed`. Closing it delivers end of input to the child.
    fn stdin() WriteStream:
        return msstd_process_forked_stdin(self.native)

    # The child's standard output, when spawned with `stdout: Stdio.Pipe`; otherwise already
    # closed. Read it while the child runs: a child whose pipe is full waits until it is read.
    fn stdout() ReadStream:
        return msstd_process_forked_output(self.native, 1)

    # The child's standard error, when spawned with `stderr: Stdio.Pipe`; otherwise already
    # closed. Read it like `stdout`.
    fn stderr() ReadStream:
        return msstd_process_forked_output(self.native, 2)

    # Waits for the child to exit and returns its exit status. Returns `Timeout` if `timeout`
    # elapses first, leaving the child running.
    fn wait(timeout: Duration?) Int!CommandError:
        return msstd_process_forked_wait(self.native, nanos(timeout))

    # Asks the child to stop (SIGTERM on Unix; Windows ends the whole tree). Does not wait.
    fn terminate() Unit:
        msstd_process_forked_signal(self.native, false)

    # Kills the child and the processes it started. Does not wait.
    fn kill() Unit:
        msstd_process_forked_signal(self.native, true)

impl Closeable for Process[T, In, Out]:
    # Closes the channel, then stops and joins the child. Call `result` first to keep it. Safe to call again.
    var fn close() Unit!:
        stop_child(self.link, self.inbox, self.native)

        for index in 0..self.registry.length():
            if self.registry[index].id == self.id:
                self.registry.remove(index)
                break

        return ok(unit)

# A scope that owns the child processes started in it. Each runs an entry returning `T` and has a
# two-way channel to the group: the child sends `Out` values and receives `In` values, both
# `Unit` unless given. Bind a group to a local: when its scope ends it stops every child still running.
# `In`, `Out` and `T` cross as JSON, so use plain data: records, alternatives, lists, maps,
# strings and numbers.
export type ProcessGroup[T: Data, In: Data = Unit, Out: Data = Unit]:
    # Internal state: the open processes in start order, changed through the shared handle so the
    # group closes when its scope ends.
    processes: Shared[List[Open]] = Shared(List[Open]())
    # Internal state: the number of the next process.
    started: Shared[Int] = Shared(0)

impl ProcessGroup[T, In, Out]:
    # Starts this executable again in a new process at `entry`, a top-level `def`, and returns the
    # process. The child gets its end of a new channel, and the process's `channel` is the
    # group's end. `stdin`, `stdout` and `stderr` each choose the parent's own stream (the
    # default), the null device, or a pipe the process's `stdin()`, `stdout()` or `stderr()`
    # reaches. Closing the process makes the group forget it.
    fn spawn(
        entry: fn(Channel[Out, In]) T,
        stdin: Stdio = Stdio.Inherit,
        stdout: Stdio = Stdio.Inherit,
        stderr: Stdio = Stdio.Inherit
    ) Process[T, In, Out]!ProcessError:
        let runner: fn() Unit = fn: serve(entry)
        let native = try msstd_process_fork(runner, stdin, stdout, stderr).map_error(
            not_started
        )
        let link = msstd_process_forked_link(native)
        let inbox = Shared(Inbox())
        let id: Int = self.started
        self.started = id + 1
        self.processes.append(Open(id, native.clone(), link.clone(), inbox))
        return ok(
            Process[T, In, Out](
                native: native,
                link: link.clone(),
                inbox: inbox,
                channel: Channel[In, Out](
                    transport: ProcessTransport[In, Out](
                        link: link, inbox: inbox
                    )
                ),
                id: id,
                registry: self.processes
            )
        )

    # Waits for every open process's result in start order, or returns the first error.
    # Closed processes are not included.
    fn results() List[T]!ProcessError:
        let count = self.processes.length()
        var values = List[T]()

        for index in 0..count:
            let open = self.processes[index].clone()
            let end = PipeEnd(open.link.clone(), open.inbox)
            values.append(try end.result[T](open.native))

        return ok(values)

impl Closeable for ProcessGroup[T, In, Out]:
    # Closes every open process: its channel, then the child, which is stopped and joined. Safe to call again.
    var fn close() Unit!:
        for index in 0..self.processes.length():
            let open = self.processes[index].clone()
            stop_child(open.link, open.inbox, open.native)

        return ok(unit)
