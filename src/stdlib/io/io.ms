import (
	Bytes from "@std/bytes.ms",
	adopt from "@std/concurrency/promise.ms",
	Closeable from "@std/core.ms",
	Duration, monotonic from "@std/time.ms",

	msstd_io_redirect_null, msstd_io_stdout_status from "@std/internal/io.ms",
	msrt_io_write_bytes_stderr,
	msrt_io_write_bytes_stdout,
	msrt_io_write_stderr,
	msrt_io_write_stdout,
	msrt_pipe_add_writer,
	msrt_pipe_brief_wait,
	msrt_pipe_close_reader,
	msrt_pipe_close_writer,
	msrt_pipe_ended,
	msrt_pipe_flush,
	msrt_pipe_new,
	msrt_pipe_read,
	msrt_pipe_try,
	msrt_pipe_write,
	msrt_promise_drop,
	msrt_promise_finished,
	msrt_promise_take,
	msrt_promise_wait,
	msrt_streams_buffered,
	msrt_streams_close,
	msrt_streams_error,
	msrt_streams_flush,
	msrt_streams_open,
	msrt_streams_read,
	msrt_streams_write,
	msrt_task_read_limit,
	msrt_task_read_limit_restore from "@std/internal/promises.ms",
)

// ---- Streams ------------------------------------------------------------------------------------------------------

// Supplies the items of a stream; `next` may wait for an item to become available.
export interface Source[T] {
	// Returns the next item, waiting when needed. Returns `null` at the end of the
	// stream and an error when the source fails.
	var fn next() T?!
	// Releases what the source owns; the stream calls it once, when it closes.
	move fn close() Void!
}

// Receives written values and defines their buffering, when they count as flushed
// and how the sink is cleaned up.
export interface Sink[T] {
	// Accepts `value` and returns any write failure. Waits while the sink is full, so a
	// writer cannot outrun it.
	var fn write(move value T) Void!
	// Returns once everything written has drained. A descriptor sink drains its pending
	// bytes; a pipe waits until its queue is at most its capacity or its reader closes.
	var fn flush() Void!
	// Called when the stream closes, to release what the sink owns. The sink decides
	// how buffered work finishes, and may wait.
	move fn close() Void!
}

// A stream of items. `for item in stream:` walks it, and a failed read returns its
// error from the enclosing function, as `?` would. `next` waits inside the source, so
// a task parks only at a file, socket or pipe. Make one with `ReadStream(source)`.
// The stream owns its source; closing or dropping the stream releases the source and
// what it owns.
export type ReadStream[T] {
	// The source this stream pulls; `close` replaces it with an ended one so what it
	// owned is released at once.
	source Source[T]
	// Whether `close` has run; a closed stream is at its end.
	closed Bool = false
}

// Returns the next item, or `null` at the end or after `close`. A failed read returns
// its error. With `timeout`, a read that waits that long in total (a stalled socket)
// fails with `ETIMEDOUT`. The source may be left mid-item, so close the stream
// afterwards.
fn var ReadStream[T].next(timeout Duration? = null) move T?! {
	if self.closed { return ok(null) }

	bound := timeout
	if bound != null { return read_bounded(self.source, bound) }

	return self.source.next()
}

// Closes the source and drops it, so a socket or file it held is released now.
// Later calls do nothing.
fn move ReadStream[T].close() Void! {
	if self.closed { return ok() }

	self.closed = true
	return self.source.close()
}

// Half-closes the stream: closes the source now and leaves the stream ended, so a
// holder (a connection's input side) keeps its other parts. Later reads return `null`.
fn var ReadStream[T].end() Void! {
	self.closed = true

	source := self.source
	self.source = EndedSource[T]()
	return source.close()
}

// Internal: one read of `source` that waits at most `bound` in total.
fn read_bounded[T](var source Source[T], bound Duration) T?! {
	var nanos = bound.to_nanoseconds()
	if nanos < 0 { nanos = 0 }

	started := monotonic()
	previous := msrt_task_read_limit(nanos)
	got := source.next()
	msrt_task_read_limit_restore(previous)
	if got.is_error() and monotonic().difference(started).compare(bound) >= 0 {
		return error(Error("I/O: read timed out", kind: "ETIMEDOUT"))
	}

	return got
}

// A source with nothing left: the one a closed `ReadStream` holds.
type EndedSource[T] {
	done Bool = true
}

fn var EndedSource[T].next() move T?! {
	return ok(null)
}

fn move EndedSource[T].close() Void! {
	return ok()
}

// A stream that sends values out with `write`; `flush` waits until the destination
// has taken them. Make one with `WriteStream(sink)`. The stream owns its sink and
// closes it when its scope ends.
export type WriteStream[T] {
	// The destination the stream's writes go to; `close` replaces it with a closed one.
	sink Sink[T]
}

