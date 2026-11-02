[Wiki](../index.md) › [Runtime](index.md)

# Sync and timer needs are idioms over tasks, not new APIs

Decision (Chinmay, 2026-11-01): match Go's capability, not its API. Tasks share one thread, so `sync/atomic` and `WaitGroup` have no counterpart: use `Shared[Int]` with `lock` and `TaskGroup.wait`. Only `once()`, `deadline_after`, `ticker` and error `wrap`/`join` were missing and are added in `.ms`.

Failure mode: a function that returns an `Error` view recovered by `match` through recursion (`root_cause`) crashes or returns garbage, so no cause-chain walker exists; match on `ContextError` instead.

Apply when: adding sync, timer or error helpers.
Evidence: [fixture](../../tests/e2e/testdata/stdlib/sync-timers-errors.ms).
Verify: that fixture passes.
