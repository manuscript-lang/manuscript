[Wiki](../index.md) › [Runtime](index.md)

# Worker threads are isolates that share nothing

Decision (owner, 2026-10-24): workers follow the `worker_threads` model: an OS thread with its own isolate, started from a named top-level `def`, talking to its starter over a `Channel` whose transport is an in-memory pipe of JSON messages. No sendable concept for users; the compiler rejects lambdas and captures as entries, and JSON encoding rejects handles, resources and `Shared`.

Apply when: adding a process-wide `static`, a cache, or a standard-library feature that keeps state outside the isolate.
Evidence: `proposals/worker-threads.md`; measured scaling 1.8x on two workers and 3.0x on four (`fib(38)` x8); allocator thread-local state cost +0.04% instructions on the program suite.
Verify: every runtime `static` is an atomic, a `Process` cell (main isolate only), or an `isolate_static!`.
