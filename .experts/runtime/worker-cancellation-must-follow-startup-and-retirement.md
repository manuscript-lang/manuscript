[Wiki](../index.md) › [Runtime](index.md)

# Worker cancellation must follow startup and retirement

Verified: a cancellation sent immediately after spawn was discarded before the worker published
its isolate slot. A completed, unjoined worker retained that slot and could cancel a later worker
that reused it. Keep the request in the worker object, and serialize slot publication, cancellation,
and retirement before task teardown. Generation-checking the public worker handle alone does not
protect the separately reused isolate slot.

Apply when: changing worker startup, cancellation or isolate retirement.
Evidence: [worker regressions](../../crates/ms-rt/src/worker.rs)
(`cancellation_immediately_after_spawn_is_remembered`,
`cancelling_completed_worker_does_not_cancel_reused_isolate`).
Verify: immediate cancellation ends the intended worker, and cancelling an exited worker leaves
its replacement running normally.

Verified: a park token's identity must outlive its isolate. Resetting token generations when
an isolate registry slot is reused lets a late completion wake a replacement worker. Preserve
per-slot generations in the registry across teardown, and retire exhausted token slots rather
than wrapping their generation. Retain generation numbers only, never values or waiters.
Apply when: changing token allocation, isolate retirement, or remote completion delivery.
Evidence: [worker retirement regression](../../crates/ms-rt/src/worker.rs)
(`late_posts_from_a_retired_isolate_do_not_wake_its_replacement`) and
[generation exhaustion regression](../../crates/ms-rt/src/task.rs)
(`an_exhausted_token_generation_does_not_revive_a_stale_id`).
Verify: `cargo nextest run -p ms-rt` passes both stale-post regressions.

Verified: `isolate_static!` suppresses thread-local destructors. Closing every group does not
release its scope-table buffers, and dropping a stack-pool vector would not unmap its stacks.
Scheduler retirement explicitly releases both; generation history needed by remote tokens stays
in the process registry instead. Check Rust heap storage as well as program allocations.
Apply when: adding isolate-local caches or changing worker/scheduler teardown.
Evidence: [mapping regression](../../crates/ms-rt/src/task.rs)
(`teardown_unmaps_pooled_task_stacks`) and
[Rust heap regression](../../crates/ms-rt/tests/scope_teardown.rs).
Verify: `cargo nextest run -p ms-rt` releases the mappings and reports zero retained table bytes.

---
Topics: [Concurrency and cancellation](../topics/concurrency-and-cancellation.md) · [Testing](../topics/testing.md)
