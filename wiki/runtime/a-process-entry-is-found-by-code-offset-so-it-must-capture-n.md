[Wiki](../index.md) › [Runtime](index.md)

# A process entry is found by code offset, so it must capture nothing

Decided: `ProcessGroup.spawn` passes `lambda: serve(entry)` to `msstd_process_fork`, which reads the runner's and the entry's code and drop words and sends them as offsets from `msrt_start` in `MS_ENTRY`. The child rebuilds both closures before `main`. This needs no entry table in the compiler, but only a closure without captures can be rebuilt, so the checker requires the entry to name a top-level `def`.

Apply when: changing closure layout, `ProcessGroup.spawn`, the runner, or the JSON handling of `Unit`.
Evidence: [start hook](../../crates/ms-rt/src/start.rs), [fork natives](../../crates/ms-std-process/src/fork.rs), [processes module](../../stdlib/os/processes.ms), [fixture](../../tests/conformance/fixtures/e2e/stdlib/processes.ms), [reject fixture](../../tests/conformance/fixtures/e2e/reject/process-entry-lambda.ms).
Verify: the processes fixture passes under `ms test`; a lambda entry is rejected by `ms check`.
