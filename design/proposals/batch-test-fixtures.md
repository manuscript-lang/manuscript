# Batch test-phase conformance fixtures into one build

## Summary

- Problem: each of the 730 `phase=test` fixtures runs its own `ms test`, so the test runner and every stdlib module it imports are compiled again for each one. Under LLVM that is the largest part of the PR corpus time and the `llvm-amd64-corpus` job (500 s corpus step) fails the 600 s `Time budget` on slow runners (PR #4598: 388 s to 638 s on identical code).
- Change: `ms-conform` builds several clean test fixtures with one `ms test a.ms b.ms ... --json`, slices the combined report into one observation per fixture, and judges each against its recorded expectation. A batch that does not reproduce every expectation is rerun fixture by fixture.
- Decision requested: none for users; no language, CLI or expectation change. Chinmay, 2026-11-19: "no bump to limit, let's cut unnecessary tests and make it faster".

## Status

Implemented, 2026-11-19 (reviewed by an independent skeptical reviewer; changes taken), checked at `ccb9d30fb`. Follows the `ms check --each` batching of check fixtures (`runner.rs: check_batch`).

## Problem

- Measured (`MS_TIMINGS=1`, `--build-type Release`): a one-test program spends 0.38 s of 0.45 s in LLVM codegen, almost all of it the test runner (about 10,900 IR lines; `run_test_files`, `run_file`, `report`, `fault_message` are 900 to 1,450 lines each). 730 fixtures pay it: about 290 CPU-s of the 1,618 s of `test` fixture time in the PR LLVM job.
- Measured: each yaml fixture recompiles the whole yaml module (4.3 s); `yaml-dash-key.ms`, 21 lines, takes 4.6 s.
- Measured: 12 consecutive `e2e/stdlib` test fixtures take 11.0 s as 12 `ms test` runs and 7.0 s as one on one core; the reviewer's 4 fixtures gave 3.06 s wall and 6.8 s CPU against 4.0 s and 8.1 s (23% wall, 16% CPU). The ceiling is about 280 CPU-s, 70 s wall on 4 jobs.
- Trimming the runner source does not help: simplifying `report` saved 190 of 10,900 lines. The cost is per build, so the fix is fewer builds.

## Design

- Eligible: a `Phase::Test` single-file fixture without args or stdin whose expectation is exit 0, all tests passed, no diagnostics, empty stderr, and a `stdout` that holds only `RUN`/`PASS` lines and the summary line (683 of the 714 single-file test fixtures, recomputed by the reviewer). A fixture that imports `@std/os/`, `@std/net/`, `@std/process` or `@std/time` (files, ports, processes, clocks and timing: state one process would share) runs alone, as do fixtures with a `// conform: timeout`. Others run alone as today.
- Not batched: `CONFORM_LEAKS` runs (a leak count belongs to one program) and `record`; both keep one fixture per process.
- Batch: up to 12 eligible fixtures in id order (neighbours share modules: `yaml*`, `bigint*`), no two with the same file name (test names are `file.ms::test`). Each is materialized into its own work directory; one `ms test` takes all paths, with a timeout of the sum of the members', at most 300 s.
- Slicing: names come back as `<member dir>/file.ms::test` (with `\` on Windows), so the slicer strips the directory and takes the tests of each member in order, renumbered from 0; `source_root` is the common parent in a batch and is set to `<DIR>`. The member's observation is rebuilt as the recorded shape: `exit_code`, a report with `repeat`, `format`, `source_root` as `<DIR>`, `tests`, a `summary` counted from those tests, `completed`, a `stdout` of their `RUN`/`PASS` lines plus `N tests, 0 failed`, `diagnostics`, the key `shape` and `stderr`.
- Safety: every rebuilt observation is compared with the recorded expectation. Batching weakens isolation, since a member could be satisfied by another's state in the shared process; the carve-out above keeps the fixtures that depend on such state alone, and a pass still means the recorded observation was produced. If the batch process exits non-zero, times out, lists a test twice or another file, or any member differs, every member of that batch is observed alone and its own result is judged. 
- Shared state: files of one `ms test` run at once and share the working directory of the first file. A fixture that depends on its own directory or on exclusive resources shows up as a mismatch and runs alone; the batch size keeps the extra work small.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-conform/src/runner.rs` | group eligible fixtures, run batches, fall back per fixture | unit tests for grouping and fallback |
| `crates/ms-conform/src/observe.rs` | `observe_test_batch`: run, parse, slice | unit tests for slicing a recorded multi-file report |
| `design/wiki/repository/pull-request-ci-has-a-ten-minute-budget.md` | record the measurement | `make repo-check` |

## Alternatives

- Do nothing: the job stays at 388 to 638 s against a 600 s limit; a bump is refused.
- Trim the runner's IR: 190 of 10,900 lines saved by a source change; the bulk is inlined string, map and promise fast paths in `stdlib/internal/test_runner.ms`.
- Cache the compiled test-runner module by content: removes the runner cost without batching, but the wiki prefers removing caches to adding them.
- Lower the LLVM opt level for tests: saves under 8% and weakens what the LLVM corpus proves.
- Merge yaml fixtures by hand: about 9 CPU-s, under 1%, and it changes the corpus.

## Stages

1. Batch eligible fixtures with the per-fixture fallback; measure `test` fixture time on the Cranelift and LLVM corpus and record it in the wiki.
