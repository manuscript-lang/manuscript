# Cancel-at-every-await sweep

## Summary

- Problem: cancellation leaks were found one at a time by hand (#2996, #3003, #3008, #3034, #3040, #3045, #3046, #3048); no check cancels a test at each await point.
- Change: a counting-runtime hook that cancels the n-th park of a process, and `make cancel-sweep`, which runs every `tests/e2e/testdata/stdlib` test cancelled at each park and fails when a cancelled run leaves more live blocks than the uncancelled run.
- Decision requested: none. Replacing the cleanup stack with destructor-running unwinds, and removing `rt::Parked`, is a later stage that this harness gates.

## Status

Implemented 2026-11-08 against `c6fef864`.

## Problem

- `msrt_cancelled` leaves a task by a jump; `ms-mir/src/unwind.rs` registers cleanups per live owned value, and native code needs `rt::Parked` per local. A value neither covers leaks.
- Measured: 182 of 191 stdlib fixtures, 17,088 cancelled runs (up to 16 parks per test), 0 live blocks. The remaining fixtures (HTTP, mail, router) are slower and listed in the PR.
- The sweep sees `ms-rt` blocks only. Rust-heap leaks in native code (what `Parked` covers) need `memory_usage().heap_used` fixtures such as `http-fault-leak.ms`.

## Design

- `ms-rt` feature `stats` only: `MS_CANCEL_AT_PARK=n` makes the n-th `msrt_task_wait_fd` or `msrt_token_park` return `WAIT_CANCELLED`, as a cancel of the parking task; `MS_PARK_COUNT=1` prints the park count at exit. Release builds compile the hook to `false`.
- `tools/cancel-sweep.ms` reads each test's park count from one run, then reruns it with `--filter` at each park up to `SWEEP_MAX_PARKS` (default 64).
- Parks on other scheduler threads are counted too; a test whose count varies between runs is swept at the counts it saw.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt/src/task.rs`, `start.rs` | park counter and injection (stats only) | `make cancel-sweep` |
| `tools/cancel-sweep.ms`, `Makefile` | sweep driver, target | run on `stream-cancel.ms` |

## Alternatives

- Do nothing: leaks keep surfacing as issues, one per fixture.
- Cancel by timer: not deterministic, misses most parks.
- Unwind running destructors instead of cleanup entries: the real fix for `Parked`, but a codegen change; it should land behind this gate.