// Sends `value` to the sink, which may wait; returns sink errors, including `EBADF`
// for a closed pipe reader.
fn var WriteStream[T].write(move value T) Void! {
	return self.sink.write(value)
}

// Returns once the sink has drained what was written; a pipe may still hold up to
// its capacity of unread values.
fn var WriteStream[T].flush() Void! {
	return self.sink.flush()
}

// Closes the sink and drops it. A custom sink may wait while closing.
fn move WriteStream[T].close() Void! {
	return self.sink.close()
}

// Half-closes the stream: closes the sink now and leaves the stream refusing writes, so
// the holder (a connection's output side) keeps its other parts.
fn var WriteStream[T].end() Void! {
	sink := self.sink
	self.sink = ClosedSink[T]()
	return sink.close()
}

// A sink that refuses every write: the one a closed `WriteStream` holds.
type ClosedSink[T] {
	done Bool = true
}

fn var ClosedSink[T].write(move value T) Void! {
	return error(Error("I/O: resource is closed", kind: "EBADF"))
}

fn var ClosedSink[T].flush() Void! {
	return ok()
}

fn move ClosedSink[T].close() Void! {
	return ok()
}

// ---- Descriptors and standard input --------------------------------------------------------------------------------

// Reads chunks from the runtime stream-table descriptor `id` (a pipe, socket or file)
// until the end; a negative id is already at its end. Wrap it as
// `ReadStream(DescriptorSource(id))` to get a stream.
export type DescriptorSource {
	// The runtime descriptor read from.
	id Int
	// Set by `close`, so a second close (the owner's scope end) releases nothing.
	closed Bool = false
}

// Waits for the next chunk of the descriptor. Returns `null` at its end and `EIO`
// when the descriptor failed. A wait that ends early, such as at the `timeout` of
// `ReadStream.next`, returns `ETIMEDOUT`.
fn var DescriptorSource.next() move Bytes?! {
	p := msrt_streams_read(self.id)
	code := msrt_promise_wait(p, -1)

	if code != 0 {
		msrt_promise_drop(p)
		return error(Error("stream: read timed out", kind: "ETIMEDOUT"))
	}

	chunk := msrt_promise_take[Bytes](p)
	msrt_promise_drop(p)

	data := chunk
	if data != null { return ok(data) }

	message := msrt_streams_error(self.id)
	if not message.is_empty() { return error(Error(message.clone(), kind: "EIO")) }

	return ok(null)
}

// Releases the descriptor without waiting.
fn move DescriptorSource.close() Void! {
	if self.closed { return ok() }

	self.closed = true
	msrt_streams_close(self.id)
}

// Bytes a descriptor may hold queued before `write` waits for it to drain.
HIGH_WATER := 1048576

// Writes to the runtime stream-table descriptor `id`; a negative id fails every write
// with `EBADF`. Wrap it as `WriteStream(DescriptorSink(id))` to get a stream.
export type DescriptorSink {
	// The runtime descriptor written to.
	id Int
	// Set by `close`, so a second close (the owner's scope end) releases nothing.
	closed Bool = false
}

// Queues the bytes for the descriptor; returns `EBADF` once it is closed. A write
// that leaves more than `HIGH_WATER` bytes queued waits until the descriptor has taken
// them, so a slow reader slows the writer. An OS write failure returns `EIO`, and
// later writes and flushes keep returning it until the descriptor closes.
fn var DescriptorSink.write(move value Bytes) Void! {
	if msrt_streams_write(self.id, value) != 0 {
		return error(Error("stream: closed", kind: "EBADF"))
	}

	descriptor_write_result(self.id)?
	if msrt_streams_buffered(self.id) > HIGH_WATER { return flush_descriptor(self.id) }
}

// Waits until the queued bytes have been handed to the descriptor; an OS write
// failure returns `EIO`.
fn var DescriptorSink.flush() Void! {
	return flush_descriptor(self.id)
}

// Waits until the queued bytes have been handed to the descriptor, then releases it.
// The descriptor is released even when the wait fails or is cancelled, and that
// failure is returned.
fn move DescriptorSink.close() Void! {
	if self.closed { return ok() }

	self.closed = true

	drained := flush_descriptor(self.id)
	msrt_streams_close(self.id)
	return drained
}

// An OS write failure is terminal: bytes may have been partly written, so later drains
// must not hide it.
fn descriptor_write_result(id Int) Void! {
	message := msrt_streams_error(id)
	if message.length() > 0 { return error(Error(message.clone(), kind: "EIO")) }

	return ok()
}

fn flush_descriptor(id Int) Void! {
	adopt[Void](msrt_streams_flush(id)).wait()?
	return descriptor_write_result(id)
}

