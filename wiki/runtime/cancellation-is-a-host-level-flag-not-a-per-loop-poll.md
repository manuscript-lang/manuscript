[Wiki](../index.md) › [Runtime](index.md)

# Cancellation is a host-level flag, not a per-loop poll

Decision: cancellation is one global flag (set by signals, shutdown, and task-group cancellation; see the tasks and workers entries for scoped cancellation) checked by runtime calls and I/O, not on loop back edges ([design contract](../../crates/DESIGN.md)). A helper that runs in constant time (Optional/Result extraction, builder append) must not check cancellation; keep the check in helpers that loop, wait, or call user callbacks.

State that says "this task is unwinding" is per task (`Ctx` in `fault.rs`), never per thread: `UNWIND_DROPS` gates the drops generated cleanups run, and a cleanup that parks (joining a worker, closing a pipe) lets other tasks end, whose guard exit cleared the shared flag, so the cancelled task skipped its drops and leaked (#2671, an HTTP server closed with a request in flight left the accept loop's list). Fixture: `http-close-in-flight-frees-accept-loop`.

Apply when: adding a runtime function, or deciding where a function should be a cancellation point.
Evidence: [design contract](../../crates/DESIGN.md), [shutdown fixtures](../../tests/conformance/fixtures/e2e/shutdown/server.source), [signal project](../../tests/conformance/fixtures/e2e/projects/signal).
Verify: loop and I/O cancellation cases still stop; compare `ms run bench/tools/programs.ms --` before and after.
