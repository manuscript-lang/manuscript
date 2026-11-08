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

A promise's closure is dropped when its task ends, which closes what it captured. That drop runs shielded (`promise::task_ended`): a task ended by a cancel still has the cancel pending, and a close that parks (a WebSocket's close frame) would otherwise re-enter `msrt_cancelled` with no guard and exit the program with 143 (#3041).

The HTTP/2 client had the same gap: a request cancelled while waiting for its response left its `H2Stream` open on the shared connection (never reset), so after about a hundred cancels the peer's stream limit was full and later requests on that connection timed out, and its request headers leaked. `exchange_h2` now holds the stream and headers in `rt::Parked`; `tests/e2e/testdata/stdlib/http2-cancelled-requests.ms` pins both. A smaller residual of about 15 B per cancelled request remains after a redirect hop or on h2; its source is not located.