// Returns the process standard-input stream.
// ms: effect std.console.read
export fn stdin() ReadStream[Bytes] {
	return ReadStream[Bytes](DescriptorSource(msrt_streams_open(0, 1)))
}

// ---- Standard output and error -------------------------------------------------------------------------------------

// Standard output, as text or bytes, sharing the runtime's process-wide buffer.
// Writes are buffered until a flush, process exit, the start of a child process, or a
// write to standard error. Closing does not flush: `stdout()` makes a fresh stream on
// each call, so a flush on close would turn every `stdout().write(...)` into a system
// call. `flush` returns the first failed write (a full disk, a closed descriptor), and
// `write` returns it once it is known. If output was lost and the program would
// otherwise have exited 0, the process exits 1. A broken pipe is not an error.
type StdoutText {
	unused Bool = false
}

fn var StdoutText.write(move value String) Void! {
	msrt_io_write_stdout(value)
	return msstd_io_stdout_status(false)
}

fn var StdoutText.flush() Void! {
	return msstd_io_stdout_status(true)
}

fn move StdoutText.close() Void! {
	return ok()
}

type StdoutBytes {
	unused Bool = false
}

fn var StdoutBytes.write(move value Bytes) Void! {
	msrt_io_write_bytes_stdout(value)
	return msstd_io_stdout_status(false)
}

fn var StdoutBytes.flush() Void! {
	return msstd_io_stdout_status(true)
}

fn move StdoutBytes.close() Void! {
	return ok()
}

// Standard error, as text or bytes.
type StderrText {
	unused Bool = false
}

fn var StderrText.write(move value String) Void! {
	msrt_io_write_stderr(value)
}

fn var StderrText.flush() Void! {
	return ok()
}

fn move StderrText.close() Void! {
	return ok()
}

type StderrBytes {
	unused Bool = false
}

fn var StderrBytes.write(move value Bytes) Void! {
	msrt_io_write_bytes_stderr(value)
}

fn var StderrBytes.flush() Void! {
	return ok()
}

fn move StderrBytes.close() Void! {
	return ok()
}

// Standard output as text.
// ms: effect std.console.write
export fn stdout() WriteStream[String] {
	return WriteStream[String](StdoutText())
}

// Standard output as bytes; it shares its buffer with `stdout()`.
// ms: effect std.console.write
export fn stdout_bytes() WriteStream[Bytes] {
	return WriteStream[Bytes](StdoutBytes())
}

// Standard error as text.
// ms: effect std.console.write
export fn stderr() WriteStream[String] {
	return WriteStream[String](StderrText())
}

// Standard error as bytes.
// ms: effect std.console.write
export fn stderr_bytes() WriteStream[Bytes] {
	return WriteStream[Bytes](StderrBytes())
}

// ---- Pipes ---------------------------------------------------------------------------------------------------------

// Internal: the next value of pipe `id`, waiting when needed; `null` once every writer
// has closed.
fn pipe_next[T](id Int) T?! {
	// Fast path: a queued value or the end needs no promise.
	queued := msrt_pipe_try[T](id)
	if queued != null { return ok(queued) }
	if msrt_pipe_ended(id) == 1 { return ok(null) }

	if msrt_pipe_brief_wait(id) == 1 {
		queued := msrt_pipe_try[T](id)
		if queued != null { return ok(queued) }
	}

	p := msrt_pipe_read(id)
	code := msrt_promise_wait(p, -1)

	if code != 0 {
		msrt_promise_drop(p)
		return error(Error("pipe: read cancelled", kind: "ECANCELED"))
	}

	value := msrt_promise_take[T](p)
	msrt_promise_drop(p)
	return ok(value)
}

// The reading end of a pipe: the one reader, ended by the last writer closing.
type PipeSource[T] {
	id Int
}

fn var PipeSource[T].next() move T?! {
	return pipe_next[T](self.id)
}

fn move PipeSource[T].close() Void! {
	msrt_pipe_close_reader(self.id)
	self.id = 0
}

// One writing end of a pipe; closing it releases that writer.
type PipeSink[T] {
	id, capacity Int
}

fn var PipeSink[T].write(move value T) Void! {
	status := msrt_pipe_write[T](self.id, value)
	if status == 1 { return error(Error("pipe: the reader is gone", kind: "EBADF")) }

	// Back pressure: status 2 says the pipe is above its capacity; the writer waits
	// for the reader to take it back down.
	if status == 2 { return adopt[Void](msrt_pipe_flush(self.id)).wait() }
}

fn var PipeSink[T].flush() Void! {
	return adopt[Void](msrt_pipe_flush(self.id)).wait()
}

fn move PipeSink[T].close() Void! {
	// Closing again releases nothing: an owner that closed the writer by hand is
	// closed again at scope end.
	msrt_pipe_close_writer(self.id)
	self.id = 0
}

