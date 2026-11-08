[Wiki](../index.md) › [Runtime](index.md)

# Runtime guard exits skip native Rust destructors

Verified: production `msrt_guard_call` exits faults and cancellation with a jump, so a Rust
`Drop` guard alone cannot release a response body's active read. Register a runtime cleanup
for state removed across a park; discard it on ordinary return. Interrupted decoders are
closed and abandoned rather than resumed with potentially partial state.

Apply when: native operations take state or resource ownership across a cancellable wait.
Evidence: [response body guard and cancellation regression](../../crates/ms-std-net/src/http/client.rs), [runtime guard](../../crates/ms-rt/src/fault.rs).
Verify: `make leak-check` on `tests/conformance/fixtures/e2e/stdlib/tasks-cancel-release.ms` reports zero live blocks; use the production runtime dependency (not `ms-rt`'s own unwinding unit-test guard), assert a stack destructor is skipped, join reports cancellation, later reads return Closed, and the peer observes connection release.

Same class, found by a soak (client aborts mid-body leaked ~1 fd per few hundred connections): a server exchange held an `Rc<dyn Io>` clone across `wait_fd`, so a handler cancelled while parked kept the socket open after `close_conn`. `HeldIo` in `http/exchange.rs` owns that clone through a cleanup. The client's shared 64 KiB read buffer, taken out of its thread-local for the read, leaked once per fetch cancelled by a timeout (`rt::Parked<T>`, aliased `ParkedBuf` for buffers, now frees it through a cleanup).

The same applies to the request itself: `Client::send` owned its method, URLs, header vectors and pool key in locals, about 340 B per cancelled fetch (#3008). They now live in one `Sending` struct behind `rt::Parked`, and the helpers borrow from it. Measure with `memory_usage().heap_used` over thousands of cancels; `tests/e2e/testdata/stdlib/http-fault-leak.ms` pins it. `make leak-check` cannot see either (Rust heap, not `ms-rt` blocks): count `/proc/<pid>/fd` under load instead.

Main-isolate scheduler state is a `ManuallyDrop` thread-local; `run_main` calls `task::teardown()` in every build so valgrind sees no definite losses in an empty program (#2470). Check new per-isolate state is released there.
