# Runtime promise slots (crates/ms-rt/src/promise.rs). Ids carry a generation: a stale id never matches.
# Outcome codes of msrt_promise_wait: 0 ok, 1 the operation's own error, 2 timed out, 3 cancelled,
# 4 closed (the result was already taken), 5 failed (a fault inside).

export extern fn msrt_promise_new() Int

export extern fn msrt_promise_put[T](id: Int, value: T, failed: Int) Unit

export extern fn msrt_promise_take[T](id: Int) T?

export extern fn msrt_promise_done(id: Int) Bool

export extern fn msrt_promise_start(id: Int, work: fn() Unit) Unit

export extern fn msrt_promise_wait(id: Int, timeout_ns: Int) Int

export extern fn msrt_promise_fault_report(id: Int) String

export extern fn msrt_promise_drop(id: Int) Unit
