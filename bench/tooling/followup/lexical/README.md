# Finite standard lexical-cache validation

External probes only. Baseline and candidate are supplied as `--repo` arguments; the scripts capture exact HEAD/diff metadata. Comparisons must reject unequal pinned-source digests. The selected comparison is clean baseline `b49c0c99a3bc89176ce7598fbc1c53c651bfe770` and clean candidate `9c2296984c92a2f90c08c1353775150802765bae`, both after the same standard-library changes. Older aa3/5fac measurements are context only.

`run_index.py` builds a test overlay with no production code instrumentation. It provides:

- Two fresh-process first-index complete payload captures per fixture. Occurrences serialize key, name, all original position fields, end, declaration/write, every exported checker.Info field, stable Symbol/Binding/Method fields, complete type graph with deterministic graph references, and declaration/argument syntax with checker `Fact` annotations removed. Only fixture roots are normalized. A coverage guard fails if a new exported Info field is omitted. Full JSON artifacts and hashes are retained; pointer addresses are never formatted.
- Five independent fresh-process cold samples. Each compiles exactly the same fixture first, warming checker/standard sources equally without sourceIndex, forces GC, then times and counts allocations for the first sourceIndex. Dropping the index and forcing GC precedes inventory inspection or semantic serialization, so fixed retained memory is separate from payload-encoding caches. KeepAlive retains the same checked Program across the samples. Baseline temporary-buffer release is reported; the candidate-minus-baseline post-GC difference estimates the additional fixed inventory cost.
- Warm isolated sourceIndex benchmarks, five repeated benchmark samples at 500ms, with checked Program and one prewarming index outside the timer. ns/op, B/op and allocs/op exclude fixture setup and semantic encoding.
- Independent direct Lex token inventory/digest and candidate inventory slot count/capacity/bytes. The candidate adapter calls confirmed pinnedIndexTokens() only after first-index measurement and post-GC sampling. It reads source/tokens/err; no cache state is reset or injected.

`run_workspace.py` validates the real server paths on the same application41/101 and library11/21 fixtures. Counts mode uses external compiler/index/lexer observer overlays. Plain memory and latency binaries overlay only the test and otherwise-unused hook definitions: production function bodies are unchanged. Full normalized returned payloads are encoded, hashed and persisted after the request timer/sampler stops; that work is outside timing and the result is dropped before post-GC retention.

Workspace counts must retain identical strict before/after selection counts. Memory runs sample HeapAlloc/RSS at 2ms and state lower-bound peak limitations. Separate latency runs have no counter callbacks or sampler. Each workload has three consecutive requests in one process, explicitly not three independent processes. All runs fix GOMAXPROCS=4, GOGC=100, GOMEMLIMIT=off and use the checkout-pinned Go SDK. No tests or measurements execute concurrently.

Example index commands (run serially):

```
python3 run_index.py --repo "$BASELINE_REPO" --label baseline-index-app
python3 run_index.py --repo "$CANDIDATE_REPO" --label candidate-index-app --candidate
python3 run_index.py --repo "$BASELINE_REPO" --label baseline-index-library --modules 11,21 --library
python3 run_index.py --repo "$CANDIDATE_REPO" --label candidate-index-library --candidate --modules 11,21 --library
```

Example workspace commands:

```
python3 run_workspace.py --repo "$BASELINE_REPO" --label baseline-workspace-app
python3 run_workspace.py --repo "$CANDIDATE_REPO" --label candidate-workspace-app
python3 run_workspace.py --repo "$BASELINE_REPO" --label baseline-workspace-library --modules 11,21 --library
python3 run_workspace.py --repo "$CANDIDATE_REPO" --label candidate-workspace-library --modules 11,21 --library
```

All JSON payload comparisons, source digests, token digests, raw timings/allocation counts, inventory capacity, post-GC deltas and exact source/adapter/probe hashes remain reviewable in each output directory. No claimed startup improvement, editor-host RSS, graph reuse or implementation change follows from this harness.


## Portable publication copy

The probe templates use `.go.txt` names so they remain report assets and do not become repository Go test files. Loaders generate Go overlay targets from them. `run_workspace.py` depends on the adjacent `../selections/prepare.py` package; keep those report directories together.

Prepare immutable baseline/candidate checkouts at the exact commits above, with the repository-pinned SDK and embedded build payload available according to its development instructions. Set `BASELINE_REPO` and `CANDIDATE_REPO` to their absolute paths. Set `GOCACHE` to a writable shared build cache if desired; default is `/tmp/manuscript-tooling-go-cache`. Run all commands from this directory, serially and without concurrent heavy jobs. Regenerate the four index directories first, run `python3 run_balanced_cold.py`, then regenerate the four workspace directories and run `python3 summarize.py` and `python3 render_results.py`.

Published evidence preserves the original exact source/probe hashes, small raw test/benchmark logs, cold records, balanced records, report and summary. The complete 10–15 MB occurrence JSON files, small workspace JSON payload files, test binaries and generated instrumentation copies remain local to the original executor and are intentionally omitted. Their hashes and the successful original byte comparisons are preserved; regeneration reruns the same comparisons. `summarize.py` requires regenerated full payloads and is not intended to run on this reduced package before regeneration. The already published `summary.json` and `RESULTS.md` remain readable without that regeneration. `verify_published.py` checks available hashes and raw recorded comparisons without claiming to recreate omitted payloads.
