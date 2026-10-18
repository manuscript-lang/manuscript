# Manuscript vs hand-written Go (performance)

Go parity remains unmet. The retained changes remove measured inlining and
loop-bookkeeping overhead; several workloads still run slower than the Go controls.

2026-10-18, Go 1.25.1, linux/amd64, AMD EPYC 9V74, 4 vCPU quota.
Baseline compiler/runtime: aa3efa72. Both revisions compile the same corrected benchmark
sources in this change. Medians of 30 trials, cycling every permutation of Go/before/after.
Each comparison shares the same Go samples; every checksum and operation count is verified.
Compilation and correctness checks finished before sampling.

| operation | before ns/op | after ns/op | Go ns/op | after / Go |
|---|---:|---:|---:|---:|
| string_append_50k | 7.09 | 3.34 | 2.81 | 1.19x |
| read_line | 81.89 | 81.32 | 62.99 | 1.29x |
| map_put_get_8k | 64.51 | 64.61 | 31.93 | 2.02x |
| int_eq | 1.24 | 1.26 | 0.98 | 1.29x |
| generic_call | 0.88 | 0.90 | 0.28 | 3.20x |
| method_call | 2.27 | 2.37 | 0.29 | 8.18x |
| try | 3.63 | 2.74 | 0.56 | 4.94x |
| match | 6.39 | 4.82 | 1.57 | 3.07x |
| builtin_length | 1.22 | 0.92 | 0.28 | 3.25x |
| for_list | 0.92 | 0.95 | 0.41 | 2.31x |

String appending is about 2.1x faster; try and matching improve about 1.3x.
The length workload improves by about 25% through cheaper loop polling.
Map timings are particularly noisy and show no established improvement.

## What changed

- Keep fault stack capture out of line, so small checked helpers can inline.
  Go's reported costs for Optional.get and Result.get fall from 93/94 to 75/76,
  below its budget of 80. Fault messages and source frames remain intact.
- Construct Result cases as typed Go literals. `try` evaluates once and returns
  an exactly matching failed Result directly; different success types and error
  widening still construct the enclosing return type. This lowers `chain`'s
  ordinary Go inlining cost from 91 to 80. In a separate 30-run comparison
  against bf8aa92e, try improves from 3.57 to 2.84 ns/op.
- Store a StringBuilder's bytes directly. Its pointer and sealed state preserve
  aliases and immutable zero-copy freeze, while removing a redundant Go value-copy
  check. Append now inlines at cost 72 instead of 118.
- For literal-start, strictly bounded unit-step counters, derive the exact poll
  phase from the counter. Dynamic starts, extra writes and continue retain a tick.
  Native probes verify cancellation before iterations 64 and 128. Assembly
  confirms the initial literal folds and the separate tick disappears.
- Isolate workloads in separate functions in both languages; allow ordinary Go
  inlining; acquire stdin once; align setup/timing boundaries; alternate samples;
  reject incorrect outputs; and retain raw evidence. Older tables used a different
  harness and best-of sampling, so their ratios are not comparable.

## Allocation controls

Seven samples, 300 ms per sample, ordinary caller inlining. Builder operations
construct and freeze 50,000 appended bytes; list reads measure one lookup/get.
Allocation counts are unchanged from the baseline.

| operation | before ns/op | after ns/op | Go ns/op | after allocations |
|---|---:|---:|---:|---:|
| ListAtGetVsGo | 2.341 | 0.873 | 0.426 | 0 B / 0 allocs |
| StringBuilderVsGo | 271,714.000 | 104,531.000 | 96,192.000 | ~211,706 B / 21 allocs |

## Remaining gaps

The reported labels time whole loops. In emitted Go, integer equality and positive-literal
remainder are native operators, the generic identity inlines, length is already len,
and list iteration is already a Go range. Their remaining costs include checked
accumulation and cancellation. `chain` now inlines, but `checked` and the method
retain arithmetic that still exceeds Go's inline budget. Matching retains checked
multiplication and optional access.
Maps retain insertion order and recoverable concurrent-access diagnostics, while the
Go control uses an unordered map. Line reads retain stream synchronization and UTF-8
validation. These are contributing costs, not proof that further optimization is
impossible. Safe arithmetic/alias proofs and more profiling are still needed to
meet the requested parity target.

An experiment compiling the runtime with Go's `-l=4` made checked methods and
`checked` inline, but the wider suite exposed regression candidates, including
string interpolation. It was rejected. Optimized builds retain ordinary Go
settings. Raw rejected results, compile/build costs and the review constraints
are preserved alongside the retained measurements.

## Evidence and reproduction

[Latest program and stdlib samples, environment and hashes](../results/2026-10-18-linux-amd64/try-inlining/)
and [earlier runtime allocation/polling evidence](../results/2026-10-18-linux-amd64/)
are checked in. The raw program tables can be regenerated with table.py; compare.py runs
already-built revisions in balanced order. Build each compiler, then build these
same benchmark sources with both compilers. Use run.sh for the ordinary Go/MS pair.
The [proposals and review constraints](optimization-notes.md) describe the retained invariants.

```sh
make build
BENCH_OUTPUT=.artifacts/perf-programs sh perf-bench/programs/run.sh 30
python3 perf-bench/programs/compare.py --before /path/to/before/bench --after /path/to/after/bench --go /path/to/go/bench --input .artifacts/perf-programs/lines.txt --output .artifacts/perf-comparison --repeats 30
toolchain/go/bin/go test ./pkg/runtime -run '^$' -bench '^(BenchmarkStringBuilderVsGo|BenchmarkListAtGetVsGo)$' -benchmem -count=7 -benchtime=300ms
python3 -m unittest discover -s perf-bench/programs -p 'test_*.py'
```

Validation: make verify; the full native e2e suite; final compiler/lower tests,
native polling-phase probe, and targeted overflow/fault-location/bound-member
tests; builder checkptr checks; ShellCheck; benchmark validation tests; and the
66-case standard-library benchmark; packaged compilation/tooling with fresh
caches and no host tools. Platform execution evidence is linux/amd64.
