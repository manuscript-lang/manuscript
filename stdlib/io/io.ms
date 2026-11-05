import Closeable, Iterator from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import Promise, complete, adopt from "@std/concurrency/promise.ms"
import Duration from "@std/os/time.ms"
import (
    msrt_promise_new,
    msrt_promise_defer,
    msrt_promise_take,
    msrt_promise_wait,
    msrt_promise_drop,
    msrt_streams_open,
    msrt_streams_read,
    msrt_streams_error,
    msrt_streams_close,
    msrt_streams_write,
    msrt_streams_flush,
    msrt_streams_buffered,
    msrt_pipe_new,
    msrt_pipe_add_writer,
    msrt_pipe_write,
    msrt_pipe_read,
    msrt_pipe_flush,
    msrt_pipe_buffered,
    msrt_pipe_close_writer,
    msrt_pipe_close_reader,
    msrt_cells_new,
    msrt_cells_take,
    msrt_cells_put,
    msrt_cells_drop,
    msrt_cells_out,
    msrt_io_write_stdout,
    msrt_io_write_stderr,
    msrt_io_write_bytes_stdout,
    msrt_io_write_bytes_stderr,
    msrt_io_flush,
    msrt_promise_finished
) from "@std/internal/promises.ms"
import (
    msstd_terminal_event_kind,
    msstd_terminal_event_text,
    msstd_terminal_event_ctrl,
    msstd_terminal_event_alt,
    msstd_terminal_event_shift,
    msstd_terminal_event_columns,
    msstd_terminal_event_rows,
    msstd_io_redirect_null,
    msstd_terminal_raw_mode,
    msstd_terminal_capabilities_input_is_terminal,
    msstd_terminal_capabilities_output_is_terminal,
    msstd_terminal_capabilities_error_is_terminal,
    msstd_terminal_capabilities_raw_mode,
    msstd_terminal_capabilities_resize_events,
    msstd_terminal_capabilities_colors,
    msstd_terminal_size_status,
    msstd_terminal_size_columns,
    msstd_terminal_size_rows,
    msstd_terminal_raw_terminal_close,
    msstd_terminal_raw_terminal_share,
    msstd_terminal_raw_terminal_next_event,
    msstd_terminal_raw_terminal_size_status,
    msstd_terminal_raw_terminal_size_columns,
    msstd_terminal_raw_terminal_size_rows,
    msstd_terminal_raw_terminal_move_cursor,
    msstd_terminal_raw_terminal_show_cursor,
    msstd_terminal_raw_terminal_erase
) from "@std/internal/io.ms"

// Supplies the items of a stream; `next` may wait for an item to become available.
export interface Source[T]:
    // Returns the next item, waiting when needed; none at the end of the stream, an error when the source fails.
    var fn next() T?!
    // Releases what the source owns; the stream calls it once, when it closes.
    var fn close() Unit!

// Read values one at a time with `read().wait()`, or loop over `wait()` and apply `try` to each item.
// The stream owns its source; closing or dropping it releases that source and the resources it owns.
export opaque type ReadStream[T]:
    // The runtime cell that holds the source.
    cell: Int

// Runs one `next` of `source`, which the caller took out of its cell, and puts it back.
fn run[T](id: Int, cell: Int, source: Source[T]) Unit:
    var running = source
    let result = running.next()
    msrt_cells_put[Source[T]](cell, running)
    complete[T?](id, result)

// Runs the read `id` in the task that waits and completes it with the source's answer.
fn step[T](id: Int, cell: Int) Unit:
    match msrt_cells_take[Source[T]](cell):
        source:
            run[T](id, cell, source)
        none:
            complete[T?](
                id,
                error(
                    Error(
                        "stream: a read is already waiting", kind: "EBADF"
                    )
                )
            )

impl ReadStream[T]:
    // Returns a promise for the next item. The source runs when waited; `none` marks the end.
    var fn read() Promise[T?]:
        let cell = self.cell

        // One closure that owns the promise's id and the cell, instead of `deferred`'s wrapper around a second one.
        let id = msrt_promise_new()
        msrt_promise_defer(id, fn: step[T](id, cell))
        return adopt[T?](id)

    // The items as an iterator for `for x in s.wait()`: each is `T!`, so a failure arrives in the loop and ends it.
    // The loop holds the source until it ends, breaks or fails, then hands it back to the stream.
    var fn wait() Waiting[T]:
        var held: List[Source[T]] = []
        if let source = msrt_cells_take[Source[T]](self.cell):
            held.append(source)
        return Waiting[T](self.cell, held, false)

