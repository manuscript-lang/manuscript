# Scheduler stress mode

## Summary

- Problem: a promise usually runs inline on its waiter, so races that need another thread to take it show once in N runs, in CI only.
- Change: `MS_SCHED_STRESS=1` makes placement deterministic: a promise never starts on its creator and the first idle thread takes it. `make stress-sched` runs the stdlib fixtures under it.
- Decision requested: none; no language or user-visible default changes.

## Status

Proposal and implementation in one PR, 2026-11-15, checked against 7d4b8c2f.

## Problem

- `promise(fn:)` queues on the creator (`sched::submit`); a waiter without a deadline pulls it back and runs it inline (`promise::run_unstarted`). Another thread takes only a start older than `BEAT_NS` (20 us). Most tests therefore run every promise on one thread, and a cross-thread bug appears only when a test happens to be slow enough.
- Past examples: terminal state touched from a thief thread (#2820), handles used off their owner thread (#3118), mixed-thread `wait_any` (#3355). Each was found by a flaky CI run, not by a test written for it.
- The thread count follows the CPU count, so a 1-core runner never crosses threads at all.

## Design

- `MS_SCHED_STRESS` set to anything but empty or `0` turns it on; read once (`ms_workers_stress`).
- `sched::limit` is at least 2, so another thread always exists.
- `sched::submit` in stress mode (`submit_stress`) pushes the start to the first idle thread other than the creator (lowest index), else the next thread in turn. The start is already aged, so any idle thread may also take it. It returns sequence 0: the creator's queue holds nothing, `remove_pending` finds nothing, and the waiter parks.
- Cancel of such a start sets `WANT_CANCEL`, the same path as a start taken but not yet running.
- Unchanged: a promise pinned to its creator (live native stream, terminal, `start_here`) stays on it, since correctness needs that.
- Placement is a rule, not a random choice, so a failure reproduces; the order the OS runs the threads in still varies, which is the point.
- `tools/stress-sched.ms` runs each e2e stdlib file with stress on. A failing file is rerun without stress: pass means a stress-only failure (fails the tool), fail means broken anyway (reported). `STRESS_CHANGED=<ref>` runs only changed fixtures. Not in pull request CI yet: the nightly job runs `make stress-sched`; it moves to PRs only once measured to fit the 10-minute budget.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `runtime/core/worker.c`, `promise.c` | `ms_workers_stress`, aged queueing, no inline claim, limit floor | `promise::tests` run with stress forced |
| `tools/stress-sched.ms`, `Makefile` | the sweep and `make stress-sched` | run on the fixtures |
| `documentation/contributing/development.md`, `wiki/runtime` | how to use it | none |

## Alternatives

- Do nothing: bugs keep surfacing as flakes on unrelated PRs.
- Randomized placement with a seed: finds more orders but costs reproducibility; a fixed rule plus OS jitter covers the first-idle case that matters. Can be added later.
- `MS_THREADS=8` only: leaves inline running, so the waiter still runs the work.