// An in-memory stream of whole values, in order, with any number of writers and one
// reader. A write hands the pipe the value: a plain value is copied, and a resource
// such as a `WriteStream` moves in, so a request can carry the way to answer it.
//
// `capacity` is the number of queued values above which a writer's `write` and `flush`
// wait. The pipe itself is not a writer: the reader ends once every writer from
// `writer()` has closed, so make the writers before reading. Closing the reader makes
// later writes fail with `EBADF`.
export opaque type Pipe[T] {
	// The runtime pipe's id.
	id Int
	// The queued values above which a write waits.
	capacity Int
	// Whether `reader` has handed out the reading end.
	taken Bool
}

// Returns a new writing end, like `dup` on a descriptor. Close it when done: the
// reader ends when every writer has closed. It is safe to call from a promise that
// owns the pipe, since each call makes a writer of its own.
fn Pipe[T].writer() move WriteStream[T] {
	msrt_pipe_add_writer(self.id)
	return WriteStream[T](PipeSink[T](self.id, self.capacity))
}

// Returns the reading end. A pipe has only one: later calls return a stream that is
// already at its end.
fn var Pipe[T].reader() ReadStream[T] {
	if self.taken { return ReadStream[T](PipeSource[T](0)) }

	self.taken = true
	return ReadStream[T](PipeSource[T](self.id))
}

// Waits for the next value; returns `null` once every writer has closed. Unlike
// `reader()`, it takes no stream, so a consumer that only borrows the pipe, such as a
// promise, can use it. Use it instead of `reader()`, never together with it.
fn Pipe[T].receive() T?! {
	return pipe_next[T](self.id)
}

// Releases the reading end if `reader()` was never called.
fn move Pipe[T].close() Void! {
	if not self.taken {
		msrt_pipe_close_reader(self.id)
	}
}

// Makes an in-memory pipe whose writers wait while more than `capacity` values are
// queued.
export fn pipe[T](capacity Int) Pipe[T] {
	id := msrt_pipe_new(capacity)

	// The runtime starts a pipe with one writer, which the Pipe value would hold;
	// writers come from `writer()` instead.
	msrt_pipe_close_writer(id)
	return Pipe[T](id: id, capacity: capacity, taken: false)
}

// ---- Transforms ----------------------------------------------------------------------------------------------------

// Turns each input item into zero or more output items, then emits anything held
// back at the end. A custom step may wait.
export interface Transform[A, B] {
	// Takes one input item and appends to `out` the output items it completes, possibly
	// null.
	var fn step(move value A, var out List[B]) Void!
	// Called once at the end of the input; appends any held-back items to `out`.
	var fn finish(var out List[B]) Void!
}

// A transform over a stream: its output collects in `out`, reversed after each step so
// `pop` moves the next one out.
type Through[A, B] {
	input ReadStream[A]
	transform Transform[A, B]
	out List[B]
	finished Bool
}

fn var Through[A, B].next() move B?! {
	while true {
		item := self.out.pop()
		if item != null { return ok(item) }
		if self.finished { return ok(null) }

		step := self.input.next()?
		var wrote Void! = ok()
		value := step

		if value != null {
			wrote = self.transform.step(value, self.out)
		} else {
			self.finished = true
			wrote = self.transform.finish(self.out)
		}

		// A failed step's partial output is dropped, so the failure is the next
		// item.
		if wrote.is_error() {
			self.out = []
			return error(wrote.err().clone())
		}

		if self.out.length() > 1 { self.out.reverse() }
	}

	return ok(null)
}

fn move Through[A, B].close() Void! {
	return self.input.close()
}

// Returns a stream of `transform`'s output over `input`. Closing it closes `input`.
export fn through[A, B](
	move input ReadStream[A],
	move transform Transform[A, B],
) ReadStream[B] {
	return ReadStream[B](Through[A, B](input, transform, [], false))
}

// ---- Process streams -----------------------------------------------------------------------------------------------

// One of this process's three standard streams.
export enum StdStream {
	Input  // Standard input; once redirected it reads as end of file.
	Output  // Standard output; once redirected its writes are discarded.
	Error  // Standard error; once redirected its writes are discarded.
}

// Points one of the process's own standard streams at the null device (`/dev/null`,
// or `NUL` on Windows): input reads as end of file and output is discarded. This
// replaces the descriptor itself, so it also affects child processes started
// afterwards that inherit it. Buffered standard output is written first. The change
// cannot be undone.
// ms: effect std.console.write
export fn redirect_to_null(stream StdStream) Void! {
	var which = 2

	match stream {
		Input => which = 0
		Output => which = 1
		Error => which = 2
	}

	return msstd_io_redirect_null(which)
}
