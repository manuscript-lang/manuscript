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

// A new stream: next may wait.
export interface Source[T]:
    // Waits for the next item; none at the end of the stream, an error when the source fails.
    var fn next() T?!
    // Releases what the source owns; the stream calls it once, when it closes.
    var fn close() Unit!

// A stream of values over time. It owns its source, parked in a runtime cell so that a pending read carries only the
// cell's id; dropping the stream drops the source and whatever it owns.
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
                        "stream: a read is already waiting", kind: ErrorCategory.Closed
                    )
                )
            )

impl ReadStream[T]:
    // One step, started now and run where it is waited; none at the end.
    var fn read() Promise[T?]:
        let cell = self.cell
        // One closure that owns the promise's id and the cell, instead of `deferred`'s wrapper around a second one.
        let id = msrt_promise_new()
        msrt_promise_defer(id, fn: step[T](id, cell))
        return adopt[T?](id)

    // The items as an iterator for `for x in s.wait()`: each is `T!`, so a failure arrives in the loop and ends it.
    var fn wait() Waiting[T]:
        return Waiting[T](self.cell, false)

// The items of a stream, one read at a time; `for item in stream.wait()` waits for each.
export type Waiting[T]:
    // The runtime cell that holds the stream's source.
    cell: Int
    // True after the end of the stream or a failure; later steps give none.
    ended: Bool

impl Iterator[T!] for Waiting[T]:
    // Waits for the next item: `ok(item)`, an error that ends the loop, or none at the end.
    var fn next() T!?:
        if self.ended:
            return none

        // The waiter runs the source's step itself: the same work a deferred read would run on this stack, without a
        // promise, a closure or a result copy per item.
        var result: T?! = ok(none)

        match msrt_cells_take[Source[T]](self.cell):
            source:
                var running = source
                result = running.next()
                msrt_cells_put[Source[T]](self.cell, running)
            none:
                result = error(
                    Error(
                        "stream: a read is already waiting", kind: ErrorCategory.Closed
                    )
                )

        if result.is_error():
            self.ended = true
            return error(result.err())

        if let item = result.get():
            return ok(item)

        self.ended = true
        return none

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
            return error(Error("stream: read timed out", kind: ErrorCategory.Timeout))

        let chunk = msrt_promise_take[Bytes](p)
        msrt_promise_drop(p)
        if let data = chunk:
            return ok(data)

        let message = msrt_streams_error(self.id)
        if message.length() > 0:
            return error(Error(message, kind: ErrorCategory.Failed))

        return ok(none)

    var fn close() Unit!:
        msrt_streams_close(self.id)
        return ok(unit)

// A stream over the runtime stream-table descriptor `id` (a pipe, socket or file): chunks until the end. A negative
// id is a stream that is already at its end.
export fn descriptor_reader(id: Int) ReadStream[Bytes]:
    return stream[Bytes](DescriptorSource(id))

// Writes to the runtime stream-table descriptor `id`; a negative id fails every write with `Closed`.
type DescriptorSink:
    id: Int

impl Sink[Bytes] for DescriptorSink:
    var fn put(value: Bytes) Unit!:
        if msrt_streams_write(self.id, value) != 0:
            return error(Error("stream: closed", kind: ErrorCategory.Closed))

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

// A place values are written to. `put` never waits.
export interface Sink[T]:
    // Moves `value` into the sink's buffer without waiting; an error once the sink is closed.
    var fn put(value: T) Unit!
    // A promise that finishes once everything put so far has drained.
    var fn drain() Promise[Unit]
    // Items or bytes put and not yet drained.
    fn buffered() Int
    // Drains what is buffered and releases what the sink owns; the stream calls it once, when it closes.
    var fn close() Unit!

// A stream that accepts values over time. `write` moves the value into a buffer and never waits; `flush` is the
// backpressure point.
export opaque type WriteStream[T]:
    // The destination the stream's writes go to.
    sink: Sink[T]

impl WriteStream[T]:
    // Moves `value` into the stream's buffer. `Closed` once the reader is gone.
    var fn write(value: T) Unit!:
        return self.sink.put(value)

    // A promise that finishes when the buffer has drained.
    var fn flush() Promise[Unit]:
        return self.sink.drain()

    // Items or bytes not yet drained.
    fn buffered() Int:
        return self.sink.buffered()

impl Closeable for WriteStream[T]:
    // Hands what is buffered to the runtime and releases the sink.
    var fn close() Unit!:
        return self.sink.close()

// Wraps `sink` as a WriteStream that owns it.
export fn writer[T](sink: Sink[T]) WriteStream[T]:
    return WriteStream[T](sink: sink)

