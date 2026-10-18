# CLI inspection performance

`inspectProgram` constructs a full inspection only for legacy diagrams.
Inspection JSON and scoped diagrams already construct their required inspection
in their consumers. Moving the unused call preserves public APIs, formats,
source identities and generated Go.

## Measurement

Production baseline: `aa3efa7296e8b02f1ca1aa26a144debcd69dc7d8`.
Code candidate: `d474941d35e422839eb1f0a47b51d131f6926328`, based on
`7f5834b2129b02e3c7cc1597514f8e34e04b1006`. Intervening #659/#660
do not change this call path. Measurements used baseline/candidate binaries
from before that rebase.

Linux 6.18.55 amd64, AMD EPYC 9V74, five visible CPUs, four-CPU cgroup quota,
16 GiB memory limit, pinned Go 1.25.1. Six samples per N/2N/4N workload:

```sh
toolchain/go/bin/go test ./internal/cli -run '^$' \
  -bench '^BenchmarkInspectProgram$' -benchmem -benchtime=150ms -count=6 -cpu=1
```

| Functions / mode | Median before | Median after | Allocated before / after |
| --- | ---: | ---: | ---: |
| 128 / inspect | 5.136383 ms | 4.449021 ms | 1,830,710 / 1,554,887 B |
| 256 / inspect | 10.052489 ms | 8.946658 ms | 3,758,385 / 3,172,834 B |
| 512 / inspect | 20.477194 ms | 18.234303 ms | 7,726,314 / 6,610,022 B |
| 512 / scoped diagram | 6.633205 ms | 4.149478 ms | 3,032,748 / 1,910,912 B |
| 512 / legacy diagram control | 2.914939 ms | 2.944214 ms | 1,286,129 / 1,286,129 B |

Across the three sizes, inspect improves 11–13%; scoped diagrams improve 37–39%.
Legacy diagrams vary -1.6% to +1.0% with identical allocation counts.
The benchmark includes file output on prechecked simple functions, excluding
checking, process startup, stdout behavior and complex call graphs.
No total-command speedup is claimed.

## Validation

- Exact code-head independent gpt-6.1-sol review: no findings. Six focused CLI
  tests passed independently: TestReviewAndDiagramFormats, TestDiagramViews,
  TestDiagramFlowAndScopeNeedAnEntity, TestReviewExplainAndDiagramDiff,
  TestSourceCommandsNeedNoNativeToolchain and
  TestSourceCommandsRetainProjectEntryValidation.
- Nine before/after command variants preserve status, stdout and stderr bytes:
  check JSON; inspect JSON including BuildID and GoLocals; legacy ASCII/Mermaid;
  scoped calls ASCII/Mermaid; flow; scope; emitted Go. The source fixture
  includes methods, locals and calls.
- Full `internal/cli -count=1`, integration `make repo-check` and scoped
  `go vet` passed.
- Integration Linux amd64 `make dist-check` passed: packaged compilation,
  source tooling, LSP, terminal/DAP debugging and profiles used only ms,
  without system Go, dlv or downloads.
- Integration validation used the initial baseline plus the three package
  candidates. Final branch-head review and required CI gate publication/merge;
  these notes do not claim that pending remote CI has passed.

