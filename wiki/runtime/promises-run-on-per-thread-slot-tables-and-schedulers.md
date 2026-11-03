[Wiki](../index.md) › [Runtime](index.md)

# Promises live in per-thread slot tables; threads exchange events

Verified: a promise id is `thread<<56 | generation<<32 | index+1`. The creating thread owns the slot columns (state, token, result, closure, timers); other threads never touch them and send `Started`, `Done`, `Ended` and `Cancel` events through the target thread's mail. I/O promises (sleep, fd readiness, native `io_on_ready` continuations) have no task. A `promise(fn:)` task retains its closure until `Ended`, so dropping a promise cancels, joins, then frees. `KEPT_CALLBACKS` and the MIR unwind `SPAWNERS` list must name every extern that keeps a callback, or the closure is freed early and cancelled tasks leak stack values.

Verified: load is a thread's live promise tasks plus queued starts, and only a thread with no live task takes unstarted work. Counting only ready tasks let a thread full of sleepers take a CPU-bound promise, and its sleepers then overshot by the whole spin (about 600 ms against 3 ms). Tests that expect spreading must keep promises busy, because a sleeping promise does not make its thread busy.

Verified: a native that blocks hands its work to the blocking pool itself (`pool::run`, `fs` `offload`, net `wait`) when other tasks share its thread, and this works from scheduler threads. There is no declared blocking marker on externs; a Rust name list or a new keyword was not needed. Terminal natives stay on the main thread (`Global::get`); the system inventory is per thread.

Apply when: changing `promise.rs`, `sched.rs`, `pipes.rs`, the poller, or adding a native that completes a promise.
Evidence: `crates/ms-rt/src/promise.rs` tests (spread, steal, remote cancel, remote fault, pool jobs from scheduler threads); `tools/leak-check.ms` on cancel and fault programs.
Verify: `cargo test -p ms-rt --lib` repeated; leak-check clean after a dropped running promise.
