# Owner watcher research — WITHHELD

**Final decision: do not ship this production patch or stage3 watcher batching. Keep the current global invalidation.** Independent review demonstrated stale analysis through closed lexical symlink routes and cross-owner editor overlays. The measured optimization is incomplete; favorable timings do not establish correctness. The parent will publish this evidence as a docs-only closeout.

Public baseline `3232c8db008fe60804f88bb8a243d15ce8da0a14`; held experimental source `50d3b1c804b1d5801a54ce6903189229cd8868d6`. These share the merged pinned lexical-token cache and all non-LSP sources. Only five LSP files differ (server/snapshot/watch/watch tests/scheduling test); canonical discovery is absent. No production push/PR or batching implementation occurred.

The [final independent HOLD review](final-hold-review.md) supersedes earlier approvals. The [original proposal](original-implementation-plan.md) and [preimplementation review](preimplementation-review.md) are historical evidence, superseded by the final HOLD. The [future upstream input-footprint decision](future-input-footprint-decision.md) identifies the concrete missing contract. The [per-open footprint proposal](rejected-overlay-footprint-plan.md) was not implemented because closed routes disprove its completeness.

## Descriptive measurements, not shipping results

Five balanced baseline/candidate pairs, alternating order,20 fixed operations per sample at2/4/8 independent roots,4 dependency modules and8 functions/module per root. Both watcher and ordinary didChange/publication workloads were measured:30 samples/head,600 timed operations/head,1200 total. Fixture disk writes and fresh analysis validation run outside timers. Every operation checks refreshed A success/error against actual disk mutation and fresh uncached analysis. Linux amd64, AMD EPYC9V74, pinned Go1.25.1, GOMAXPROCS2, warm filesystem/build caches; exact source hashes, standard-source tree and .msversion pins are in each metadata.json.

| Roots | Owner event median ms/op, base → held candidate | Median B/op, base → held candidate | Compilations and diagnostic publications/op |
| --- | --- | --- | --- |
| 2 | 1.542 → 0.834 | 850812 → 426765 | 2 → 1 |
| 4 | 3.035 → 0.882 | 1819255 → 462205 | 4 → 1 |
| 8 | 6.315 → 1.142 | 3971326 → 534049 | 8 → 1 |

Independent B's Program is retained in every candidate watch operation and none of the baseline operations. These simple local-path fixtures expose saved work but omit the legal alias dependencies that later falsified the optimization.

| Roots | Ordinary change median ms/op, base → candidate | Median B/op, base → candidate | Time median change |
| --- | --- | --- | --- |
| 2 | 1.296 → 1.345 | 901441 → 918142 | +3.7% |
| 4 | 2.884 → 2.747 | 1870271 → 1903439 | -4.8% |
| 8 | 6.450 → 6.833 | 4029123 → 4091102 | +5.9% |

Ordinary allocations increase about1.5–1.9%; all ordinary sample time ranges overlap. Compilations/publications/FindManifest counts remain2/4/8 on both sides; LSP EvalSymlinks counts remain6/12/24. Capturing the actual analyzeWith selected target removed the initial duplicate-preselection overhead. Watch manifest counts are2/4/8 baseline versus3/5/9 candidate because watcher reselects every open context before compiling affected A. Do not infer no typing regression, peak memory, actual host/wire latency or p50/p95 from five fixed samples.

`final-pairs/` retains all raw samples, allocation/operation counts, execution order, source/pin metadata, rows.json and summary.json (median/min/max). Instrumentation wraps only LSP calls to CompileFile, FindManifest and EvalSymlinks; compiler internals are not counted. Go benchmark allocation/time scope includes actual in-process handle compilation and diagnostic serialization, without extension-host transport. No fresh-validation cache reuse was introduced.

## What passed, and what invalidated the candidate

The exact50d full LSP package suite passed1.971s (`final-tests.txt`). It covered whole-owner default/Module eviction, independent B index/lint identity and publication silence, retained Program-derived ownership, parent/nested hidden imports, missing dependencies, source/test library discovery, failed/invalid/new/deleted manifests, malformed/empty events, standard sentinels, pending didChange diagnostics, actual selected target interleaving, and deleted/retargeted local aliases. These checks were insufficient. Final independent review blocks shipping; no final race/build/CI gate was run after the decision to withhold.

**Closed routes:** `closed-routes/probe_test.go.txt` and `repro.log` preserve six actual filesystem observations: relative import, manifest alias and manifest entry through closed A/link.ms resolving into B, each with A closed or an independent A document open. After replacing the link with a regular outside file, cached B still succeeds with the identical Program while fresh B correctly reports an escape error. This observation test deliberately PASSES only when the bug is reproduced; its PASS is not correctness acceptance.

**Open overlays:** `overlay_footprint_probe_test.go.txt` and `overlay-footprint-50d-negative-control.txt` retain four failing correctness controls: file/directory symlink × delete/retarget. A's ordinary URI was never requested, but its unsaved text entered B physically. B wrongly retains its old type failure while fresh B succeeds from disk. An unrelated C is materialized with index/lint and checked for identity/publication retention. The probe FAIL is the expected falsification of the candidate.

No extra compiler graph, heuristic config/import parser or production footprint patch was added after these results. The [future API decision](future-input-footprint-decision.md) is the concrete next boundary, rather than silently deferring unspecified optimization.

## Portable source and reproduction

`experimental-owner-candidate.patch.txt` is the complete immutable3232→50d production/test patch. The unpublished50d Git object is unnecessary: reconstruct its source in a disposable checkout, make a local commit and use that commit with the loaders. Its SHA differs, but source hashes and standard pins must match retained metadata. Never merge this research patch as a remedy.

```sh
ROOT=/path/to/manuscript
GO=/path/to/go1.25.1/bin/go
CACHE=/tmp/owner-go-cache
ARTIFACT=/absolute/path/to/owner-watch
git -C "$ROOT" worktree add --detach /tmp/owner-research 3232c8db
git -C /tmp/owner-research apply "$ARTIFACT/experimental-owner-candidate.patch.txt"
git -C /tmp/owner-research add pkg/tooling/lsp
git -C /tmp/owner-research -c user.name=Reproduction -c user.email=reproduction@example.invalid commit -m 'Local held owner research source'
python3 "$ARTIFACT/run_owner_probe.py" --checkout /tmp/owner-research --commit 3232c8db --go "$GO" --cache "$CACHE" --output /tmp/owner-base --count 5 --iterations 20
python3 "$ARTIFACT/run_owner_probe.py" --checkout /tmp/owner-research --commit HEAD --go "$GO" --cache "$CACHE" --output /tmp/owner-candidate --count 5 --iterations 20
# Exit0 confirms six stale-cache observations, not successful invalidation:
python3 "$ARTIFACT/run_alias_control.py" --checkout /tmp/owner-research --commit HEAD --go "$GO" --cache "$CACHE" --output /tmp/owner-closed-control --case closed
# Expected exit1: four correctness assertions fail on the held candidate:
python3 "$ARTIFACT/run_alias_control.py" --checkout /tmp/owner-research --commit HEAD --go "$GO" --cache "$CACHE" --output /tmp/owner-open-control --case open
```

For the recorded balanced order, run one sample (`--count 1`) per side for sample0–4, reversing side order on odd samples; `final-pairs/execution-order.json` retains the actual run order. These loaders use temporary read-only Go source overlays and remove generated sources afterwards. `.go.txt` prevents normal package discovery. They reject tracked non-LSP checkout differences; use a compatible isolated3232 checkout so actual compiler/standard sources match the selected commit. No binaries, generated full checkout, absolute-path-only overlay or publishing action is required.
