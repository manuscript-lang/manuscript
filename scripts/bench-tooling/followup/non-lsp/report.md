# Non-LSP tooling coverage and efficiency assessment

Base: `aa3efa7296e8b02f1ca1aa26a144debcd69dc7d8`, workspace `/workspace/manuscript-tooling-followup`.
Read-only production review; all probes/evidence are external Go overlay files here. No LSP or VS Code measurements repeated. Current Go is pinned `go1.25.1 linux/amd64` matching `.go-version` (module go1.25.0). Source references describe the base; other agents' concurrent working-tree files are outside this assessment.

## Coverage inventory

| Surface | Implementation traced | Observed work / evidence limits |
| --- | --- | --- |
| Formatting and checked redundant labels | `format.go`, `format_layout.go`, `format_paragraphs.go`, `redundant_labels.go` | Strict parse before/after plus layout's additional parse/lex passes; concrete full-source rebuild per inserted parenthesis and per removed label. Nested layout flat strings can be recomputed. Multiple passes are not by themselves a demonstrated bottleneck; preserve semantics, comments and idempotence. |
| Source/semantic lint and individual rules | `lint.go`, `lint_program.go`, `capture_lint.go`, `result_lint.go`, `pattern_lint.go`, `nested_match_lint.go`, `optional_match_lint.go`, `result_match_lint.go` | Shared checked identities, expression/type maps and syntax visitor already avoid a second lexical approximation. Multiple bounded rule passes; nested callback exclusion can revisit nested bodies. No ordinary-input superlinear timing claim yet. |
| Inspection and standard declarations | `inspect.go`, `standard_sources.go` | Materializes locals/entities/calls/statements, source hashes, sorted collections, JSON identity bytes and BuildID even for consumers needing a subset. `sourceSpan` scans from each position to end-of-line, so extremely long lines can repeat scans. Full outputs may legitimately require these collections. |
| Facts and ordered flow | `facts.go`, `flow.go` | `CollectFacts` always builds full `Inspect` then derived graph maps, flow trees, per-callable try/with counts. Calls/imports use linear `appendUnique` scans per owner, potentially quadratic for one very high-fanout owner. Flow expansion has a node cap; fact construction still precedes the cap. |
| Review and diff | `review.go`, `report.go`, `diff.go`, `mark.go` | Eager all-entity reverse reachability for every comparison, even no-op. Touched-line ownership scans all facts in a file per changed line. Unified diff parsing/reversal uses indexed sequential source slices and builders/join rather than reapplying every hunk to the full string. Report rows are assembled before final row caps; digest hashes the rendered ASCII body, and final row caps do not bound all report construction. |
| Diagrams and views | `diagram_ascii.go`, `inspect.go:Diagram`, `views.go`, `flow.go`, `mark.go` | ASCII aggregates unique edges; Mermaid shares node IDs, though label replacers are rebuilt per node. Calls/effects/errors roots are all expanded despite the advertised200-node cap; modules view also bypasses cap. Output count needs a direct probe; no latency claim from source. |
| Guide search/pages | `guide/search.go`, `guide/std.go`, `guide/guide.go` | Search indexes standard declarations once using sync.Once; query scoring scans index and sorts matches before truncation. Typo distance builds a small full matrix for similar-length words; documentation prose excludes typo/subsequence matching; exact/prefix/substring matches remain. `Page` rebuilds all detached standard API metadata through `modules()->StandardLibrary()` for each request; output budget does not bound that input work. `capDoc` repeatedly converts/shrinks a rune slice for long docs; fixed shipped doc sizes limit practical relevance. |
| Documentation generation/quality | `docgen/documentation.go`, `coverage.go`, `description_policy.go` | Builder-based rendering, one module/declaration/member traversal for inventory, map-based backlog validation. `SiteFiles` obtains StandardLibrary once then calls `StandardLibraryMarkdown`, which obtains it again. Full Markdown and JSON output materialization is intentional; duplicate detached snapshot assembly is avoidable. No benchmarks of docgen were pre-existing. |

