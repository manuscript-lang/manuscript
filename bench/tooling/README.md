# Tooling performance review and controls

The review found repeated checking/indexing, obsolete diagnostics and VS Code
client ownership bugs. The bounded fixes retain full uncanceled results and
conservative source-generation invalidation. They do not establish that every
editor operation is fast: large completions and workspace queries remain costly.

## Reproduce

Use a checkout with its pinned SDK and built `ms` (`make build`), Python 3,
and `GOMAXPROCS=4`. Run the harness from the repository root against isolated old/new
checkouts. Each output directory is disposable; fixture source is generated
deterministically and never written into either measured checkout.

```sh
python3 bench/tooling/wire_bench.py --repo /path/to/before --out /tmp/tooling-before --sizes small:2:10,medium:40:20 --samples 20 --cold 7
python3 bench/tooling/wire_bench.py --repo /path/to/after --out /tmp/tooling-after --sizes small:2:10,medium:40:20 --samples 20 --cold 7 --allow-coalescing
python3 bench/tooling/wire_bench.py --repo /path/to/after --out /tmp/tooling-large --sizes scaling:100:50 --samples 5 --cold 3 --allow-coalescing
python3 bench/tooling/compare_protocol.py --before /path/to/before/ms --after /path/to/after/ms --out /tmp/tooling-equivalence
MANUSCRIPT_SNAPSHOT_EXPECT_PROGRAMS=1 python3 bench/tooling/memory.py --repo /path/to/after --out /tmp/tooling-heap-after.log
MANUSCRIPT_SNAPSHOT_EXPECT_PROGRAMS=10 python3 bench/tooling/memory.py --repo /path/to/before --out /tmp/tooling-heap-before.log
python3 bench/tooling/assertion_controls.py --binary /path/to/after/ms --out /tmp/tooling-controls
python3 bench/tooling/helpers.py --repo /path/to/before --out /tmp/tooling-helpers-before.txt
python3 bench/tooling/helpers.py --repo /path/to/after --out /tmp/tooling-helpers-after.txt
```

Use `--allow-coalescing` only with the new server. It requires the newest edit's
diagnostics and valid complete results, while allowing intermediate obsolete
versions to be omitted. An explicit request barrier between malformed/restored
source in `compare_protocol.py` requires both diagnostics versions. The memory
probe uses a temporary Go overlay with the same pre-existing private server APIs
on both revisions, without modifying either checkout. Set expected programs to
1 against the old server as a deliberate failing control. Assertion controls
must exit 0/1/0: positive, false assertion with `try`, false assertion whose
Result is deliberately ignored. An ignored Result alone is not a failing test.

Run correctness separately from timings:

```sh
toolchain/go/bin/go test -count=1 ./pkg/tooling/...
toolchain/go/bin/go test -race -count=1 ./pkg/tooling/lsp
make repo-check docs-check
```

## Environment and interpretation

Initial architecture review: `a3b14fbcc54bb72222567915656fb8be6920f1f4`.
Implementation baseline: `a988705cbd5ed9c7424ac891aa42893c2805474a`.
Final measured implementation: `767c70b34754c4be6b42062f38211583f05d7877`,
including current main `b8c9cc0cf3a436fdaf2b93e6d79516013307a039`.
Later evidence-only commits do not change production code. Earlier isolated
stages are recorded separately in results. Baseline and final were measured
sequentially on the same host, without other local test/benchmark processes.

Linux amd64, AMD EPYC 9V74, cgroup quota 4 CPUs/16 GiB, Go 1.25.1, GOMAXPROCS=4,
Python 3.12.14; available Node 24.19.0 versus repository pin 24.13.0. Per-series
metadata records kernel, revision, fixtures and observed process memory; newer
harness runs also record the executable SHA256 and tracked-diff digest.

Wire timings cover stdio frame write through response/notification receipt,
including server work and JSON. A new process defines cold startup; OS page
cache is uncontrolled/warm. First-open timings exclude process launch/initialize.
Warm sessions have initialized and opened their documents; their series include
the first lazy occurrence-index miss. Features run in harness order, so semantic
tokens reuse the index built by hover. No measurements came from a real VS Code
extension host or graphical editor; editor rendering, actual watcher debounce,
native process survivors and event propagation remain unmeasured.

