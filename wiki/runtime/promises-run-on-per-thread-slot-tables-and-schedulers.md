[Wiki](../index.md) › [Runtime](index.md)

# Promises live in per-thread slot tables; threads exchange events

Verified: a promise id is `thread<<56 | generation<<32 | index+1`. The creating thread owns the slot columns (state, token, result, closure, timers); other threads never touch them and send `Started`, `Done`, `Ended` and `Cancel` events through the target thread's mail. I/O promises (sleep, fd readiness, native `io_on_ready` continuations) have no task. A `promise(fn:)` task owns the closure it is handed (the MIR extern parameter is `own`; nothing retains it) until `Ended`, so dropping a promise cancels, joins, then frees.

Function values a native keeps (`KEPT_CALLBACKS` in `ms-check/src/stdlib.rs`: `msrt_promise_start`, `msrt_promise_defer`, `msstd_http_serving_new`) are handed over, not lent: `rtcall::hands_over` marks the `*mut Closure` (or `env`) parameter `own` in the MIR extern and lowering passes an owned value, and the runtime drops the closure once when the task ends, the deferred work runs, or the serving drops. The runtime never retains such an argument, and a runtime-side creator (`promise::start_native`, the pipe tests) hands its fresh closure over without a release of its own. A retain in the runtime paired with a borrowed MIR parameter was the old refcount pattern; the valgrind signature of getting this wrong is a use-after-free in `task::closure_entry` / `promise::native_code`. `KEPT_CALLBACKS` and the MIR unwind `SPAWNERS` list must name every extern that keeps a callback, or the closure is freed early and cancelled tasks leak stack values.

Verified: load is a thread's live promise tasks plus queued starts, and only a thread with no live task takes unstarted work. Counting only ready tasks let a thread full of sleepers take a CPU-bound promise, and its sleepers then overshot by the whole spin (about 600 ms against 3 ms). Tests that expect spreading must keep promises busy, because a sleeping promise does not make its thread busy.

Apply when: changing `promise.rs`, `sched.rs`, `pipes.rs`, the poller, or adding a native that completes a promise.
Evidence: `crates/ms-rt/src/promise.rs` tests (spread, steal, remote cancel, remote fault, pool jobs from scheduler threads); `tools/leak-check.ms` on cancel and fault programs.
Verify: `cargo test -p ms-rt --lib` repeated; leak-check clean after a dropped running promise.