Existing performance evidence: `rg -n '^func Benchmark' pkg/tooling --glob '*test.go'` finds benchmarks under LSP only, none in the surfaces above. Existing unit/fuzz tests primarily constrain semantics/determinism/bounded output and do not establish complexity. No production performance changes are proposed solely because a map, visitor or materialized output exists.

## Ranked concrete candidates

1. **Review reachability:** `review.go:48–49,254–277` computes reverse BFS from every entity before checking whether changes exist: O(V(V+E)) worst-case and repeated visited maps. Only changed scored findings consume reach (`classify` lines 121–129). Small remedy: build reverse adjacency once and compute reach lazily for findings that actually use it; preserve cycle dedup and ranking/determinism. No-op and internal-body-only changes should avoid reach traversal. Do not introduce SCC/all-pairs machinery before profiling a workload that changes many entities.
2. **Formatter edit application:** `format_layout.go:774–781` rebuilds the entire source for each insertion, O(insertions × source bytes). `redundant_labels.go:58–60` repeats that pattern for deletions. Small remedy: sort edit positions and emit unchanged spans plus insertions/cuts once into a pre-grown builder; preserve same-position ordering and byte offsets. Representative long arithmetic statements actually exercise the insertion mechanism; full Format and helper probes separate parse/layout cost from application cost.
3. **Guide page metadata:** `guide/std.go:74–82,156–163` invokes `checker.StandardLibrary()` per page. That exported API deliberately creates a detached documentation snapshot (`pkg/checker/documentation.go:42–74`), including source excerpts and method docs; the underlying standard type loader's sync.Once does not cache that snapshot. Small remedy: private once-built sorted guide module metadata, internally read-only, consistent with existing Search's private cached index. Preserve public checker's detached/mutable-caller contract and page bytes. A pre-materialized json module is an exact render-only control.
4. **View output cap:** `views.go:48–50` caps descendants inside expand but does not limit independent roots. `modulesView:180–202` has no equivalent check. Enforce a consistent node budget across roots, descendants and module/import nodes, with deterministic omitted count. This is a concrete output-bound contract issue; quantify root count rather than infer UI latency.
5. **Docgen duplicate snapshot:** `docgen/documentation.go:91–96,113–119` obtains the same immutable standard API metadata twice within SiteFiles. Render the plain Markdown from the already held module snapshot through a private helper. `scripts/docgen/main.go:25` separately constructs a snapshot for Inventory before SiteFiles; route that cross-owner observation to its owner rather than changing script scope here.

Cross-owner observation for the CLI owner: `internal/cli/source.go:82` eagerly calls Inspect; `inspect` later calls `inspectionWithGoLocals` (`debug_names.go:96–97`) which calls Inspect again, and `diagram --view` calls `CollectFacts` which also invokes Inspect. Plain diagram uses its first inspection. Moving the first Inspect into the plain-diagram branch avoids duplicate complete work; no internal production files edited here.

## Measured results and validation

Executed with the exclusive CPU slot at candidate **`5facbb5ff966904e0b6fe918245d7df7885937ff`**. The nine measured non-LSP production source hashes match base `aa3efa72` byte-for-byte (`source-sha256.txt`, `metadata.json`); parent later advanced HEAD while collecting metadata, recorded separately as `metadata_collection_head`. Linux x86_64, AMD EPYC9V7480-Core Processor, pinned Go1.25.1, `GOMAXPROCS=2`, writable `GOCACHE=/workspace/tooling-perf-review/go-cache`. Initial default-cache invocation failed before tests due read-only home; the configured run succeeded.

Five **one-iteration** benchmark repetitions per case in each package test process, summarized by median; these are not independent fresh-process replicates. Fixed-iteration data is descriptive and includes normal per-operation allocation/GC effects; it is not a confident p95 or end-to-end CLI latency estimate. Compilation/setup are outside the measured consumer regions. Synthetic Facts isolate review's real graph algorithm; formatter input is valid source containing many long arithmetic bindings; Inspect/Facts/Lint controls use checked function-chain source. Guide compares the real fixed shipped standard library against an exact same-page render-only control, with standard types and search index already warm.

