import Bytes from "@std/bytes.ms"

// Runtime promise slots (crates/ms-rt/src/promise.rs). Ids carry a generation: a stale
// id never matches. Outcome codes of msrt_promise_wait: 0 ok, 1 the operation's own
// error, 2 timed out, 3 cancelled, 4 closed (the result was already taken), 5 failed (a
// fault inside).

export extern fn msrt_promise_new() Int

export extern fn msrt_promise_put[T](id: Int, value: T, failed: Int) Unit

export extern fn msrt_promise_take[T](id: Int) T?

export extern fn msrt_promise_done(id: Int) Bool

export extern fn msrt_promise_run_unstarted(id: Int) Bool

export extern fn msrt_promise_start(id: Int, work: fn() Unit) Unit

// As `msrt_promise_start`, but always on the calling thread.
export extern fn msrt_promise_start_here(id: Int, work: fn() Unit) Unit

// As `msrt_promise_start`, but on the least loaded thread.
export extern fn msrt_promise_start_spread(id: Int, work: fn() Unit) Unit

export extern fn msrt_promise_wait(id: Int, timeout_ns: Int) Int

// Limits the promise: once `timeout_ns` has passed from now without a result it is
// cancelled and a wait reports a timeout.
export extern fn msrt_promise_limit(id: Int, timeout_ns: Int) Unit

// Cancels the promise if it has not finished; a wait then reports a cancellation. It
// does not wait.
export extern fn msrt_promise_cancel(id: Int) Unit

// Makes the promise listen to the cancel switch: when it fires the promise is
// cancelled. Call it once the work has started.
export extern fn msrt_promise_on_cancel(id: Int, cancel: Int) Unit

// A new cancel switch that has not fired, as an id.
export extern fn msrt_cancel_new() Int

// Fires the switch: every promise listening to it is cancelled. Firing twice does
// nothing.
export extern fn msrt_cancel_fire(id: Int) Unit

// Whether the switch has fired; a freed switch reads as not fired.
export extern fn msrt_cancel_fired(id: Int) Bool

// Frees the switch; the promises that listened keep running.
export extern fn msrt_cancel_free(id: Int) Unit

// The index of the first of `ids` to finish, waiting up to `timeout_ns` (negative: no
// limit); -1 on timeout.
export extern fn msrt_promise_wait_any(ids: List[Int], timeout_ns: Int) Int

export extern fn msrt_promise_fault_report(id: Int) String

export extern fn msrt_promise_drop(id: Int) Unit

// A promise that finishes after `ns` nanoseconds; it has no task. Wait with code 0.
export extern fn msrt_promise_sleep(ns: Int) Int

// In-memory pipes (crates/ms-rt/src/pipes.rs). A pipe starts with one writer, the Pipe
// value itself.
export extern fn msrt_pipe_new(capacity: Int) Int

// Another writing end.
export extern fn msrt_pipe_add_writer(pipe: Int) Unit

// Moves a value in; 0 written, 1 the reader is gone (the value is dropped). Never
// waits.
export extern fn msrt_pipe_write[T](pipe: Int, value: T) Int

// A promise for the next value (take it with msrt_promise_take[T]); finishes with no
// value at the end.
export extern fn msrt_pipe_read(pipe: Int) Int

// The next queued value without a promise; none when nothing is queued right now.
export extern fn msrt_pipe_try[T](pipe: Int) T?

// 1 when a read would end with no value: every writer closed and nothing is queued.
export extern fn msrt_pipe_ended(pipe: Int) Int

// A promise that finishes when no more than `capacity` values are queued, or the reader
// is gone.
export extern fn msrt_pipe_flush(pipe: Int) Int

export extern fn msrt_pipe_close_writer(pipe: Int) Unit

export extern fn msrt_pipe_close_reader(pipe: Int) Unit

// The native stream table (crates/ms-rt/src/streams.rs): descriptor-backed byte
// streams. Flags of msrt_streams_open: 1 reads, 2 writes, 4 closing the stream closes
// the descriptor.
export extern fn msrt_streams_open(fd: Int, flags: Int) Int

// A promise for the next chunk (take it with msrt_promise_take[Bytes]); no value at the
// end or after a failure.
export extern fn msrt_streams_read(stream: Int) Int

// Queues bytes; 0 admitted, 1 closed or not writable. Check msrt_streams_error for
// terminal write failures. Never waits.
export extern fn msrt_streams_write(stream: Int, data: Bytes) Int

// A promise that finishes when the write buffer has drained.
export extern fn msrt_streams_flush(stream: Int) Int

export extern fn msrt_streams_buffered(stream: Int) Int

// The last read failure or the terminal write failure (retained until close), or an
// empty string.
export extern fn msrt_streams_error(stream: Int) String

export extern fn msrt_streams_close(stream: Int) Unit

// Makes the new promise `id` one whose work runs in the first task that waits on it.
export extern fn msrt_promise_defer(id: Int, work: fn() Unit) Unit

// An already finished promise with no value.
export extern fn msrt_promise_finished() Int

// The process-wide output buffers (crates/ms-rt/src/io.rs); standard output is flushed
// at exit.
export extern fn msrt_io_write_stdout(text: String) Unit

export extern fn msrt_io_write_stderr(text: String) Unit

export extern fn msrt_io_write_bytes_stdout(data: Bytes) Unit

export extern fn msrt_io_write_bytes_stderr(data: Bytes) Unit

export extern fn msrt_io_flush() Unit

// Bounds every wait of the running task until it is restored: none lasts past
// `timeout_ns` in all, and one that reaches it reports a timeout to its caller. A bound
// already in force stays when it ends sooner. Returns the previous limit.
export extern fn msrt_task_read_limit(timeout_ns: Int) Int

// Puts back the limit `msrt_task_read_limit` returned.
export extern fn msrt_task_read_limit_restore(previous: Int) Unit
