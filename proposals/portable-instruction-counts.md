# Runtime work counters for `ms bench`

## Summary

- Problem: `ms bench` times are too noisy to fail a build, and the only stable gate (`make perf-counts`) needs callgrind, so it is Linux-only and unusable from another project (for example a driver such as ms-pg).
- Change: `ms bench` reports the runtime's own work counters per operation (allocations, bytes allocated, list copies, string clones and their bytes) and `--baseline` / `--fail-over` gates on them. Times are reported and never gate.
- Decision: replaces the earlier "count compiled blocks" design, which the owner narrowed and a skeptical review and a measurement rejected.

## Status

Stage 1 and the baseline gate implemented, 2026-11-15. The first draft counted operations in compiled blocks; callgrind on the five `bench/perf/guards` programs showed compiled Manuscript code is 0% (crypto), 0.8% (regex), 17.7% (image), 22% (chains) and 47% (maps) of instructions, so that count would miss most regressions. The review also found the cost model needed invented weights and raced across threads.

## Design

- The allocator already counted requests in the `stats` runtime build only. They now always count, in per-thread state (no atomics on the hot path), merged into a process total when a thread releases its heap. Cost measured with `make perf-counts`: +0.9% instructions on the allocation-heavy `strings` program, under 0.1% on the others.
- `msrt_counts` reads six words: allocations, bytes, list copies, list copy bytes, string clones, string clone bytes. `@std/os/system` exposes them as `runtime_counts()`.
- `run_bench_block` runs the body once more after the timed samples and subtracts the counters: exact per operation, and independent of the time-based calibration.
- `ms bench --baseline file.json --fail-over 3` compares each counter of each bench with an earlier `--json` result and exits 1 naming every counter over the bound. A counter that was zero may rise by one.
- `ms bench --ops` adds MIR operation counts for the program's own code, the part a user project owns: after the optimizer, a `count_ops` pass puts a leaf call at the head of every block that adds the block's instruction count to a process total (`msrt_ops_add`). The count is the same under LLVM and Cranelift (verified on a list-building bench: 5039 operations either way) and on every platform, and needs no valgrind. The counter slows the program, so an `--ops` run executes each bench once and its times are not meaningful.
- Same numbers on Linux, macOS and Windows: they are counts of runtime events, not CPU events, and need no valgrind or privileges.

## Limits

- MIR operations count compiled blocks in the code the optimizer leaves, equal weight per instruction: a loop that gets slower inside a runtime call is not seen (allocations and bytes show part of it).
- Allocations cover the calling thread and finished threads; copies cover the calling isolate. A thread still running is not in the total.
- Work inside the Rust crates (crypto, regex, image decoding) shows only as allocations and bytes. A pure slowdown there, such as the SIMD prefilter, is invisible; `perf-counts` stays for those on Linux.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-rt` | always-on counters, `msrt_counts` | `ms-rt` unit tests |
| `ms-std-process`, `stdlib/os/system.ms` | `runtime_counts()` | `e2e/stdlib/runtime-counts.ms` |
| `stdlib/test/bench.ms` | counted run, new JSON fields | `bench_baseline_gates_on_work_counters` |
| `ms-cli` | `--baseline`, `--fail-over`, `--ops` | same test, `bench_ops_counts_the_programs_own_operations` |
| `ms-mir`, `ms-build` | `count_ops` pass, `BuildOptions.count_ops` | same test |

## Alternatives

- Do nothing: regressions in a user's Manuscript program are found by hand.
- Operation counts of compiled blocks: rejected by measurement above.
- Hardware counters: no common API, privileges missing on CI VMs; fails parity.
- Best-of-N CPU time against a baseline: still noisy on shared runners; kept as an idea for the cost the counters cannot see.

## Stages

1. Done: counters, `runtime_counts()`, bench report, baseline gate.
2. Done: `cpu_ns` (process user plus kernel time per operation) in `ms bench`; `bench/perf/guards/bench.ms` gated by `make bench-gate` in the nightly run, against `baseline.json`, with callgrind kept for the Rust crates.
3. Not done: counting runtime calls by name and syscalls has no single choke point (lowered code calls `msrt_*` directly and the std crates call the OS themselves), so it needs compiler or per-crate instrumentation; threads still running are not in the allocation total; instruction counts stay callgrind-only because no portable source exists.
