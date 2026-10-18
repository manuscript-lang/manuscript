# Successful Result payload bounds

Baseline: 0bac0cbd (merged PR #694). `programs/` is the final primary 30-trial
comparison, with all six Go/before/after orders and matching CGO/trim/link flags.
`summary.json` includes paired bootstrap intervals; `environment.json` pins source,
input/build settings and executable hashes. No compilation/tests overlap sampling.

`native-manifest.json` records exact generated-Go hashes, executable hashes and
Go build metadata. `result-matched-builds.py` rebuilds already generated native
workspaces with matching flags; it requires the recorded local cache paths or
regenerated corresponding native sources. The normalized library source and
executables are byte-identical before/after. `library-control/` retains 30 CLI-built
diagnostic trials with all 66 counts/checksums and raw elapsed times; those
executables differ only in build-id notes, with identical loaded code/data. Timing
variation in this control is not a changed algorithm. No library rows are dropped.

`manual-carry-control/` is the earlier diagnostic experiment that justified the
restricted proof. `remaining-controls.py` reconstructs generated-Go experiments
using overlays on canonical real paths; it includes unshipped match/combined
controls. Do not treat these manual assumptions as compiler guarantees.

Summary/proof N/2N/4N allocation and time controls plus CPU profile text are retained.
The [latest report](../../../programs/results.md),
[proposal/review record](../../../programs/parity-plan.md), and canonical compiler
guide describe selection, fallbacks and validation. Method loops and matching
remain current gaps; this increment makes no complete-parity claim.