// The reading end of a pipe: the one reader, ended by the last writer closing.
type PipeSource[T]:
    id: Int

impl Source[T] for PipeSource[T]:
    var fn next() T?!:
        let p = msrt_pipe_read(self.id)
        let code = msrt_promise_wait(p, -1)

        if code != 0:
            msrt_promise_drop(p)
            return error(Error("pipe: read cancelled", kind: ErrorCategory.Other))

        let value = msrt_promise_take[T](p)
        msrt_promise_drop(p)
        return ok(value)

    var fn close() Unit!:
        msrt_pipe_close_reader(self.id)
        return ok(unit)

// One writing end of a pipe; closing it releases that writer.
type PipeSink[T: Clonable]:
    id: Int

impl Sink[T] for PipeSink[T]:
    var fn put(value: T) Unit!:
        if msrt_pipe_write[T](self.id, value) != 0:
            return error(Error("pipe: the reader is gone", kind: ErrorCategory.Closed))

        return ok(unit)

    var fn drain() Promise[Unit]:
        return adopt[Unit](msrt_pipe_flush(self.id))

    fn buffered() Int:
        return msrt_pipe_buffered(self.id)

    var fn close() Unit!:
        msrt_pipe_close_writer(self.id)
        return ok(unit)

// An in-memory stream of whole values, in order: any number of writers and one reader. A write hands the pipe a copy
// (the stream interface only lends the argument), so `T` must be `Clonable`; the copy then moves through by pointer.
// `capacity` is the number of queued values above which a writer's `flush` waits. The pipe itself is not a writer: the
// reader ends once every writer from `writer()` has closed, so make the writers before reading. Closing the reader
// makes later writes fail with `Closed`.
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

// A changed stream: never waits; appends zero or more items per input, and what it held back at the end.
export interface Transform[A, B]:
    // Takes one input item and returns the output items it completes, possibly none.
    var fn feed(value: A) List[B]!
    // Called once at the end of the input; returns the items held back.
    var fn finish() List[B]!

// Items a transform produced and the reader has not taken yet, newest first so `pop` moves the next one out.
type Through[A, B]:
    input: ReadStream[A]
    transform: Transform[A, B]
    pending: List[B]
    finished: Bool

impl Source[B] for Through[A, B]:
    var fn next() B?!:
        while true:
            if let item = self.pending.pop():
                return ok(item)
            if self.finished:
                return ok(none)

            let step = try self.input.read().wait()
            var produced: List[B] = []

            if let value = step:
                produced = try self.transform.feed(value)
            else:
                self.finished = true
                produced = try self.transform.finish()

            produced.reverse()
            self.pending = produced

        return ok(none)

    var fn close() Unit!:
        return self.input.close()

// A stream of `transform`'s output over `input`; closing it closes `input`.
export fn through[A, B](input: ReadStream[A], transform: Transform[A, B]) ReadStream[B]:
    return stream[B](Through[A, B](input, transform, [], false))

// One of this process's three standard streams.
export type StdStream:
    case Input  // Standard input; once redirected it reads as end of file.
    case Output  // Standard output; once redirected its writes are discarded.
    case Error  // Standard error; once redirected its writes are discarded.

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
export type TerminalEvent:
    // Printable characters typed together.
    case Text(
        // The typed characters in order, as valid UTF-8 text.
        text: String
    )
    // A named or modified key press.
    case Key(
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
    case Resize(
        // The new width in columns.
        columns: Int,
        // The new height in rows.
        rows: Int
    )

// The part of the screen cleared by `RawTerminal.erase`.
export type EraseRegion:
    case Screen  // Every cell of the screen; the cursor does not move.
    case Line  // The whole cursor line.
    case LineEnd  // From the cursor to the end of the line.
    case LineStart  // From the start of the line to the cursor.

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
    // Input events as a stream: keys, text and resizes, one per read. Waits honor cancellation and `wait(timeout:)`.
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

    // Returns the current terminal size, or `Closed` after close.
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

    // Moves the cursor to a zero-based row and column; negative or very large values return `InvalidInput`.
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

// Returns the terminal size, or `NotTerminal` when output is redirected.
export fn terminal_size() TerminalSize!:
    try msstd_terminal_size_status()
    return ok(
        TerminalSize(
            columns: msstd_terminal_size_columns(), rows: msstd_terminal_size_rows()
        )
    )

// Acquires raw input with an optional alternate screen; returns `Busy` while another raw terminal is open and `NotTerminal` when streams are redirected.
export fn raw_mode(alternate_screen: Bool) RawTerminal!:
    let native = try msstd_terminal_raw_mode(alternate_screen)
    return ok(RawTerminal(handle: RawHandle(native)))
