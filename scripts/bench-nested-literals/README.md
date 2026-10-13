# Nested literal checking (#147)

Build and run with the pinned SDK from the checkout root:

```sh
toolchain/go/bin/go run ./scripts/bench-nested-literals -count=3
```

The runner constructs List/Map ASTs directly after parsing one shallow module.
This isolates checking from the independent 1,000-level source parser guard.
Standard declarations are warmed; timed checks retain normal type/effect work.
Bytes are total allocations during one check, not retained heap or peak RSS.
The checker allocation-growth tests enforce scaling without flaky time limits.

Independent baseline: pristine main `f01d88003284cc21ffda49284b04694c53f8cd8a`,
Go 1.25.1, AMD EPYC 9V74, Linux amd64. The same runner was compiled against that
checkout. Current main's mechanical moves and query API changes do not replace
this independent implementation. Unprofiled samples are in `results/before.jsonl`;
the earlier profiling pass includes the complete 4K result and is retained
separately. Candidate samples in `results/after.jsonl` include both collection
kinds and no CPU profiler. Shared-host times are workload evidence, not universal
speedup promises; allocation counts provide the deterministic comparison.

| List depth | Before median | After median | Before → after allocations |
| --- | --- | --- | --- |
| 500 | 0.321 s | 0.0010 s | 376,961 → 1,723 |
| 1,000 | 2.691 s | 0.0027 s | 1,503,723 → 3,233 |
| 2,000 | 23.11 s | 0.0035 s | 6,007,247 → 6,251 |
| 4,000 | 219.57 s (one profiled pass) | 0.0063 s | 24,014,326 → 12,285 |

The 4K Map candidate uses about 4.8 MB total allocated and 28K allocations.
Bounds are still checked at each literal's own source location. Nested empty
Lists now report the missing leaf context once; independent invalid Map keys
retain one diagnostic per key instead of being repeated by every parent.
