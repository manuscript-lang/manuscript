[Wiki](../index.md) › [Runtime](index.md)

# Scheduler stress mode sends every promise to another thread

Verified (2026-11-15): by default a waiter runs its unstarted promise inline, so cross-thread bugs show only when a test is slow enough to be stolen. `MS_SCHED_STRESS=1` makes `sched::submit` put each start on the first idle thread other than its creator and raises the thread limit to at least 2, so every promise crosses threads. `make stress-sched` runs the e2e stdlib files whose declared phase is `test` under it (a parse, check or run fixture is not meant to pass `ms test`) and reruns a failing file without it; only a stress-only failure fails the tool. Promises pinned to their creator (live native stream, terminal, `start_here`) stay put.

First sweep over 245 files: no stress-only failure in four runs. Runtime tests that assert placement (inline run, manual placement) fail under stress by design; do not run them with it set (`tools/stress-sched.ms` drives the sweep).

The mode exists only in a runtime built with the `sched-stress` feature; `make stress-sched` builds a separate `ms` (`target/stress`) with it, and the shipped runtime never reads `MS_SCHED_STRESS`.

Apply when: adding a promise test, or changing `sched::submit`. The nightly main job runs `make stress-sched`; PR CI does not, until its time is measured against the 10-minute budget.
Evidence: `design/proposals/scheduler-stress-mode.md`, `tools/stress-sched.ms`.