Each number is milliseconds. Median is p50; p95 is nearest-rank and reported
only for n>=20. Small final/medium warm requests and edits have n=20. Small
baseline and large warm requests/edits have n=5. Bursts/workspace queries have
n=3; cancellation is one immediate-cancel observation per configuration, not a
latency percentile. Fresh-process samples: medium 7/7, small 3/7, large 3/3.
Raw samples, exact counts and min/max remain in [results](results/).

| Fixture | Modules | Functions | Bytes | Open tabs |
| --- | ---: | ---: | ---: | ---: |
| Small | 3 | 21 | 1313 | 1 and 3 |
| Medium | 41 | 801 | 48477 | 1 and 10 |
| Large | 101 | 5001 | 295137 | 1 and 10 |

## Measured results

Medium, ten tabs; before -> final p50 / p95:

| Operation | Before | Final |
| --- | ---: | ---: |
| Hover | 28.47 / 45.11 | 0.134 / 0.216 |
| Definition | 23.17 / 31.83 | 0.213 / 0.274 |
| Semantic tokens | 258.45 / 272.71 | 0.382 / 0.746 |
| Completion | 42.76 / 48.61 | 41.53 / 45.03 |
| Edit to all diagnostics | 104.76 / 111.21 | 13.77 / 14.51 |
| Ten-edit burst to newest diagnostics (n=3 median) | 1071.94 | 13.33 |
| Workspace symbols (n=3 median) | 705.98 | 490.40 |
| References (n=3 median) | 743.49 | 511.88 |

The first hover still builds its index: final medium 22.03 ms and large
61.23 ms in these samples. Final signature help is 9.09/10.81 ms. Completion
does not improve materially on this fixture; its private repaired analysis
remains separate. Fresh-process first-open medians were small 31.42->31.92,
medium 54.09->43.89, large 115.56->98.32; these small, variable samples do not
establish a startup speedup. Initialization remains about 3 ms.

| Large, ten tabs (median, n=5 except burst n=3) | Before | Final |
| --- | ---: | ---: |
| Hover | 81.30 | 0.189 |
| Semantic tokens | 1002.08 | 1.540 |
| Completion | 188.29 | 176.53 |
| Edit to all diagnostics | 641.33 | 60.60 |
| Ten-edit burst to newest diagnostics | 6342.33 | 61.28 |

Small/three-tab all-diagnostics medians are 1.94->1.09 ms; ten-edit bursts
20.28->1.36 ms. On every measured ten-tab burst the old server published
100 notifications and the new server published 10 with the latest version.
This is intentional coalescing, not less checking of the final source.

Three post-GC samples of an identical ten-module, 100-functions/module library
showed median ordinary graph retention above a warmed baseline falling from
37,355,960 bytes (10 Programs) to 3,737,816 bytes (one Program); all ten URI
aliases remain. Closing/invalidation releases them. This is retained Go heap,
not peak transient workspace memory. End-of-scenario large-process RSS/HWM were
299272/568060 KiB before and 108068/173916 KiB final. These are one process
observation each, include GC/allocator behavior and are not leak/peak guarantees.

The earlier semantic-module hoist alone reduced an identical Go helper from
220–228 to 21–23 ms/op, 101.58->27.56 MB/op, 764300->89457 allocations/op.
Declaration indexing at 4k functions fell 325–370->53–54 ms/op; a 4k declaration
documentation sweep fell 180–197->4.6–4.9 ms/op and 265.25->3.10 MB/op.
These are 2–3 benchmark means, with raw iterations retained, not editor p95s.
The documentation and large unchecked-source helper wins do not imply that
ordinary completion improved by the same factor.

## Ranked findings, fixes and remaining work

