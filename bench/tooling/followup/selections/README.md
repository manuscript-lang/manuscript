# External strict-selection and peak-memory probes

Scope: measurement only. No production or repository-test edits, no checked-graph cache, no change to selection/recovery/rename behavior. The added observer hooks are generated into Go overlay copies outside the checkout.

`prepare.py` copies the current compiler CompileFile entry, sourceIndex entry, and lexer Lex entry into external overlay files and inserts a nil observer branch. Separate new overlay hook files define the callbacks. Source SHA-256 values, repository HEAD, working-diff summary, and probe digest are retained with each build.

`run.py` prepares/builds the probe with the checkout's pinned SDK, then starts a fresh test process for each fixture/operation/mode. Runs fix GOMAXPROCS=4, GOGC=100 and GOMEMLIMIT=off. The fixture matches the retained review's star application shape: one main importing 40 or 100 leaf modules, 20 functions per leaf, Unicode comments. A library switch omits entry and therefore gives every strict selection the full discovered graph; smaller library controls can expose this amplification without a large all-graph retention experiment.

The real serial `server.handle` paths execute workspace symbols, cross-file references, and rename. The server begins with one ordinary recovering open-document snapshot and lazily built index/lint, just as a warm open editor would. Each repeated rename starts from the same unmodified live sources: edits are validated and returned, never applied to disk. Assertions check exact symbol counts, cross-file reference output, two changed rename documents, at least declaration/import/call edits, and the requested replacement text.

Counts and memory run separately:

- Counts: actual CompileFile calls keyed by input path and SHA-256 of the complete compiler.Options struct, including sorted effective overlay content. This captures per-target source override and all options; sharing a graph or selecting the same file under a different overlay is not an exact repeat. Before/after rename groups distinguish whether the effective source overlay contains the unique requested new name. All raw selection keys and repeat counts are retained. The probe counts sourceIndex calls, project modules traversed by those indexes, all lexer calls and @std lexer calls/bytes. It retains scalar/string/hash counters, never Program pointers, occurrences, or source graph objects.
- Memory: hooks stay nil, no selection fingerprints/counter maps are constructed. A 2ms goroutine samples Go HeapAlloc and Linux `/proc/self/statm` RSS and records observed maxima plus sample counts. These are sampled lower bounds, not exact peaks. ReadMemStats and RSS sampling can perturb latency, so elapsed times are only workload context. Every request also has before/after forced-GC heap/RSS points; close/invalidate has a final forced-GC point and explicit cache-map counts. Sampling stores aggregate maxima rather than an unbounded trace. The process is an instrumented Go test binary, not the shipped editor/CLI process; absolute RSS belongs to that test process. Go RSS can remain high after heap objects die because the runtime retains pages.

Historical measurements used commit `5facbb5ff966904e0b6fe918245d7df7885937ff`.
Select that revision for identical pinned standard inputs. The retained probe is
`probe_test.go.txt`; preparation maps it into Go package discovery without editing
production source. Run from this artifact directory and pass the checkout explicitly.
Use an isolated CPU window. Suggested pilot:

```
GOCACHE=/tmp/manuscript-tooling-go-cache python3 run.py --repo /path/to/checkout --label pilot --modules 5 --functions 3 --repeats 1
```

Main application matrix (three requests per operation/process, six processes per size):

```
GOCACHE=/tmp/manuscript-tooling-go-cache python3 run.py --repo /path/to/checkout --label application --modules 41,101 --functions 20 --repeats 3
```

Bounded library control:

```
GOCACHE=/tmp/manuscript-tooling-go-cache python3 run.py --repo /path/to/checkout --label library --modules 11,21 --functions 20 --repeats 3 --library
```

A new run output directory retains `overlay.json`, `inputs.json`, instrumented source copies, `build.log`, test binary, raw per-process logs, all parsed `measurements.json`, and aggregated `summary.json`. The aggregate reports before/after strict exact-repeat counts separately and individual memory deltas/sample counts rather than presenting three repeated requests as independent process samples.

No optimization is implied by a repeated-key count. A safe reuse proposal must also preserve strict selected-root diagnostics and rename before/after separation, and must bound retained checked graphs. In particular, library selection amplification can make retaining one graph per selected file quadratic. Report measured duplication and transient/retained memory first; prefer an existing one-result/index reuse or a strictly bounded single-owner alternative over an N-graph request cache.

The published historical matrices retain raw process logs, source/probe hashes,
working diff and summaries. Generated source copies and test executables remain
local executor artifacts and are regenerated by `prepare.py`/`run.py`.
