# Safe counter aggregation

Baseline ec818c1f (merged PR695). The final program and complete 66-row library
controls use30 balanced trials and matching Go build flags. `summary.json` adds
paired bootstrap intervals. `environment.json` records production source hashes;
`aggregate-matched-manifest.json` pins native generated sources, binaries and flags.
`aggregate-matched-build.py` reconstructs normalized binaries from regenerated
native cache workspaces. Local cache paths are provenance, not portable inputs.

`manual-*-control/` and `aggregate-control.py` preserve the experiments that justified
implementation; their assumptions are not compiler guarantees. Scaling controls
exercise capture inventory and accepted aggregate proofs at N/2N/4N.

Counts and checksums are validated for every trial. No library rows, slow results
or timing regressions are discarded. Source-level logical iteration counts remain
unchanged while selected loops do less unobservable work. See the canonical
lowering guide for proof restrictions and fallbacks. This increment closes method,
generic and length gaps; matching and builder work continue separately.

Rejected match-clone, builder-callback and match-return controls retain all30
program trials. Cloning regressed traversal; callback append regressed; rewriting
match assignments as returns produced no material matching improvement. None is
production code. These controls constrain the next investigation.
