[Wiki](../index.md) › [Runtime](index.md)

# Runtime guard exits skip native Rust destructors

Verified: production `msrt_guard_call` exits faults and cancellation with a jump, so a Rust
`Drop` guard alone cannot release a response body's active read. Register a runtime cleanup
for state removed across a park; discard it on ordinary return. Interrupted decoders are
closed and abandoned rather than resumed with potentially partial state.

Apply when: native operations take state or resource ownership across a cancellable wait.
Evidence: [response body guard and cancellation regression](../../crates/ms-std-net/src/http/client.rs), [runtime guard](../../crates/ms-rt/src/fault.rs).
Verify: `make leak-check` on `tests/conformance/fixtures/e2e/stdlib/tasks-cancel-release.ms` reports zero live blocks; use the production runtime dependency (not `ms-rt`'s own unwinding unit-test guard), assert a stack destructor is skipped, join reports cancellation, later reads return Closed, and the peer observes connection release.
