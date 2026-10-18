# Bounded private match and proved indexing

Baseline 02be6a39 (merged PR697). `programs/` is the final actual compiler output:
all 10 medians are within about 9% of raw Go or faster. `summary.json` contains
paired bootstrap intervals; `environment.json` records sources, flags, input and
binary hashes. The raw Go baseline is unchanged. Samples are serial, balanced
across all six Go/before/after orderings, 30 trials, with verified checksums and
counts. Final matching is 1.07x Go; the earlier manual-index control is 1.16x.
Do not infer exact equality across inputs, hosts or runs.

`manual-clone-carry/` justified one private clone; `caller-only-alternative/`
shows the smaller alternative removes only about 3.5% of matching time.
`compiler-clone-only/` is the intermediate actual compiler (1.39x Go).
`manual-index-control/` then justified direct indexing only for the already-owned
lists with a proved index. Each retains all 10 rows, including nominal timing
shifts in try/traversal. The final compiler run is separate. Earlier rejected
multiply/cold-query/representation controls remain in the adjacent
`closed-builder-range/` and `counter-aggregation/` archives. No padding, altered
raw baseline, disabled cancellation or unchecked unknown arithmetic is retained.

`library-identical-control/` retains all 66 library rows for 30 trials. Library
source and normalized binary are byte-identical before/after; nominal timing
differences are diagnostic, not changed algorithms. The intermediate library
control is preserved separately too.

The *matched-build.py scripts rebuild the generated native workspaces, then pin
matching flags. Manifest paths are historical canonical cache paths, not portable
inputs. Regenerate native workspaces from the baseline/final revisions, normalize
with CGO_ENABLED=0 and Go 1.25.1 using -buildvcs=false -trimpath
-ldflags='-s -w -buildid=', and verify Go version/metadata and checksums first.
The exact before/after/clone-only generated programs are saved as .go.txt.
With the regenerated binaries, reproduce using:

```sh
env -u TMPDIR -u GOTMPDIR python3 bench/perf/programs/compare.py \
  --before /path/to/before --after /path/to/after --go /path/to/raw-go \
  --input /path/to/lines.txt --output /path/to/program-results --repeats 30
env -u TMPDIR -u GOTMPDIR python3 bench/perf/compare_stdlib.py \
  --before /path/to/library-before --after /path/to/library-after \
  --output /path/to/library-results --repeats 30
```

The fixed input is 200,000 lines; its hash is pinned in environment.json.
Use the fixed input recipe from bench/perf/programs/run.sh. Do not overlap
measurement with builds or tests. `match-index-scaling.log` records accepted
128/256/512 distinct maximum-eight-case schema/callee/caller sites, plans,
initialization and actual emitted selected gets. Allocation growth is near linear;
512-site emission is about 0.21–0.24 s / 91 MB.

Proof boundaries are documented in the canonical lowering guide and parity plan.
New compiler selection/determinism tests, Int modulo interval oracle and native
effects/default/negative/overflow/cleanup/exact-frame/standalone tests pass, as do
compiler/lower race checks, make verify and book checks. The selected effectful
index next(count)*0 and faulting fail()*0 are checked specifically at their emitted
Items access, alongside the unknown effectful List.get fallback. General calls
keep checked arithmetic and original source registration. No public layout or ABI
changes are introduced.