1. **Duplicate graph/index work and obsolete edit publications: measured, high
   confidence/high impact.** [checkedDocument](../../pkg/tooling/lsp/server.go#L188),
   [generation caches](../../pkg/tooling/lsp/snapshot.go#L41), and
   [serial batching](../../pkg/tooling/lsp/server.go#L109) now share ordinary
   recovering graphs/indexes/lint and apply every queued range in order.
   Default and exact selected-module fallbacks remain separate. ScopeMarker
   repair and strict workspace checking stay uncached; ambiguous URI overlays
   bypass sharing. Whole-generation invalidation preserves dependencies without
   a new incremental compiler or parallel checker.
2. **Repeated source/module scans: measured, high confidence.** The
   [semantic loop](../../pkg/tooling/lsp/semantic.go#L52) resolves its document
   once; [positions](../../pkg/tooling/lsp/positions.go#L15), occurrence headers
   and [documentation](../../pkg/tooling/lsp/analysis.go#L195) use bounded local
   searches. UTF-16 positions retain the original-byte contract. Many tokens
   on one exceptionally long line still repeatedly scan that line prefix:
   a static scaling concern, not an editor workload measured here.
3. **Cancellation and workspace discovery: measured remaining cost, high
   confidence.** Cancellation is checked before dispatch, during discovery and
   between strict checks; a queued canceled workspace query no longer blocks
   the following hover in the observed probes (medium 734.69->0.206 ms, large
   1799.69->0.543 ms, n=1). [Workspace analysis](../../pkg/tooling/lsp/workspace.go#L144)
   still checks/indexes files transiently: final large symbols/references take
   about 1.50/1.42 seconds (n=3). A bounded next investigation should profile
   uncanceled scans and extract reusable declaration facts without retaining N
   selected checked closures. Compiler checks/index construction are not
   preemptible; cancellation behind the bounded unread transport queue also
   remains a limit. No arbitrary result truncation was added.
4. **VS Code lifecycle/watchers: reproduced with actual extension plus mocks,
   high confidence in control flow; native impact unmeasured.**
   [extension lifecycle](../../extensions/vscode/extension.js#L81) joins restarts,
   cleans failed starts, and joins shutdown. Twenty overlapping restart calls
   produce 1 replacement instead of 20; mock survivors after deactivate fall
   19->0. Pre-canceled 1000-manifest discovery performs 0 searches/creates 0
   tasks instead of 1/4000; uncanceled discovery still returns all 4000. The
   watcher now selects .ms and exact ms.toml; content/discovery cancellation
   tokens reach client10. Existing 250ms client watcher debounce remains; this
   is separate from immediate source edits. Complete extension suite: 30 pass,
   six native opt-in skips. Five new regression controls fail by assertion on
   old source. A real extension-host follow-up should measure activation,
   rapid restarts/deactivation and watcher propagation/RSS.
5. **MCP: no current implementation to benchmark.** The original #528 proposal
   removed MCP in commit a0e09e34 before squash 8b79f4e0. Current CLI agent
   search/guide and external integrations are not an in-repository MCP server.
   No MCP server was added by this work.

The protocol comparison asserts complete JSON equality for 14 feature results
and two diagnostic generations, with nonempty declaration/use/rename output
and a deliberate undefined-name error that clears on restoration. Root/URI,
overlay, malformed UTF-8/surrogate/CRLF, completion-repair, nested-manifest and
strict-rename regressions remain in the LSP tests. A deliberately removed
post-check rename cancellation checkpoint makes its new test fail; the old
server also fails the one-Program retention expectation.

Integrated local checks passed: all `pkg/tooling/...` tests (LSP 6.39s), LSP
race tests (25.44s), LSP vet, repo-check, docs-check, Python syntax, both old/new
helper-harness smoke runs, complete protocol equality, three final heap samples,
and the 0/1/0 native assertion controls. The rename-checkpoint mutation fails
by its intended assertion. Local book rendering was unavailable because Hugo
was not installed; the required CI book check covers it before merge.

Baseline CI failures are separate from performance findings: historical main
#643 had a FuzzFormat deadline timeout without a minimized counterexample;
the reviewed a3b14fbc main CI passed. Neither proves a tooling regression.
PRs #653/#654/#655 implement the first three independent stages; this directory
retains evidence for them and the shared-analysis stage. Required CI and an
independent review of each exact head gate publication/merge; see PR records
for the final check status.