// The items of a stream, one read at a time; `for item in stream.wait()` waits for each.
export opaque type Waiting[T]:
    // The runtime cell the source goes back to.
    cell: Int
    // The stream's source while the loop runs; empty when a read was already waiting.
    held: List[Source[T]]
    // True after the end of the stream or a failure; later steps give none.
    ended: Bool

impl Iterator[T!] for Waiting[T]:
    // Waits for the next item: `ok(item)`, an error that ends the loop, or none at the end.
    var fn next() T!?:
        if self.ended:
            return none

        if self.held.length() == 0:
            self.ended = true
            return error(Error("stream: a read is already waiting", kind: "EBADF"))

        // The loop runs the source's step itself, on this stack: no promise, closure or cell round trip per item.
        let result = self.held[0].next()

        if result.is_error():
            self.ended = true
            return error(result.err())

        // Consume both wrappers so the yielded item takes their cleanup obligation.
        if let maybe = result:
            if let item = maybe:
                return ok(item)
        self.ended = true
        return none

impl Closeable for Waiting[T]:
    // Hands the source back to the stream when the loop ends, so the stream reads on from there or closes it. When
    // the stream was closed or dropped during the loop, the source closes here, at the end of this scope.
    var fn close() Unit!:
        if let source = self.held.pop():
            if msrt_cells_out(self.cell):
                msrt_cells_put[Source[T]](self.cell, source)
        return ok(unit)

// A stream's source, moved out so a stage pulls it with a plain call. When a read already holds the source, the
// stage reads through the stream instead, as before.
fn source_of[T](input: ReadStream[T]) Source[T]:
    var owned = input
    if let source = msrt_cells_take[Source[T]](owned.cell):
        return source

    return Reading[T](owned)

// A source that reads through a stream whose source a pending read holds.
type Reading[T]:
    input: ReadStream[T]

impl Source[T] for Reading[T]:
    var fn next() T?!:
        return self.input.read().wait()

    var fn close() Unit!:
        return self.input.close()

impl Closeable for ReadStream[T]:
    // Drops the source and everything it owns. A read in flight ends with an error.
    var fn close() Unit!:
        // Close the source by hand so its error is returned, then park it back in the cell: moved
        // out, it is not closed again at scope end, and dropping the cell only frees it.
        var failure: Error? = none

        if let source = msrt_cells_take[Source[T]](self.cell):
            var closing = source
            let result = closing.close()
            if result.is_error():
                failure = result.err()
            msrt_cells_put[Source[T]](self.cell, closing)

        msrt_cells_drop(self.cell)
        if let cause = failure:
            return error(cause)

        return ok(unit)

// Wraps `source` as a ReadStream that owns it.
export fn stream[T](source: Source[T]) ReadStream[T]:
    return ReadStream[T](cell: msrt_cells_new[Source[T]](source))

type DescriptorSource:
    id: Int

impl Source[Bytes] for DescriptorSource:
    var fn next() Bytes?!:
        let p = msrt_streams_read(self.id)
        let code = msrt_promise_wait(p, -1)

        if code != 0:
            msrt_promise_drop(p)
            return error(Error("stream: read timed out", kind: "ETIMEDOUT"))

        let chunk = msrt_promise_take[Bytes](p)
        msrt_promise_drop(p)
        if let data = chunk:
            return ok(data)

        let message = msrt_streams_error(self.id)
        if message.length() > 0:
            return error(Error(message, kind: "EIO"))

        return ok(none)

    var fn close() Unit!:
        msrt_streams_close(self.id)
        return ok(unit)

// A stream over the runtime stream-table descriptor `id` (a pipe, socket or file): chunks until the end. A negative
// id is a stream that is already at its end.
export fn descriptor_reader(id: Int) ReadStream[Bytes]:
    return stream[Bytes](DescriptorSource(id))

// Writes to the runtime stream-table descriptor `id`; a negative id fails every write with `EBADF`.
type DescriptorSink:
    id: Int

impl Sink[Bytes] for DescriptorSink:
    var fn put(value: Bytes) Unit!:
        if msrt_streams_write(self.id, value) != 0:
            return error(Error("stream: closed", kind: "EBADF"))

        return ok(unit)

    var fn drain() Promise[Unit]:
        return adopt[Unit](msrt_streams_flush(self.id))

    fn buffered() Int:
        return msrt_streams_buffered(self.id)

    var fn close() Unit!:
        msrt_streams_close(self.id)
        return ok(unit)

