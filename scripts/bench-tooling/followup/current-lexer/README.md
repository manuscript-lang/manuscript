# Current-lexer lexical-cache refresh

This is a bounded integration refresh, not a replacement for the historical full lexical report. Exact baseline is 55228347c8555186ab6a483459e161e1bef82326 and candidate is its cache-merge child 3232c8db008fe60804f88bb8a243d15ce8da0a14. Prepare clean immutable checkouts at those SHAs with the repository-pinned SDK and embedded payload available, then set `BASELINE_REPO` and `CANDIDATE_REPO` to their absolute paths.

The index probe uses five independent fresh cold processes and three 300ms warm benchmark observations at 41/101 modules. It compares complete stable occurrence/Info/type/source-shape payloads in two fresh processes per side/fixture, independently inventories raw pinned tokens, and reads the candidate fixed cache only after cold timing and post-GC sampling. The same fixture/serialization definitions as the original report are retained; checker `Fact` cycles are omitted, exported Info fields have a coverage guard, fixture roots alone are normalized, and pointer addresses are never formatted.

Workspace scope is symbols only, at 41/101 modules, three repeated requests per size/mode/side. Count mode measures strict compiles/indexes/standard lex calls; separate plain latency mode overlays no production function bodies and has no counters or sampler. Full returned payloads are encoded/persisted after timing, then dropped before GC. This refresh makes no new peak RSS/heap claim and does not rerun the full historical operation/library matrix.

Run serially, without concurrent heavy jobs:

```
python3 run_index.py --repo "$BASELINE_REPO" --label baseline-index-app --modules 41,101 --cold-processes 5 --warm-count 3 --benchtime 300ms
python3 run_index.py --repo "$CANDIDATE_REPO" --label candidate-index-app --candidate --modules 41,101 --cold-processes 5 --warm-count 3 --benchtime 300ms
python3 run_workspace.py --repo "$BASELINE_REPO" --label baseline-workspace-app --modules 41,101 --operations symbols --modes counts,latency --repeats 3
python3 run_workspace.py --repo "$CANDIDATE_REPO" --label candidate-workspace-app --modules 41,101 --operations symbols --modes counts,latency --repeats 3
python3 summarize_refresh.py
python3 render_results.py
```

`run_workspace.py` needs adjacent `../selections/prepare.py`; keep the publication directories together. All runs use the checkout's pinned Go SDK and fixed GOMAXPROCS=4/GOGC=100/GOMEMLIMIT=off. GOCACHE is configurable through the environment, defaulting to `/tmp/manuscript-tooling-go-cache` in the portable copy. Templates use `.go.txt` filenames in publication so they cannot become repository Go tests; loaders create the actual overlay targets.

The reduced publication preserves summary, original raw logs/cold records, exact input/probe/source/adapter hashes and empty working patches. It excludes binaries, generated instrumentation sources and complete 12–15 MB JSON payloads; those remain local to the original executor. Regeneration recreates them and reruns full byte comparisons. `summarize_refresh.py` requires regenerated full payloads; the already published summary/report are readable without them. `verify_published.py` validates available hashes/logged comparisons without claiming to regenerate omitted payload bytes.
