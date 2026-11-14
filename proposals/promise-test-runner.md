# Promise test runner: run every test in one process

## Summary

- Problem: `ms test` runs each test in its own process, one after another, so a test file uses about one core and the conformance corpus pays process, record-file and supervision cost per test.
- Change: the test executable runs every test file at once, each in its own promise on the runtime's worker threads, a file's tests in order around one shared fixture; it records one result per test. This is the only way `ms test` runs tests. `ms bench` keeps one process per bench.
- Decisions (Chinmay, 2026-11-14): files are the unit; a fault stops the rest of its file; `skip(reason)?` is an error; virtual clock on by default; a test that never waits is stopped by killing the process.

## Status

Proposal, 2026-11-13, measured on `main` at `8ecb3576` plus #3835 (4 cores, release `ms`, `MS_BACKEND=cranelift`). Direction (Chinmay): virtual clock "on by default in every test" (2026-11-14); "make this the only way of testing, not a second entry"; "promises will scale better for more tests"; global state handled as Go does (serial or parallel by choice, scoped helpers, no automatic reset). Review (skeptical subagent): sketch was serial and queue time counted against timeouts, default placement is not parallel, leak accounting and stdout capture are per isolate, skip and fault records need rework, corpus benefit unmeasured; all folded in below.

## Problem

Measured on 40 `phase=test` fixtures in `tests/conformance/fixtures/e2e/stdlib` (242 tests):

| Run | Wall |
| --- | --- |
| `ms test f` for each file | 12.6 s |
| `ms test f1 f2 ...` (one binary) | 8.5 s: compile and link 2.3 s, tests 6.2 s |

- Tests run one at a time: CPU 10.0 s against 8.6 s wall, so the 6.2 s run phase uses about one core of four.
- A bare executable starts in 1.7 ms, so process start is about 7% of the 25 ms per test; the saving comes from parallelism, not from skipping spawns.
- `crates/ms-cli/src/engine/testing.rs` `run_one` spawns, pipes and reaps a child per test; `ms-lower/src/runner.rs` `build_runner` is a switch on the index argument.

Whole corpus, measured: 662 `phase=test` fixtures in 17 batches of 40 (`ms test f1 ... f40 --json`, run one batch after another): 69 s wall.

- Compile is about 36 s, about 2 s per batch: each binary re-generates code for every library function it reaches.
- Tests total 33.1 s over 2,807 tests. Median 2.4 ms including spawn, so per-test overhead is about 6 s of the 33.
- The tail dominates: the top 10 tests are 49% of test time, the top 50 are 71%, and the longest is 4.0 s (`html.ms` default limits). Many are wait-bound by design (timeouts, network, backpressure, 50,000 parked tasks), so they overlap far beyond core count.
- Simulated from those durations (list scheduling):

| Schedule | Test wall |
| --- | --- |
| today, serial | 33.1 s |
| 4 at a time, inside each batch | 15.6 s (14.7 s longest-first) |
| 4 at a time, one pool across all batches | 8.3 s |
| 16 in flight, one pool, no spawn cost | 4.0 s (the longest test) |

- Two findings: a per-binary pool is capped by each batch's slowest test, so the pool must span the whole run; and wait-bound tests make in-flight count, not core count, the limit. Promises fit that: a waiting promise holds no thread, where 16 processes would contend for 4 cores whenever tests compute.

## Design