// A WriteStream over the runtime stream-table descriptor `id`.
export fn descriptor_writer(id: Int) WriteStream[Bytes]:
    return writer[Bytes](DescriptorSink(id))

// Returns the process standard-input stream.
export fn stdin() ReadStream[Bytes]:
    return stream[Bytes](DescriptorSource(msrt_streams_open(0, 1)))

// Receives written values and defines their buffering, flush condition, and cleanup.
export interface Sink[T]:
    // Accepts `value` and returns any write failure. A custom sink may wait while accepting it.
    var fn put(value: T) Unit!
    // A promise for the sink's flush condition: descriptor sinks drain pending bytes; a pipe waits until its queue is at most capacity or its reader closes.
    var fn drain() Promise[Unit]
    // Reports the sink's pending items or bytes.
    fn buffered() Int
    // Called when the stream closes to release what the sink owns. The sink defines how buffered work finishes and may wait.
    var fn close() Unit!

// Send values with `write`, then use `flush().wait()` to wait for the destination's flush condition.
// The stream owns its sink and closes it when its scope ends.
export opaque type WriteStream[T]:
    // The destination the stream's writes go to.
    sink: Sink[T]
    // What a stream that collects for its owner holds, oldest first; `through` reads its transform's output here.
    items: List[T]
    // True for a collecting stream: writes go to `items`, not to the sink.
    collects: Bool

impl WriteStream[T]:
    // Sends `value` to the sink, which may wait; returns sink errors, including `EBADF` for a closed pipe reader.
    var fn write(value: T) Unit!:
        if self.collects:
            self.items.append(value)
            return ok(unit)

        return self.sink.put(value)

    // Returns the sink's flush promise; a pipe may still hold up to its capacity of unread values when this completes.
    var fn flush() Promise[Unit]:
        return self.sink.drain()

    // Reports pending items or bytes using the sink's accounting.
    fn buffered() Int:
        if self.collects:
            return self.items.length()

        return self.sink.buffered()

impl Closeable for WriteStream[T]:
    // Calls the sink's close operation to release its resources; a custom sink may wait while closing.
    var fn close() Unit!:
        return self.sink.close()

// Wraps `sink` as a WriteStream that owns it.
export fn writer[T](sink: Sink[T]) WriteStream[T]:
    return WriteStream[T](sink, [], false)

// The sink of a collecting stream: its writes never reach it.
type Collected[T]:
    unused: Bool = false

impl Sink[T] for Collected[T]:
    var fn put(value: T) Unit!:
        return error(Error("stream: closed", kind: "EBADF"))

    var fn drain() Promise[Unit]:
        return adopt[Unit](msrt_promise_finished())

    fn buffered() Int:
        return 0

    var fn close() Unit!:
        return ok(unit)

// The reading end of a pipe: the one reader, ended by the last writer closing.
type PipeSource[T]:
    id: Int

impl Source[T] for PipeSource[T]:
    var fn next() T?!:
        let p = msrt_pipe_read(self.id)
        let code = msrt_promise_wait(p, -1)

        if code != 0:
            msrt_promise_drop(p)
            return error(Error("pipe: read cancelled", kind: "ECANCELED"))

        let value = msrt_promise_take[T](p)
        msrt_promise_drop(p)
        return ok(value)

    var fn close() Unit!:
        msrt_pipe_close_reader(self.id)
        self.id = 0
        return ok(unit)

// One writing end of a pipe; closing it releases that writer.
type PipeSink[T: Clonable]:
    id: Int

impl Sink[T] for PipeSink[T]:
    var fn put(value: T) Unit!:
        if msrt_pipe_write[T](self.id, value) != 0:
            return error(Error("pipe: the reader is gone", kind: "EBADF"))

        return ok(unit)

    var fn drain() Promise[Unit]:
        return adopt[Unit](msrt_pipe_flush(self.id))

    fn buffered() Int:
        return msrt_pipe_buffered(self.id)

    var fn close() Unit!:
        // Closing again releases nothing: an owner that closed the writer by hand is closed again at scope end.
        msrt_pipe_close_writer(self.id)
        self.id = 0
        return ok(unit)