| Workload | N | Median ms/op | Median B/op | Median allocs/op |
| --- | ---: | ---: | ---: | ---: |
| No-op CompareFacts chain |256|4.199|3,467,240|35,895|
| No-op CompareFacts chain |512|15.944|13,783,336|138,561|
| No-op CompareFacts chain |1024|69.652|55,043,096|541,906|
| Group long formatter expressions |128|15.067|19,013,296|30,009|
| Group long formatter expressions |256|32.499|51,359,056|59,908|
| Group long formatter expressions |512|71.577|142,768,688|119,699|
| Full Format on those statements |128|41.885|63,727,744|122,005|
| Full Format on those statements |256|96.460|147,776,304|243,589|
| Full Format on those statements |512|253.208|342,822,608|486,713|
| Warm Page(json), fixed library |—|16.131|15,971,472|49,863|
| Identical page render-only control |—|0.031|8,576|54|
| Warm Search(read file), fixed library |—|1.107|46,744|271|

Review time grows3.8x then4.4x per doubling, allocation bytes4.0x then4.0x: the eager all-entity reachability mechanism is measured, including a comparison with no changes. Formatter group allocation grows2.7x then2.8x while input size doubles; full formatter grows2.3x then2.6x in time. This confirms superlinear cost in this workload, without claiming that the full formatter's measured growth is exactly quadratic or that all parse/layout cost can be removed.

Checked-chain controls at128/256/512 functions: Inspect medians0.346/0.692/1.396ms; CollectFacts0.514/1.064/2.052ms; LintProgram0.146/0.306/0.616ms. These cases show approximately linear growth. They do not rule out long-line, high-fanout or nested-callback cases described as static suspicions above. Full allocation samples and ranges for all21 benchmark cases are retained in `bench.txt` and `summary.json`.

Two requested **500ms-target** CPU/allocation captures completed (Go reported7 timed iterations each, with separate benchmark calibration). Review CPU capture:1.20s wall,1,260ms aggregate sampled CPU; reachCounts accounted for74.6% cumulative sampled CPU and98.84% sampled alloc_space. Formatter grouping capture:805ms wall,1,070ms aggregate sampled CPU; allocation line attribution assigns **614.61MB** to `format_layout.go:780` full-string concatenation, out of1,100.24MB sampled total (~55.9%). Lexer token emission also accounts for29.0% of sampled allocations, so string concatenation is a large attributable subset rather than all formatter cost. Aggregate sampled CPU can exceed wall time because GC runs with two threads. Profile allocation totals include calibration/setup; do not divide them by the7 displayed timed iterations. Use `*-cpu-top.txt`, `*-alloc-top.txt`, and `*-alloc-lines.txt` alongside raw pprof files.

Validation: `TestNonLSPProbeContracts` passes: identical Facts produce no findings,16 long expressions receive32 parentheses, and full formatted source is idempotent. `TestNonLSPGuideProbeContract` passes with byte-identical json page output. The independent-root baseline observation reports300 nodes for nodeCap200. A separate expected-failing regression (`TestNonLSPNodeCapNegativeControl`) asserts the cap and fails with exactly **300 >200**, confirming the output-bound gap without relying on a latency inference. This extra negative test was added after the initial benchmark series; benchmark functions were unchanged. It is excluded from the reproducible success/benchmark command.

All sources/probes are external overlays, with hashes in metadata. `README.md` contains exact reproducible commands; `contracts.txt`, `nodecap-negative-control.txt`, `review-profile.txt` and `format-profile.txt` retain exit evidence. No production files were edited, and the CPU slot has been released. The measured review/formatter/guide work now supports bounded implementation proposals; docgen duplicate snapshot and CLI duplicate Inspect remain source-proven work counts with consumer cost controls, not measured end-to-end savings.

## Later main reconciliation

The source and timing review above is historical at the stated revision. Main
`95ec85602c3d08a8de6d96de45df89e80bbd2d2a` includes CLI fix
[#671](https://github.com/manuscript-lang/manuscript/pull/671), which moves
`Inspect` into the plain-diagram branch and removes the duplicate work described
above. That cross-owner finding is resolved. The nine listed non-LSP tooling
production files remain byte-identical; dependencies such as the lexer changed,
so the historical timings are not relabeled as latest-main measurements.
