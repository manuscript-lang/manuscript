# TaskGroup request scopes: contained child faults and a cancel query

Status: **stage 1 (contained faults, #1327) and stage 2 (`cancelled()`) implemented.** Closes the open item in `proposals/taskgroup.md` ("Catching a child fault in the parent instead of ending the program") and adds the one missing runtime query. Needed by the HTTP server roadmap (a per-request `TaskGroup`).

## Problem

A server wants one `TaskGroup` per request: the handler spawns children, waits, and leaves the `with` block; whatever is still running is cancelled. Three things stop that today.

1. **A child fault ends the program.** `msrt_scope_spawn` starts closure tasks with `SPAWN_FATAL`, and `task_main` calls `exit_with_report` (exit 67). A handler that spawns into a `TaskGroup` turns a 500 into process exit. The server already contains handler faults (`ffi/handler.rs`); children cannot be.
2. **No way to ask "am I cancelled?".** `rt::cancelled()` is `-> !` (it raises at once); the flag is visible only to Rust (`ms-std-net/src/rt.rs:36`). A task in a CPU loop with waits only now and then cannot poll and stop early or finish its response; it can only be unwound at its next wait.
3. **Kill timer.** `TaskGroup(timeout:)` and `spawn(timeout:)` already keep one kill deadline per limited task (`scope.rs`, `task.rs` `kill_at`), cancel at the deadline and report `TimedOut`. **Nothing new is needed for children.** What does not exist is a deadline on the *handler's own task* (the server timeout never cancels a running handler); that is a server change on top of the cancel query, not a TaskGroup change, and it stays out of this proposal.

## Design

**Contained faults (opt-in).** `TaskGroup[T](contain_faults: True)`. Default stays `False`: today's behavior, so no program changes meaning, and "a fault is never silently swallowed" remains the default. When on:

- Scope tasks start without `SPAWN_FATAL` (a scope flag set by a new `msrt_scope_contain(scope)`; `msrt_scope_spawn` keeps its signature).
- The task's cleanups run exactly as for a fatal fault (the guard already unwinds before reporting); only the final `exit_with_report` is skipped.
- `msrt_scope_join` and `msrt_scope_wait` return a new outcome `4` (faulted). `wait` reports 4 ahead of timed out/cancelled. The fault text is left in a one-slot runtime buffer; `msrt_scope_fault_message() -> String` takes it (single thread, no yield between the join and the read).
- `TaskError` gains `case Faulted(message: String)`, `message()` returns `task: fault: <text>`. The message is the full report, frames and `task started by:` included (`fault_report`), as `WorkerError.Faulted` and the server's 500 log carry it. A contained fault is not logged by the runtime; the caller decides.
- `join_closure` today maps every non-zero status to timed out or cancelled; it changes to map status 1 to outcome 4 and passes a message slot instead of discarding the text. `join` (collect) fills the buffer; `wait` (keep) peeks the text of the first faulted task in start order.
- A faulted task that is never collected is dropped by `close` without a log. The opted-in group owns that choice; the docs say so.
- Siblings are unaffected. `results()` returns the first error in start order, as today.
- Leak (fixed in #1325, `proposals/handler-fault-drops.md`): drop cleanups used to run only on cancellation unwinds, so values owned by the faulted task's frames leaked. A guarded fault now unwinds with drops.

Alternatives considered: always-on (a discarded `result()`, as in `tasks-fault.ms`, would turn exit 67 into a silent exit 0); re-raise the child's fault in the parent at `result`/`results`/`wait` (structured-concurrency style: no flag, no new case, the server's guard turns it into a 500 unchanged; rejected because a fault raised inside `close` becomes a cleanup fault, siblings' results are lost, and the parent cannot choose to continue); a separate `try_spawn` (two spawn shapes, and group-level `results()` would need both).

**Cancel query.** `@std/concurrency/tasks.ms`: `export def cancelled() -> Bool`, true once the current task was cancelled (closed group, timeout, program stop). One runtime symbol `msrt_task_cancel_requested() -> i64` reading the unshielded cancel flag (`unshielded_cancel_flag`), because the live flag reads 0 inside cleanups, exactly where a cancelled task wants to do minimal work; so it is also true inside cleanups. It is a plain query: it neither unwinds nor waits. Cooperative; a loop that never waits and never polls is still not stoppable, which the docs already say.

**Kill timer.** Unchanged. Tests pin that a group `timeout` cancels a child parked in a wait and that `cancelled()` is true inside it.

## Cost and benefit

- Rust: about 40 lines in `scope.rs`/`task.rs` (a scope flag, outcome 4, one message slot, one query symbol). Manuscript: about 25 lines in `tasks.ms`. No compiler change (externs with `String` returns exist).
- Benefit: unblocks per-request scopes (HTTP Stage 2+), and any program that wants to isolate failing work, e.g. a batch where one bad item faults. Today the only isolation is a process or worker.
- Do nothing: the server cannot offer per-request groups; users hand-roll `serve` handlers without concurrency.

## Staging

1. PR 1: contained faults, tests (fault in one child with sibling success, cleanups run on the faulted child, default still exits 67 with the existing fixture), docs.
2. PR 2: `cancelled()`, tests (group close, timeout), docs.

## Risks

- A contained fault releases frame-owned values like a cancellation (`proposals/handler-fault-drops.md`).
- Windows: task fault unwinding already runs under the guard on all platforms (`tasks-fault` fixture runs everywhere); the new tests are cross-platform and not gated.
- Adding a `TaskError` case breaks exhaustive matches in user code; in-tree uses are `==` comparisons in fixtures only.
