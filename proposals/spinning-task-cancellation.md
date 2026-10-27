# Cancelling a task that never waits

## Summary

- Tasks share one thread and are cancelled at their next wait, so a loop that never waits ignores group timeouts and cancellation and starves other tasks (#1536).
- Proposed: insert a cancellation check at loop back-edges of functions that can run in a task, only when the loop body contains no wait, call, or cancellation point already.
- Cost: one load and branch per back-edge in affected loops, to be measured before approval.
- Decision requested: approve back-edge checks (recommended) or a documented limit with only the lint.

## Status

Proposal, 2026-10-27, checked against `origin/main` at `5f28e5d0`. Verified: `documentation/core-language/control-flow/loops.md#cancellation` documents the gap, and lint **MSL111** flags `while True` loops without a wait in modules importing `@std/tasks.ms`. No runtime enforcement exists. No repro was attached to #1536.

## Problem

- A task running `while True: counter += 1` is never stopped by a `TaskGroup` timeout or by cancellation, and no other task runs.
- The lint is advisory, covers only `while True`, and is off for modules that do not import `@std/tasks.ms` yet are called from tasks.
- Non-goals: preemption of native calls, and changing cancel-at-wait for loops that do wait.

## Design

- Lowering adds, at the back-edge of a loop with no call or wait in its body, a read of the current task's cancellation flag; when set it unwinds through the same path a cancelled wait uses, so cleanup (`with`, drops) runs as today.
- Loops whose bodies contain a call are not instrumented: a call may reach a wait, and the callee's own loops are instrumented. Measure before widening.
- Outside a task the flag read is the main task's flag and is never set.
- Semantics: cancellation is still cooperative and still delivered only at waits, back-edges, and calls into waits; no signal-based interruption.
- Hard limit alternative: document that spinning tasks are unsupported and rely on the lint; no code change.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-lower` / `ms-clif` / LLVM backend | back-edge check | e2e fixture: spinning task cancelled by a group timeout |
| `crates/ms-rt` | expose the current-task cancellation flag as a small primitive | runtime unit test |
| lint MSL111 | stays; message says the runtime now stops such loops | lint test |
| docs `loops.md`, `taskgroup` pages | replace the gap with the new rule | book check |
| `ms-check`, parser, stdlib | unchanged | none |

## Alternatives

- Do nothing (lint only): spinning tasks still hang a group; users cannot recover.
- Check at every loop and call: simplest rule, higher cost on hot loops; measure against `bench/perf/` before choosing.
- Preemption by signal or a watchdog thread: breaks the single-thread task model.

## Staging and verification

- Stage 1: measure the back-edge cost on `bench/perf/` kernels with the check forced on; go only if the regression is within noise. Stage 2: implement on Cranelift and LLVM together, with the e2e fixture on Linux, macOS, and Windows. Gate: `make verify-full`.

## Open questions

- Back-edge checks (recommended) or documented limit? This changes observable behavior of spinning tasks, so the owner decides.
