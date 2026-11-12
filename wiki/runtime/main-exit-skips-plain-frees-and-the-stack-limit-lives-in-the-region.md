[Wiki](../index.md) › [Runtime](index.md)

# `main` skips plain frees at exit, and the stack limit lives in the region

Verified (2026-11-12, `bench/perf/structural-gaps`): freeing a 500k-entry map when `main` returns cost 45 to 70 ms of a 211 to 243 ms program. `ms_mir::exit_drops` gates the drops on `main`'s return paths whose type is plain memory behind `msrt_exit_frees`; the counting runtime (`ms-rt/stats`, so `make leak-check`) and `MS_FREE_AT_EXIT=1` keep them. A closure, an interface value or an opaque handle is never gated (`Module::drops_plain_memory`), and a `main` that something calls again keeps every drop. Add a type that closes something to the not-plain side, never to the list of plain ones.

The recursion check reads the limit from the region word beside the task block's address (`STACK_LIMIT_CELL`), one load from the masked stack pointer. Every writer of `Hdr::limit` must follow with `task::publish_limit()` (fault depth reserve, guard exit, segment grow and return); `publish_region` rewrites every segment's cell when a task is switched in, because tasks share a region's slots. A new place that changes the limit without publishing it makes the check use a stale value: too high faults early, too low skips the grow.

A small directly self-recursive function is unrolled once into itself by the MIR inliner (`self_unroll_source`): the copies have no check or frame, so `fib(32)` fell from 137.8M to 98.4M instructions. Fault frames are compared by text because the copy's scope names its function by another table offset; the report's walk spends one step per logical frame, so inlining never changes how deep a diagnostic reaches.

Evidence: [`exit_drops.rs`](../../crates/ms-mir/src/exit_drops.rs), [`task.rs`](../../crates/ms-rt/src/task.rs), fixture `e2e/accept/main-exit-closes-resources`.

A recursive cycle keeps one stack check: `strip_depth` keeps it on the targets of the depth-first back edges only (`cycle_breakers`) and runs before and after inlining, so the unchecked functions on a cycle inline into their callers. Anything that inlines a checked function into an unchecked one would leave a cycle with no check; the inliner never inlines a function that still opens with `depth.enter`.
