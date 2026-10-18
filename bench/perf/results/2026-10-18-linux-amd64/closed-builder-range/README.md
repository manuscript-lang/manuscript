# Closed builder and ordered range batches

Baseline f58ad141 (merged PR696). `programs/` contains final30-trial matching-flag
controls. `summary.json` includes paired bootstrap intervals; `environment.json`
pins production sources, input, flags and binary hashes. No CPU-heavy work overlaps
sampling. `builder-range-matched-*` records canonical native cache paths and rebuild
commands; regenerate corresponding workspaces rather than assume paths portable.

The library source and normalized binary are byte-identical before/after; retain
all66 diagnostic rows and do not interpret nominal regressions as changed algorithms.
Lowering the fragment cap1024→128 also leaves both measured benchmark sources and
binaries byte-identical. Initial-cap and final-cap scaling remain separate.

`manual-builder*` and `manual-unroll*` justified implementation after independent
proposal review. `manual-clone-unroll` remains an unshipped diagnostic; compiler
code does not clone match helpers. Rejected index/slice-only/multiply/cold-query
controls remain with all results. No padding or placement tuning is retained.

`go-arithmetic-control/` adds checked arithmetic to the original handwritten-Go
match, then original-period cancellation. `go-semantics-control/` directly balances
that control against Manuscript with shared original raw-Go samples. These two
directories' harness version labels say ms for every candidate executable; the
before candidate is handwritten Go as recorded by filenames/hashes. Other Go
workloads are unchanged. Exact control sources are saved as .go.txt; no such
changes are made to the original handwritten-Go baseline. Matching remains slower
than raw unchecked Go; equivalent-cost evidence is diagnostic, not a parity claim.

Selection, fallback, native source-state/frames/cleanup/standalone tests and bounded
source-size proofs are described in the canonical lowering guide and parity plan.
