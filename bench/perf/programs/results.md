# Manuscript vs handwritten Go

Go parity remains incomplete. This change improves builder appends, equality,
matching, try propagation and native list searches under ordinary Go compilation.
Small checked method calls remain the largest relative gap in these programs.

2026-10-18 UTC, Go 1.25.1, linux/amd64, AMD EPYC 9V74, 4 vCPU quota.
Baseline compiler/runtime: **2b4962d19c4856efbcc3d8a156578ea9e466d9b7**.
Both revisions compile the same current benchmark sources. Medians of 30 trials,
cycling all six Go/before/after permutations; paired comparisons share the same
Go samples. Compilation and correctness checks finished before sampling. Every
program checksum and operation count is verified.

| operation | before ns/op | after ns/op | Go ns/op | after / Go |
|---|---:|---:|---:|---:|
| string_append_50k | 6.42 | 3.60 | 2.83 | 1.27x |
| read_line | 80.17 | 81.59 | 64.05 | 1.27x |
| map_put_get_8k | 64.52 | 66.97 | 31.90 | 2.10x |
| int_eq | 1.40 | 1.05 | 0.97 | 1.08x |
| generic_call | 0.89 | 0.87 | 0.28 | 3.07x |
| method_call | 2.33 | 2.59 | 0.27 | 9.44x |
| try | 3.51 | 2.61 | 0.58 | 4.51x |
| match | 5.72 | 4.23 | 1.57 | 2.69x |
| builtin_length | 0.87 | 0.88 | 0.28 | 3.10x |
| for_list | 0.89 | 0.90 | 0.38 | 2.37x |

Builder appends are about 1.8x faster; equality, try and matching improve about
25–26%. The checked method workload is about 11% slower than main and remains
unresolved. Its arithmetic body is unchanged; these samples do not establish
the cause. Maps and line reading show no improvement. Small differences in the
remaining rows should be read with the paired intervals in the raw evidence.

## Retained changes and invariants

- Keep fault stack capture out of line. Optional_Get/Result_Get costs fall from
  93/94 to 75/76, below Go's inline budget of 80. Fault messages and source
  locations remain intact.
- Lower Result constructors as typed Go literals. `try` evaluates once, checks
  `Failed`, and directly returns an exactly matching failed Result. Different
  success types/error widening construct the enclosing Result. Empty error text
  remains failure. The benchmark's chain cost falls from 91 to 80.
- Store StringBuilder bytes directly. Generated aliases share a pointer and
  sealing prevents writes after zero-copy freeze. Freeze observes cancellation
  before sealing; frozen text survives its builder. Like strings.Builder, the
  Go implementation value must not be copied after first use.
- Inline nonnegative in-range list reads; retain the original normalization,
  default and diagnostic handling in the fallback. Seven balanced microbenchmark
  samples measured positive reads at 2.18 -> 0.64 ns with zero allocations.
  Variable negative reads cost 2.19 -> 2.48 ns; defaults were roughly unchanged.
  This approximately 0.3 ns fallback tradeoff is intentional and measured.
- Derive polling phase from literal-start, strictly bounded unit-step counters
  with one unconditional write and no continue. Dynamic starts and all excluded
  forms retain ticks. `(distance + 1) & 63 == 0` preserves the exact checks before
  source iterations 64/128, including raw Go modular arithmetic.
- Keep only periodic native polling's cancellation call out of line. Poll and
  PollIndex costs fall from 91/86 to 71/66; traversal call sites inline the
  counter and predicate. Direct CheckCancelled calls are unchanged. Query counts,
  uint32 wrap, cancellation identity, nil Execution and shielding are tested.
- Align Go/MS per-workload functions, ordinary caller inlining, stdin acquisition
  and setup/timing boundaries. Reject incomplete or incorrect evidence.

## Native library control

Thirty alternating samples per revision, all 66 operation names/counts verified.
List.contains improves from 283,198 to 180,555 ns per search (paired 95% ratio interval 0.624–0.658). The isolated polling-only control independently
measures 345,368 -> 177,280 ns; its paired 95% ratio interval is approximately
0.496–0.534. The unchanged search/poll bodies in the initial whole-change control
alone did not establish causation; the isolated control supports this change.
The final whole-change run also measures fs.stat at 5,670 -> 6,510 ns
(interval 1.030–1.279); this unresolved host-workload regression is reported
alongside the gains. The complete library table, paired intervals and raw trials
are archived below.
Rounded sub-nanosecond library rows are not suitable for precise ratios.

The original allocation control measured builder construction/freeze of 50,000
appends at 271,714 -> 104,531 ns versus Go 96,192 ns, with approximately
211,706 B / 21 allocations unchanged. These earlier-baseline numbers are
historical; the current whole-program comparison is the table above.

## Remaining gaps and rejected experiments

Labels time complete loops. Equality and positive-literal remainder are native
operators; identity inlines; length is len; list iteration is a Go range. Checked
accumulation and cooperative cancellation still contribute. `chain` now inlines,
but `checked` and the method's checked arithmetic exceed Go's ordinary budget.
Matching still uses checked multiplication and optional access. Maps preserve
insertion order and recoverable concurrent-access diagnostics, whereas the Go
control is unordered. Line reads retain synchronization and UTF-8 validation.
These are contributing costs, not proof that further optimization is impossible.

Runtime-wide `-l=4`, alternative overflow formulas, a small-multiply fast path,
and globally outlining CheckCancelled improved selected workloads but regressed
others. They were rejected. No special Go flags, unchecked arithmetic, relaxed
cancellation or representation change to Result ships. The
[proposals and independent review constraints](optimization-notes.md) record
why the narrower changes were retained.

## Evidence and reproduction

[Current-main comparison, isolated polling controls, hashes and intervals](../results/2026-10-18-linux-amd64/current-main/).
[Earlier try/inlining experiments](../results/2026-10-18-linux-amd64/try-inlining/)
and [initial allocation/assembly evidence](../results/2026-10-18-linux-amd64/)
use older main revisions and are explicitly historical. Source hashes in those
archives retain the paths that existed when they were measured. Best-of tables
from older harnesses are not comparable to the corrected median controls.

```sh
make build
BENCH_OUTPUT=.artifacts/perf-programs sh bench/perf/programs/run.sh 30
python3 bench/perf/programs/compare.py --before /path/to/before/bench --after /path/to/after/bench --go /path/to/go/bench --input .artifacts/perf-programs/lines.txt --output .artifacts/perf-comparison --repeats 30
toolchain/go/bin/go test ./pkg/runtime -run '^$' -bench '^(BenchmarkStringBuilderVsGo|BenchmarkListGetVsGo|BenchmarkListGetPaths)$' -benchmem -count=7 -benchtime=300ms
python3 -m unittest discover -s bench/perf/programs -p 'test_*.py'
```

Validation includes make verify; native conformance and Go e2e; build/compiler/
lower/runtime tests; native phase/source-frame/payload/bound-member checks;
builder checkptr; ShellCheck; Python evidence tests; and standalone distribution
compilation/tooling with fresh caches and no host tools. Measured execution is
linux/amd64; CI covers additional hosts/distributions.
