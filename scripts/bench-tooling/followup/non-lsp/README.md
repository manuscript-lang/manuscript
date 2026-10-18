# Non-LSP tooling efficiency probes

Base under review: `aa3efa7296e8b02f1ca1aa26a144debcd69dc7d8`.
Production files are not edited. The generated `overlay.json` adds only external test files to
`pkg/tooling` and `pkg/tooling/guide`. No LSP or extension workloads are repeated.

Prepared cases:

- `CompareFacts` on identical chain graphs of 256/512/1024 entities. This isolates
  eager all-entity reverse reachability, including a review returning no changes.
- 128/256/512 valid long arithmetic statements, both isolated
  `groupStatementExpressions` and full `Format`; input size grows with statement
  count. Contract check ensures every expression actually receives parentheses.
- Checked-source chains 128/256/512: `Inspect`, `CollectFacts`, `LintProgram`, with
  compilation outside the timed region. These are representative controls;
  compile time is deliberately not added to consumer timings.
- Fixed shipped standard library: warm `Page("json")`, a byte-identical page
  rendering from an already materialized module, and warmed `Search`. These are
  not interchangeable query types; the render control isolates repeated complete
  API snapshot materialization, and the contract test compares identical bytes.
- A small output-count probe confirms or rejects the static suspicion that 300
  independent call roots exceed the documented 200-node cap. It deliberately
  expects the base behavior and is not a proposed production regression test.

Historical commands below record the original absolute executor paths. To rerun
in another checkout, use the retained `prepare.py` to generate a fresh overlay.
For exact historical inputs, select commit `5facbb5ff966904e0b6fe918245d7df7885937ff`;
newer standard-library changes can change guide measurements. For example:

```sh
python3 scripts/bench-tooling/followup/non-lsp/prepare.py --repo "$PWD" --out /tmp/non-lsp-review
GOCACHE=/tmp/manuscript-go-cache GOMAXPROCS=2 toolchain/go/bin/go test -vet=off -overlay=/tmp/non-lsp-review/overlay.json -run '^TestNonLSP(ProbeContracts|GuideProbeContract)$' -bench '^BenchmarkNonLSP' -benchtime=1x -count=5 -benchmem ./pkg/tooling ./pkg/tooling/guide
```

The probe `.go.txt` files are complete Go source kept outside production package
discovery. Preserve their bytes when generating the overlay. Do not run timed
probes concurrently with other heavy work. Original commands:

```sh
GOCACHE=/workspace/tooling-perf-review/go-cache GOMAXPROCS=2 toolchain/go/bin/go test -vet=off -overlay=/workspace/tooling-perf-followup/non-lsp/overlay.json -run '^TestNonLSP(ProbeContracts|GuideProbeContract)$' -bench '^BenchmarkNonLSP' -benchtime=1x -count=5 -benchmem ./pkg/tooling ./pkg/tooling/guide > /workspace/tooling-perf-followup/non-lsp/bench.txt 2>&1
GOCACHE=/workspace/tooling-perf-review/go-cache GOMAXPROCS=2 toolchain/go/bin/go test -vet=off -overlay=/workspace/tooling-perf-followup/non-lsp/overlay.json -run '^$' -bench '^BenchmarkNonLSPReviewUnchangedChain/N1024$' -benchtime=500ms -count=1 -cpuprofile=/workspace/tooling-perf-followup/non-lsp/review.cpu.pprof -memprofile=/workspace/tooling-perf-followup/non-lsp/review.mem.pprof -o /workspace/tooling-perf-followup/non-lsp/tooling.test ./pkg/tooling > /workspace/tooling-perf-followup/non-lsp/review-profile.txt 2>&1
GOCACHE=/workspace/tooling-perf-review/go-cache GOMAXPROCS=2 toolchain/go/bin/go test -vet=off -overlay=/workspace/tooling-perf-followup/non-lsp/overlay.json -run '^$' -bench '^BenchmarkNonLSPFormatter/GroupExpressions/N512$' -benchtime=500ms -count=1 -cpuprofile=/workspace/tooling-perf-followup/non-lsp/format.cpu.pprof -memprofile=/workspace/tooling-perf-followup/non-lsp/format.mem.pprof -o /workspace/tooling-perf-followup/non-lsp/tooling.test ./pkg/tooling > /workspace/tooling-perf-followup/non-lsp/format-profile.txt 2>&1
```

Preparation environment: pinned Go `go1.25.1 linux/amd64` matching `.go-version`;
module `go 1.25.0`; toolchain resolves to the prepared review toolchain. Actual
benchmark environment, execution status, sample counts and results are in
`report.md` and `metadata.json`. Five repeats support descriptive medians/ranges, not
confident p95 estimates. Source review alone does not establish observed latency.

`TestNonLSPNodeCapNegativeControl`, added after the initial series, is deliberately
expected to fail on current production: 300 independent roots exceed nodeCap200.
It is excluded from the ordinary success/benchmark command above. Run it alone
with `-run '^TestNonLSPNodeCapNegativeControl$'` to reproduce its logged failure.
