# Fast test loop: check the library once, build fixtures in one process

## Summary

- Problem: the conformance corpus builds each of 1,228 run and test fixtures in its own `ms` process; every process re-checks the built-in library and, under LLVM, re-optimizes the library code it reaches.
- Change: (1) cut the fixed start-up cost of the checker; (2) a batch mode that builds many fixtures in one process from one library load; (3) run the corpus on the fast backend by default, keeping LLVM for CI and release.
- Decision requested: approve stages 1 and 2. Stage 3 (in-memory run with Cranelift JIT) needs a new crate and is the owner's call.

## Status

Proposal, 2026-11-13, measured on `main` at `8ecb3576` (4 cores, release `ms`). Skeptical review: build with changes; ship stage 1 first, gate stage 2 on a measured prototype. Direction (Chinmay): "we should be running 1000 tests in seconds not minutes"; "no additional runners"; CI speed is the main motivation.

## Problem

Measured (`ms-conform run --phase run,test`, 1,228 fixtures, `target/release/ms`):

| Run | Wall | CPU |
| --- | --- | --- |
| default (LLVM -O3) | 4m33s | 15m39s |
| `MS_BACKEND=cranelift` | 1m30s | 4m25s |

- LLVM codegen is 3.8 s of 4.3 s for one XML test (`MS_TIMINGS=1`); front end and MIR are 0.15 s.
- A hello-world has a floor of 0.14 s on Cranelift: `ms check h.ms` is 77 to 90 ms, link about 30 ms, the rest spawn and exec.
- Callgrind of `ms check h.ms` (448M instructions): ownership analysis of the 506 prelude callables 34% (3 rounds, each re-walks all 506), checking the prelude modules 30%, parsing 8%, SipHash 12% (fixed in #3835).
- Median fixture is 199 ms on Cranelift, so about 90 ms of that is repeated library work and 30 ms is linking.
- CI: linux-arm64 conformance is 29 minutes, linux-amd64 conformance 22, the two tests jobs 8 to 10 (run 43508900616). The corpus is the critical path.

## Design

1. **Start-up cost.** Ownership: re-analyze a callable in a later round only if a summary it read changed (reads recorded in `Summaries::get`; done: hello `ms check` 85 to 70 ms with the hasher). Library: analyzing only callables reachable from user code is a second step; it needs an explicit root set (lowering roots, vtable impls of instantiated types, drop glue, closures) and a differential test that every fact lowering reads equals the full analysis, with a hard error on a missing fact.
2. **Batch mode** (gated on a prototype that shows the saving beyond stage 1, and on a per-fixture panic and timeout fallback; process-global state such as `Names::global()` must not change output). `ms run --each` and `ms test --each` (same shape as `ms check --each --json`): one library load, then each input is checked, lowered, compiled and linked on its own, and reported as its own result. `ms-conform` groups run and test fixtures into batches the way `observe_check_batch` groups check fixtures, and falls back to one process for a fixture the batch could not report.
3. **Backend choice.** `make conform` runs the corpus on Cranelift (done in #3835). CI keeps one LLVM run (linux-arm64) and one Cranelift run (linux-amd64) against the same expected output; the drift step is removed (owner, 2026-11-13).
4. **Later, needs approval.** Compile each fixture with Cranelift JIT into memory and run it in a worker: no object file, linker or exec. Needs `cranelift-jit` (a new dependency, so the owner decides).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check/src/ownership` | read-tracked worklist; demand-driven prelude | `cargo test -p ms-check`; corpus facts identical (`make conform`) |
| `crates/ms-cli` | `--each` for `run` and `test` | e2e: results equal single-file runs |
| `crates/ms-conform` | batch run and test fixtures | corpus passes; per-fixture output unchanged |
| `tools/conform.ms`, Makefile | fast loop | `make conform` |

## Alternatives

- Do nothing: 8 minutes locally, 30 minutes in CI, and more fixtures every week.
- More CI runners: rejected by the owner; it hides the cost instead of removing it.
- Cache the checked library on disk: the project rule is to make the check faster first; keep only if stage 1 cannot match it. A cache also needs a key for every input.
- Cache LLVM objects per library module (`lazy-stdlib-objects-proposal-2026-11-12.md`): helps release builds; this proposal targets the test loop.

## Stages

1. Start-up cost (item 1). Check: `ms check` of hello under 40 ms; whole corpus facts unchanged.
2. `--each` and the batch runner. Check: corpus time on Cranelift under 45 s on 4 cores.
3. CI wiring and measurements. Check: linux-arm64 conformance job under 15 minutes with no added job.
4. JIT, only if approved.

## Open questions

- Is `cranelift-jit` acceptable as a dependency? Recommendation: decide after stage 2 numbers.
