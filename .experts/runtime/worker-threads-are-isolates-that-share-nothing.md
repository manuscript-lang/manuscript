[Wiki](../index.md) › [Runtime](index.md)

# Worker threads are isolates that share nothing

Decision (owner, 2026-10-24): workers follow the `worker_threads` model: an OS thread with its own isolate, started from a named top-level `def`, talking to its starter over a `Channel` whose transport is an in-memory pipe of JSON messages. No sendable concept for users; the compiler rejects lambdas and captures as entries, and JSON encoding rejects handles, resources and `Shared`.

Apply when: adding a process-wide `static`, a cache, or a standard-library feature that keeps state outside the isolate.
Evidence: `proposals/worker-threads.md`; measured scaling 1.8x on two workers and 3.0x on four (`fib(38)` x8); allocator thread-local state cost +0.04% instructions on the program suite.
Verify: every runtime `static` is an atomic, a `Process` cell (main isolate only), or an `isolate_static!`. Rust code in a worker uses the system allocator, because an arena ends with its worker and Rust code can keep an allocation in a cache another isolate reads (a `Vec` in a worker arena behind a process-wide `OnceLock` was a use-after-free). `Global<T>` in `ms-std-*` faults in a worker. Worker stdout writes bypass the main isolate's buffer. Windows reaches the task header through `msrt_isolate_hdr`, a call, because fibers cannot be aligned.

Verified: the worker must close the pipe end transferred in its startup argument. Publishing
that end from the parent after thread creation races with an immediate worker exit and leaks
the end, preventing the peer from seeing closure. The worker's own `END` state owns this
cleanup. `worker_closes_pipe_before_parent_publishes_handle_metadata` reproduces the ordering.

---
Topics: [Concurrency and cancellation](../topics/concurrency-and-cancellation.md)