1. **Harness in Manuscript.** `stdlib/test/runner.ms` `run_test_files` takes one runner closure per test file and runs every file at once in a `Placement.Spread` promise (a fork-join tree, since a promise in a loop reads the loop variable in place, #3845). `run_plain_file` and `run_fixture_file[F]` run a file's tests in order; lowering (`ms-lower/src/runner.rs` `build_file_runners`) builds each file's runner from its test bodies, `make_fixture` and hooks. Each test's clock starts when it starts, so queue time never counts against `--timeout`.

2. **Protocol.** `MS_TEST_SELECT` lists the test indices to run; the harness appends records to the file `MS_TEST_RESULTS` names: `MSSTART index file`, `MSOUT index bytes` plus the output, `MSTEST index status nanos, message, site`, and `MSFAULT file, report`. The host reads them as they arrive (for the watchdog), prints `RUN`/result lines in plan order and fills the JSON document. Selection, `--shuffle`, `--repeat` (one process per round) and `--fail-fast` stay in the host.
3. **Faults.** A fault in a file's promise comes back from `wait` as `"EIO"` with `details["report"]`; `run_file` records it with the report cut at the runner's frames. The test that was running fails with it, `after_each` and `after_all` run from the cleanup stack (the fixture is a `Closeable` scope), and the file's later tests are reported not run. `skip(reason)?` returns an `ESKIP` error, which ends only that test; the `SKIP_MARKER` fault is gone. `MS_FAULT_RECORD` stays for benches.
4. **Crashes.** A stack overflow, abort or signal ends the process. Tests that were running (start record, no result) fail, and their files' later tests are not run, since the culprit is not known. Other files' unfinished tests run again in a new process, on a new fixture. A lost process never reports success.
5. **Timeouts.** `MS_TEST_TIMEOUT_NS` sets the file task's promise deadline at each test's start (`msrt_test_deadline`), so every wait in the test (and its hooks) fails with `ETIMEDOUT` at the limit, as a promise `timeout` does; nothing is killed. A test that never waits cannot see a deadline (cancellation is cooperative), so the host kills the process when a started test has no result one second past the limit; that test fails as timed out, its file ends as on a fault, and other files rerun as after a crash. Loop back-edge cancellation checks would remove the kill; they cost every loop and are a separate proposal.
6. **Output.** A task carries a capture id, inherited by the tasks and promises it starts (`sched::Start.capture`); `msrt_io_write_stdout*` appends to that capture instead of the process buffer. Each file's promise gets a capture; the harness takes it at each result and writes it as an `MSOUT` record, so parallel tests never interleave and the host prints each test's output between its `RUN` and result lines. Standard error passes through live.
7. **Files are the unit.** Files run at once; a file's tests run in order in one promise and share one fixture: `make_fixture` and `before_all` once, `before_each`/`after_each` around each test, `after_all` at the end (Chinmay, 2026-11-14). Hooks return `Unit!`; a hook's error fails (or, `ESKIP`, skips) the tests it guards. An error from a test fails that test and the file continues. Process-wide state (cwd, environment) is shared as in Go; tests that change it restore it. No test is skipped or gated on any platform.
8. **One pool.** `ms-conform` runs every batch's executable into one shared pool of test slots instead of one batch after another, so no batch waits on its own slowest test.
9. **Ordering.** The host starts the tests that ran longest last time first (durations kept beside the build output), so a 4 s test never starts last. Without history, source order.
10. **Compile time.** Out of scope here; it is about 37 s of the corpus and has its own work. This proposal only requires that each batch's tests can start as soon as it links.
11. **Parallelism limit.** `--parallel <n>` caps tests in flight; default 4 per core, since a waiting test holds no thread; `1` is serial, for debugging.
12. **Leak accounting.** The stats runtime's live-block count is process-wide, so `ms-conform` (`LEAK_CHECKED`) and `tools/count-check.ms` keep coverage. `tools/cancel-sweep.ms` needs per-test park counts, so it runs each test alone with `--test`.
13. **Virtual clock, on by default.** Each test promise and every promise it starts share one test clock: `sleep`, promise `timeout`, `monotonic()` and `now()` read it. When every promise of the test is blocked, the clock jumps to the next timer (Go's `testing/synctest` model), so timer waits take no wall time and are deterministic. A promise blocked on real I/O (socket, file, child process) is not durably blocked, so the clock waits for it. `--timeout` stays wall time. A test that needs real time calls `@std/test` `with_real_clock(operation)` (hypothesis name, checked in stage 4).
14. **Benches.** `ms bench` keeps one process per bench (timing needs isolation); only the test path changes.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/internal/test_runner.ms` (new) | promise harness, per-test records | `ms test` e2e: pass, fail, skip, fault, timeout cases |
| `crates/ms-lower/src/runner.rs` | call the harness instead of the index switch | `cargo test -p ms-lower` |
| `crates/ms-cli/src/engine/testing.rs` | read the record stream, watchdog, crash reporting, `--parallel` | `testing.rs` unit tests, rewritten for records |
| `crates/ms-rt/src/io.rs` | per-test stdout buffer | e2e: two printing tests do not interleave |
| `stdlib/test/test.ms`, `documentation/` | `TestHooks` wording, `--parallel` | `make docs`, repo-check |
| `tools/conform.ms`, `ms-conform` | many fixtures per `ms test` call | corpus output unchanged |

## Alternatives

- Do nothing: 6.2 s of the 8.5 s above is serial test time; it grows with every test.
- Parallel child processes (run N at once): should give about the same run-phase time (6.2 s to about 1.6 s on 4 cores, hypothesis) and keeps isolation of crashes, timeouts, leaks, output and env. The cost of choosing promises is exactly that isolation; the owner chose promises as the only lane.
- Keep both lanes: rejected by the owner; two entries double the protocol and the tests.
- JIT in-process: needs a new dependency and an embeddable runtime; rejected earlier, no change.

## Stages

0. Prototype the harness on the 40 fixtures. Stop if the run phase is not within 1.2 x its longest test (3.5 s there, so about 4.2 s, against 6.2 s serial).
1. Harness, protocol, host reader, leak accounting across isolates, crash and timeout reporting; `ms test` fixtures green. Check: the 40-fixture run phase within 1.2 x its longest test, leak and `expect-` checks unchanged.
2. Per-test output buffer and scoped cwd/env helpers; fix the 2 fixtures. Check: corpus output identical.
3. `ms-conform` batches fixtures per `ms test` call and compiles batches in parallel (independent of promises; 12.6 s to 8.5 s on 40 fixtures alone). Check: corpus test phase under 6 s on 4 cores (from 33 s); `make conform-fast` corpus time, and the CI conformance legs, before and after.

4. Virtual clock in `ms-rt` timers and `@std/time`, `with_real_clock`; fixtures that measure real elapsed time opt out. Check: `many-tasks.ms` and `http2-cancelled-requests.ms` under 50 ms each; corpus test phase re-measured.

## Results

Prototype on `main` at `4b2eaddf` (4 cores, release `ms`, `MS_BACKEND=cranelift`): conformance test phase (660 fixtures) 1m19s including compile, 658 green; the other 2 (`json.ms`, `yaml.ms` deep nesting) overflow a promise task's stack in generated encoders and are fixed by #3857. Fixtures whose expectations changed by decision: `testing-fixture-teardown-on-skip` (fixture shared), three fault fixtures (fault ends the file), `golden-0412` (hook message).
