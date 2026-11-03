import Bytes from "@std/bytes.ms"

// Runtime promise slots (crates/ms-rt/src/promise.rs). Ids carry a generation: a stale id never matches.
// Outcome codes of msrt_promise_wait: 0 ok, 1 the operation's own error, 2 timed out, 3 cancelled,
// 4 closed (the result was already taken), 5 failed (a fault inside).

export extern fn msrt_promise_new() Int

export extern fn msrt_promise_put[T](id: Int, value: T, failed: Int) Unit

export extern fn msrt_promise_take[T](id: Int) T?

export extern fn msrt_promise_done(id: Int) Bool

export extern fn msrt_promise_start(id: Int, work: fn() Unit) Unit

export extern fn msrt_promise_wait(id: Int, timeout_ns: Int) Int

// The index of the first of `ids` to finish, waiting up to `timeout_ns` (negative: no limit); -1 on timeout.
export extern fn msrt_promise_wait_any(ids: List[Int], timeout_ns: Int) Int

export extern fn msrt_promise_fault_report(id: Int) String

export extern fn msrt_promise_drop(id: Int) Unit

// A promise that finishes after `ns` nanoseconds; it has no task. Wait with code 0.
export extern fn msrt_promise_sleep(ns: Int) Int

// A promise for the readiness of a descriptor (events: 1 read, 2 write) that finishes with an
// Int of the ready bits (8 for a timeout; `timeout_ns` negative means none). -1 when the
// descriptor cannot be waited on.
export extern fn msrt_promise_ready(fd: Int, events: Int, timeout_ns: Int) Int

// In-memory pipes (crates/ms-rt/src/pipes.rs). A pipe starts with one writer, the Pipe value itself.
export extern fn msrt_pipes_new(capacity: Int) Int

// Another writing end.
export extern fn msrt_pipes_add_writer(pipe: Int) Unit

// Moves a value in; 0 written, 1 the reader is gone (the value is dropped). Never waits.
export extern fn msrt_pipes_write[T](pipe: Int, value: T) Int

// A promise for the next value (take it with msrt_promise_take[T]); finishes with no value at the end.
export extern fn msrt_pipes_read(pipe: Int) Int

// A promise that finishes when no more than `capacity` values are queued, or the reader is gone.
export extern fn msrt_pipes_flush(pipe: Int) Int

export extern fn msrt_pipes_buffered(pipe: Int) Int

export extern fn msrt_pipes_close_writer(pipe: Int) Unit

export extern fn msrt_pipes_close_reader(pipe: Int) Unit

// The native stream table (crates/ms-rt/src/streams.rs): descriptor-backed byte streams.
// Flags of msrt_streams_open: 1 reads, 2 writes, 4 closing the stream closes the descriptor.
export extern fn msrt_streams_open(fd: Int, flags: Int) Int

// A promise for the next chunk (take it with msrt_promise_take[Bytes]); no value at the end or after a failure.
export extern fn msrt_streams_read(stream: Int) Int

// Appends to the write buffer; 0 taken, 1 the stream is closed or not writable. Never waits.
export extern fn msrt_streams_write(stream: Int, data: Bytes) Int

// A promise that finishes when the write buffer has drained.
export extern fn msrt_streams_flush(stream: Int) Int

export extern fn msrt_streams_buffered(stream: Int) Int

// The message of the failure that ended the last operation, or an empty string.
export extern fn msrt_streams_error(stream: Int) String

export extern fn msrt_streams_close(stream: Int) Unit

// Makes the new promise `id` one whose work runs in the first task that waits on it.
export extern fn msrt_promise_defer(id: Int, work: fn() Unit) Unit

// Cells (crates/ms-rt/src/cells.rs): one owned value parked in the runtime, so a closure carries only the id.
export extern fn msrt_cells_new[T](value: T) Int

// Moves the value out; none when the cell is empty (a user has it) or gone.
export extern fn msrt_cells_take[T](id: Int) T?

export extern fn msrt_cells_put[T](id: Int, value: T) Unit

export extern fn msrt_cells_drop(id: Int) Unit

// Whether the cell holds a value now.
export extern fn msrt_cells_full(id: Int) Bool

// Moves the value out; Closed when the cell is empty or gone. A plain `try` binds it without a copy.
export extern fn msrt_cells_take_result[T](id: Int) T!

// An already finished promise with no value.
export extern fn msrt_promise_finished() Int

// The process-wide output buffers (crates/ms-rt/src/io.rs); standard output is flushed at exit.
export extern fn msrt_io_write_stdout(text: String) Unit

export extern fn msrt_io_write_stderr(text: String) Unit

export extern fn msrt_io_write_bytes_stdout(data: Bytes) Unit

export extern fn msrt_io_write_bytes_stderr(data: Bytes) Unit

export extern fn msrt_io_flush() Unit
