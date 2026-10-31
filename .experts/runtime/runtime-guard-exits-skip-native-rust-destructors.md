[Wiki](../index.md) › [Runtime](index.md)

# Runtime guard exits skip native Rust destructors

Verified: production `msrt_guard_call` exits faults and cancellation with a jump, so a Rust
`Drop` guard alone cannot release a response body's active read. Register a runtime cleanup
for state removed across a park; discard it on ordinary return. Interrupted decoders are
closed and abandoned rather than resumed with potentially partial state.

Decision (#1217): Manuscript frames get the same treatment automatically. `ms_mir::unwind` runs after the optimizer in every profile and, for programs that start tasks, workers or servers, registers one cleanup per owned value live across each call that can reach a cancellation point (`msrt_cleanup_discard` after the call). The cleanup drops only while `msrt_unwind_drops` is true, which `msrt_cancelled` sets when a guard will catch the jump; faults and process exit free nothing. A value moved out of a field and not yet refilled, or held in a stack slot, is skipped (it leaks rather than double frees). Rust natives use `ms_rt::fault::with_cleanup(&mut cleanup, body)` around a park that holds a borrow or flag.

Apply when: native operations take state or resource ownership across a cancellable wait.
Evidence: [response body guard and cancellation regression](../../crates/ms-std-net/src/http/client.rs), [runtime guard](../../crates/ms-rt/src/fault.rs).
Verify: `make leak-check` on `tests/conformance/fixtures/e2e/stdlib/tasks-cancel-release.ms` reports zero live blocks; use the production runtime dependency (not `ms-rt`'s own unwinding unit-test guard),
assert a stack destructor is skipped, join reports cancellation, later reads return Closed,
and the peer observes connection release.

---
Topics: [Concurrency and cancellation](../topics/concurrency-and-cancellation.md) · [Cleanup and resources](../topics/cleanup-and-resources.md)
