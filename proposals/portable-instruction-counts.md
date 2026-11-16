# Portable instruction counts for `ms bench`

## Summary

- Problem: `ms bench` reports wall-clock time, which is too noisy to fail a build. The only stable gate (`make perf-counts`) needs callgrind, so it is Linux-only and not available to a user's own Manuscript project.
- Change: `ms bench --count` builds the program with a block counter and reports deterministic executed-operation counts per bench, comparable against a saved baseline.
- Decision requested: approve counting in the compiler backends (option B below) as the first stage.

## Status

Proposal, 2026-11-15, checked against `main` at 276158dd. Direction from the owner: bench should gate Manuscript programs without callgrind and without a MIR interpreter. Not yet reviewed by a skeptical reviewer.

## Problem

- `stdlib/test/bench.ms` measures with `monotonic()`; runs on a shared runner differ by far more than a real 3% regression.
- `tools/perf-counts.ms` runs nine programs under valgrind. valgrind does not exist on macOS or Windows, so parity fails, and a user project cannot reuse it.
- Measured on Linux: the five guards in `bench/perf/guards` count between 4.5M and 322M instructions, stable to under 0.1% across runs, which is what a gate needs.

## Design

- `ms bench --count` compiles the program with counting on. Each MIR basic block gets an index in a flat `u64` array. The backend emits one add per block, adding the block's operation count (a constant known at compile time). No hash, no pointers.
- The array lives in the runtime. `run_bench_block` reads the total before and after each iteration and adds `instructions` (per operation) to the `MSBENCH` JSON line next to the time fields.
- Runtime primitives called from a block (`call.rt`) add a fixed cost from a table in `ms-rt-abi`, plus the byte or element count where the call has one. This is a model, not a hardware count.
- `ms bench --json` output with `instructions` can be saved and compared: `--baseline file.json --fail-over 3%` exits non-zero when a case rises past the bound. Time stays reported but never fails.
- Same output on Linux, macOS and Windows, because the number comes from compiled-in constants, not the CPU.
- Only code built through MIR is counted. Rust crates behind runtime calls (crypto, regex, image) count as their table cost, so a slowdown inside them is invisible. `perf-counts` stays for those on Linux.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-mir` | per-block operation weight | unit test on a known function |
| `ms-clif`, `ms-mir-llvm` | emit the add when counting is on | conformance: same count under both backends |
| `ms-rt`, `ms-rt-abi` | counter array, call cost table | runtime test |
| `stdlib/test/bench.ms` | report `instructions` | bench JSON test |
| `ms-cli` | `--count`, `--baseline`, `--fail-over` | CLI invocation test |

## Alternatives

- Do nothing: regressions in Manuscript programs are found by hand.
- Hardware counters (`perf_event_open`, macOS `kperf`, Windows): need privileges the CI VMs and containers often lack, and have no common API; fails parity.
- MIR interpreter count: portable, but runs slowly, may not support every runtime call, and ignores the real backends. Rejected by the owner.
- Callgrind everywhere: not available outside Linux.

## Stages

1. Counting in the Cranelift backend and `--count` output; one guard moves over as a bench block.
2. LLVM backend parity check (counts must match the Cranelift counts within the model).
3. `--baseline` and `--fail-over`; move the guards from `perf-counts` into bench blocks.

## Open questions

- Should the operation count weight memory operations and calls more than arithmetic? Recommendation: no; equal weight, with the runtime table carrying the cost of heavy calls.
- Is a model-based count acceptable as a gate when runtime Rust code is only table-costed? Recommendation: yes for Manuscript code, and keep callgrind on Linux for runtime crates.