// An in-memory stream of whole values, in order: any number of writers and one reader. A write hands the pipe a copy
// (the stream interface only lends the argument), so `T` must be `Clonable`; the copy then moves through by pointer.
// `capacity` is the number of queued values above which a writer's `flush` waits. The pipe itself is not a writer: the
// reader ends once every writer from `writer()` has closed, so make the writers before reading. Closing the reader
// makes later writes fail with `EBADF`.
export opaque type Pipe[T: Clonable]:
    // The runtime pipe's id.
    id: Int
    // Whether `reader` has handed out the reading end.
    taken: Bool

impl Pipe[T]:
    // A new writing end, like dup on a descriptor. Close it when done: the reader ends when every writer has closed. Safe
    // to call from a promise that owns the pipe: each call makes a writer of its own.
    fn writer() WriteStream[T]:
        msrt_pipe_add_writer(self.id)
        return writer[T](PipeSink[T](self.id))

    // The reading end. A pipe has one: later calls return a stream that is already at its end.
    var fn reader() ReadStream[T]:
        if self.taken:
            return stream[T](PipeSource[T](0))

        self.taken = true
        return stream[T](PipeSource[T](self.id))

    // Waits for the next value, none once every writer has closed. It reads the pipe's one reader place without taking a stream, for a consumer that only borrows the pipe, such as a promise: use it instead of `reader()`, never beside it.
    fn receive() T?!:
        var source = PipeSource[T](self.id)
        return source.next()

impl Closeable for Pipe[T]:
    // Releases the reading end if no one took it.
    var fn close() Unit!:
        if not self.taken:
            msrt_pipe_close_reader(self.id)
        return ok(unit)

// Makes an in-memory pipe whose writers' `flush` waits while more than `capacity` values are queued.
export fn pipe[T: Clonable](capacity: Int) Pipe[T]:
    let id = msrt_pipe_new(capacity)

    // The runtime starts a pipe with one writer, which the Pipe value would hold; writers come from `writer()` instead.
    msrt_pipe_close_writer(id)
    return Pipe[T](id: id, taken: false)

// Standard output and error share the runtime's process-wide buffers.
type StdoutSink:
    bytes_too: Bool

impl Sink[String] for StdoutSink:
    var fn put(value: String) Unit!:
        msrt_io_write_stdout(value)
        return ok(unit)

    var fn drain() Promise[Unit]:
        msrt_io_flush()
        return adopt[Unit](msrt_promise_finished())

    fn buffered() Int:
        return 0

    var fn close() Unit!:
        msrt_io_flush()
        return ok(unit)

type StderrSink:
    bytes_too: Bool

impl Sink[String] for StderrSink:
    var fn put(value: String) Unit!:
        msrt_io_write_stderr(value)
        return ok(unit)

    var fn drain() Promise[Unit]:
        return adopt[Unit](msrt_promise_finished())

    fn buffered() Int:
        return 0

    var fn close() Unit!:
        return ok(unit)

type StdoutBytesSink:
    bytes_too: Bool

impl Sink[Bytes] for StdoutBytesSink:
    var fn put(value: Bytes) Unit!:
        msrt_io_write_bytes_stdout(value)
        return ok(unit)

    var fn drain() Promise[Unit]:
        msrt_io_flush()
        return adopt[Unit](msrt_promise_finished())

    fn buffered() Int:
        return 0

    var fn close() Unit!:
        msrt_io_flush()
        return ok(unit)

type StderrBytesSink:
    bytes_too: Bool

impl Sink[Bytes] for StderrBytesSink:
    var fn put(value: Bytes) Unit!:
        msrt_io_write_bytes_stderr(value)
        return ok(unit)

    var fn drain() Promise[Unit]:
        return adopt[Unit](msrt_promise_finished())

    fn buffered() Int:
        return 0

    var fn close() Unit!:
        return ok(unit)

// Standard output as bytes; it shares its buffer with `stdout()`.
export fn stdout_bytes() WriteStream[Bytes]:
    return writer[Bytes](StdoutBytesSink(true))

// Standard error as bytes.
export fn stderr_bytes() WriteStream[Bytes]:
    return writer[Bytes](StderrBytesSink(true))

// Standard output as text; writes are buffered until flushed or the process exits.
export fn stdout() WriteStream[String]:
    return writer[String](StdoutSink(false))

// Standard error as text.
export fn stderr() WriteStream[String]:
    return writer[String](StderrSink(false))

// Transforms each input into zero or more output items, then emits anything held back at the end; custom steps may wait.
export interface Transform[A, B]:
    // Takes one input item and writes the output items it completes, possibly none, to `out`.
    var fn step(value: A, var out: WriteStream[B]) Unit!
    // Called once at the end of the input; writes the items held back to `out`.
    var fn finish(var out: WriteStream[B]) Unit!

