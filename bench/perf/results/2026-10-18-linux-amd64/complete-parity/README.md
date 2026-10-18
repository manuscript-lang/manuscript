# Go parity measurements, 2026-10-18

The primary retained comparison is in `programs/` and `stdlib/`.
Baseline: d710e9bf68845ce8a23e2de3f91836459396dafe. Both revisions use
identical current benchmark sources. The Go control and native builds use
Go 1.25.1, CGO_ENABLED=0, -buildvcs=false, -trimpath and
-ldflags='-s -w -buildid=' with ordinary inlining.

Thirty process trials cycle all six Go/before/after orders for programs;
library trials alternate before/after order. Sampling ran without concurrent
compilation or correctness tests and with TMPDIR/GOTMPDIR unset. Every operation
count and checksum is validated. Library ratios use raw elapsed nanoseconds divided
by operation count; printed rounded rows are checked for consistency.
`environment.json` pins source hashes, final executable hashes and build metadata.
The final inventory lookup correction rebuilds to identical executable hashes.
`statistics.json` contains paired bootstrap intervals with deterministic seed 142.

See [the program report](../../../programs/results.md) and
[all 66 library rows](../../../stdlib/results.md). Seven of ten program workloads
are within roughly 20% of Go; generic accumulation, try and matching remain slower.
Full library slowdowns are retained. Focused controls repeat unchanged bodies
20 times in each of 15 balanced processes to check collection-phase effects;
the large full-sequence regressions do not reproduce there. These are diagnostic
controls, not substitutes for the full table. First rounded focused results are
explicitly labeled `initial-rounded-*`; final focused summaries use raw elapsed.

`controls/` records intermediate accepted and rejected experiments. Their inherited
Go binary used CGO_ENABLED=1 and default trim/link flags, so those ratios are
historical and must not be substituted for final primary parity ratios.
`experiments/` retains scripts, assembly and generated Go snapshots as `.go.txt`
(to avoid creating extra Go packages). Controls use build overlays rather than
mutating cached native workspaces. The focused executable hashes for the initial
ten-operation group were not retained; the scripts and raw results are archived.

Allocation controls isolate metadata construction, ordinary/presence-only line
reads and ordered/closed map batches. Compiler scaling controls separate proof
work from parsing/checking/printing. The map control doubles both candidates and
unrelated methods at 128/256/512, with proof times about 0.14/0.29/0.57 ms;
Int evidence lookup occurs once per program. Mixed-cell timing profiles retain
collector cost rather than inferring complexity from timing alone.

Reproduction commands and validation results are in the program report;
[the proposal record](../../../programs/parity-plan.md) labels retained, rejected
and deferred work. No padding, special inlining flags, changed cancellation query
phase, delayed fault capture or unchecked general arithmetic ships.
