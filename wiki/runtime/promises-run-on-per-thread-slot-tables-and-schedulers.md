[Wiki](../index.md) › [Runtime](index.md)

# Promises live in per-thread slot tables; threads exchange events

Verified: a promise id is `thread<<56 | generation<<32 | index+1`. The creating thread owns the slot columns (state, token, result, closure, timers); other threads never touch them and send `Started`, `Done`, `Ended` and `Cancel` events through the target thread's mail. I/O promises (sleep, fd readiness, native `io_on_ready` continuations) have no task. A `promise(fn:)` task retains its closure until `Ended`, so dropping a promise cancels, joins, then frees. `KEPT_CALLBACKS` and the MIR unwind `SPAWNERS` list must name every extern that keeps a callback, or the closure is freed early and cancelled tasks leak stack values.

Apply when: changing `promise.rs`, `sched.rs`, `pipes.rs`, the poller, or adding a native that completes a promise.
Evidence: `crates/ms-rt/src/promise.rs` tests (spread, steal, remote cancel, remote fault, pool jobs from scheduler threads); `tools/leak-check.ms` on cancel and fault programs.
Verify: `cargo test -p ms-rt --lib` repeated; leak-check clean after a dropped running promise.