// A transform over a source: its output collects in `out`, reversed after each step so `pop` moves the next one out.
type Through[A, B]:
    input: Source[A]
    transform: Transform[A, B]
    out: WriteStream[B]
    finished: Bool

impl Source[B] for Through[A, B]:
    var fn next() B?!:
        while true:
            if let item = self.out.items.pop():
                return ok(item)
            if self.finished:
                return ok(none)

            let step = try self.input.next()
            var wrote: Unit! = ok(unit)

            if let value = step:
                wrote = self.transform.step(value, var self.out)
            else:
                self.finished = true
                wrote = self.transform.finish(var self.out)

            // A failed step's partial output is dropped, so the failure is the next item.
            if wrote.is_error():
                self.out.items = []
                return error(wrote.err())

            if self.out.items.length() > 1: self.out.items.reverse()

        return ok(none)

    var fn close() Unit!:
        return self.input.close()

// A stream of `transform`'s output over `input`; closing it closes `input`.
export fn through[A, B](input: ReadStream[A], transform: Transform[A, B]) ReadStream[B]:
    let out = WriteStream[B](Collected[B](), [], true)
    return stream[B](Through[A, B](source_of[A](input), transform, out, false))

// One of this process's three standard streams.
export enum StdStream:
    Input  // Standard input; once redirected it reads as end of file.
    Output  // Standard output; once redirected its writes are discarded.
    Error  // Standard error; once redirected its writes are discarded.

// Points the process's own standard stream at the null device (`/dev/null`, or `NUL` on Windows): input reads as end of file and output is discarded.
// This replaces the descriptor itself, so it also affects children started afterwards that inherit it. Buffered standard output is written first. The change cannot be undone.
export fn redirect_to_null(stream: StdStream) Unit!:
    var which = 2

    match stream:
        Input: which = 0
        Output: which = 1
        Error: which = 2

    return msstd_io_redirect_null(which)

// Character columns and rows of a terminal window.
export type TerminalSize:
    // Width in character columns.
    columns: Int
    // Height in character rows.
    rows: Int

/*
What the current process can do with its standard streams as a terminal.
`colors` is 0 when output is not a terminal, `NO_COLOR` is set, or `TERM` is
`dumb`; otherwise 16, 256, or 16777216 from `TERM` and `COLORTERM`.
*/
export type TerminalCapabilities:
    // True when standard input is a terminal.
    input_is_terminal: Bool
    // True when standard output is a terminal.
    output_is_terminal: Bool
    // True when standard error is a terminal.
    error_is_terminal: Bool
    // True when `raw_mode` can succeed on this host and the streams are terminals.
    raw_mode: Bool
    // True when raw terminals deliver `Resize` events.
    resize_events: Bool
    // Supported color count, or 0 when color output should be avoided.
    colors: Int

/*
One decoded terminal input event. `Text` carries printable characters typed
together. `Key` names a non-printing or modified key: `enter`, `tab`,
`backspace`, `escape`, `space`, `up`, `down`, `left`, `right`, `home`, `end`,
`insert`, `delete`, `page_up`, `page_down`, `f1` to `f12`, or a letter with
`ctrl` or `alt` set. `Resize` carries the new size.
*/
export enum TerminalEvent:
    // Printable characters typed together.
    Text(
        // The typed characters in order, as valid UTF-8 text.
        text: String
    )
    // A named or modified key press.
    Key(
        // The key name, such as `enter`, `up`, or a lowercase letter.
        name: String,
        // True when Control was held.
        ctrl: Bool,
        // True when Alt was held.
        alt: Bool,
        // True when Shift was held for a named key.
        shift: Bool
    )
    // The terminal window changed size.
    Resize(
        // The new width in columns.
        columns: Int,
        // The new height in rows.
        rows: Int
    )

// The part of the screen cleared by `RawTerminal.erase`.
export enum EraseRegion:
    Screen  // Every cell of the screen; the cursor does not move.
    Line  // The whole cursor line.
    LineEnd  // From the cursor to the end of the line.
    LineStart  // From the start of the line to the cursor.

// Reads decoded events from a raw terminal's native handle.
type TerminalEvents:
    handle: RawHandle

