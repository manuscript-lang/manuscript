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
export extern fn msrt_pipe_new(capacity: Int) Int

// Another writing end.
export extern fn msrt_pipe_add_writer(pipe: Int) Unit

// Moves a value in; 0 written, 1 the reader is gone (the value is dropped). Never waits.
export extern fn msrt_pipe_write[T](pipe: Int, value: T) Int

// A promise for the next value (take it with msrt_promise_take[T]); finishes with no value at the end.
export extern fn msrt_pipe_read(pipe: Int) Int

// A promise that finishes when no more than `capacity` values are queued, or the reader is gone.
export extern fn msrt_pipe_flush(pipe: Int) Int

export extern fn msrt_pipe_buffered(pipe: Int) Int

export extern fn msrt_pipe_close_writer(pipe: Int) Unit

export extern fn msrt_pipe_close_reader(pipe: Int) Unit
