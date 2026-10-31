[Wiki](../index.md) › [Runtime](index.md)

# Cancellation is a host-level flag, not a per-loop poll

Decision: cancellation is one global flag (set by signals, shutdown, and task-group cancellation; see the tasks and workers entries for scoped cancellation) checked by runtime calls and I/O, not on loop back edges ([design contract](../../crates/DESIGN.md)). A helper that runs in constant time (Optional/Result extraction, builder append) must not check cancellation; keep the check in helpers that loop, wait, or call user callbacks.

Apply when: adding a runtime function, or deciding where a function should be a cancellation point.
Evidence: [design contract](../../crates/DESIGN.md), [shutdown fixtures](../../tests/e2e/testdata/shutdown/server.source), [signal project](../../tests/e2e/testdata/projects/signal).
Verify: loop and I/O cancellation cases still stop; compare `bench/perf/programs/run.sh` before and after.