impl Source[TerminalEvent] for TerminalEvents:
    var fn next() TerminalEvent?!:
        let ready = try msstd_terminal_raw_terminal_next_event(self.handle.native, none)
        if ready.is_none(): return ok(none)

        let kind = msstd_terminal_event_kind()
        if kind == 0: return ok(TerminalEvent.Text(msstd_terminal_event_text()))
        if kind == 1: return ok(
            TerminalEvent.Key(
                msstd_terminal_event_text(), msstd_terminal_event_ctrl(),
                msstd_terminal_event_alt(), msstd_terminal_event_shift()
            )
        )

        return ok(
            TerminalEvent.Resize(
                msstd_terminal_event_columns(), msstd_terminal_event_rows()
            )
        )

    var fn close() Unit!:
        return ok(unit)

// The runtime handle behind a `RawTerminal`.
export extern type NativeRawTerminal

/*
Raw terminal input and cursor control. Closing it, or leaving the
scope that acquired it by return, error, fault, or cancellation, restores the
original terminal settings, shows the cursor, and leaves the alternate screen.
In raw mode, Ctrl-C arrives as a `c` key with `ctrl` set instead of cancelling.
*/
export type RawTerminal:
    // The runtime handle; the event stream holds another on the same terminal.
    handle: RawHandle

// What the native `raw_mode` returns: the runtime handle itself.
export type RawHandle:
    // The runtime terminal handle.
    native: NativeRawTerminal

impl Closeable for RawTerminal:
    // Restores the terminal; closing again does nothing.
    var fn close() Unit!:
        msstd_terminal_raw_terminal_close(self.handle.native)
        return ok(unit)

impl RawTerminal:
    // Input events as a stream: keys, text and resizes, one per read. Waits honor cancellation and promise timeouts.
    // The stream ends with an error once the terminal is closed; closing the stream leaves the terminal open.
    fn events() ReadStream[TerminalEvent]:
        return stream[TerminalEvent](
            TerminalEvents(
                RawHandle(
                    msstd_terminal_raw_terminal_share(
                        self.handle.native
                    )
                )
            )
        )

    // Returns the current terminal size, or `EBADF` after close.
    fn size() TerminalSize!:
        try msstd_terminal_raw_terminal_size_status(self.handle.native)
        return ok(
            TerminalSize(
                columns: msstd_terminal_raw_terminal_size_columns(
                    self.handle.native
                ),
                rows: msstd_terminal_raw_terminal_size_rows(
                    self.handle.native
                )
            )
        )

    // Moves the cursor to a zero-based row and column; negative or very large values return `EINVAL`.
    fn move_cursor(row: Int, column: Int) Unit!:
        return msstd_terminal_raw_terminal_move_cursor(self.handle.native, row, column)

    // Shows or hides the cursor until the terminal is restored on close.
    fn show_cursor(visible: Bool) Unit!:
        return msstd_terminal_raw_terminal_show_cursor(self.handle.native, visible)

    // Erases the selected screen region without moving the cursor.
    fn erase(region: EraseRegion) Unit!:
        match region:
            Screen: return msstd_terminal_raw_terminal_erase(self.handle.native, 0)
            Line: return msstd_terminal_raw_terminal_erase(self.handle.native, 1)
            LineEnd: return msstd_terminal_raw_terminal_erase(self.handle.native, 2)
            LineStart: return msstd_terminal_raw_terminal_erase(self.handle.native, 3)

// Reports terminal availability and color support without changing terminal state.
export fn terminal_capabilities() TerminalCapabilities:
    return TerminalCapabilities(
        input_is_terminal: msstd_terminal_capabilities_input_is_terminal(),
        output_is_terminal: msstd_terminal_capabilities_output_is_terminal(),
        error_is_terminal: msstd_terminal_capabilities_error_is_terminal(),
        raw_mode: msstd_terminal_capabilities_raw_mode(),
        resize_events: msstd_terminal_capabilities_resize_events(),
        colors: msstd_terminal_capabilities_colors()
    )

// Returns the terminal size, or `ENOTTY` when output is redirected.
export fn terminal_size() TerminalSize!:
    try msstd_terminal_size_status()
    return ok(
        TerminalSize(
            columns: msstd_terminal_size_columns(), rows: msstd_terminal_size_rows()
        )
    )

// Acquires raw input with an optional alternate screen; returns `EBUSY` while another raw terminal is open and `ENOTTY` when streams are redirected.
export fn raw_mode(alternate_screen: Bool) RawTerminal!:
    let native = try msstd_terminal_raw_mode(alternate_screen)
    return ok(RawTerminal(handle: RawHandle(native)))
