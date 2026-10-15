# Final accessor integration and bounded verification

No push or PR. Implementation fb66c3b4 and recursion fix 789a4452 remain intact.

Integrated main: `9dcc0bae6f6e269dafe794b4ff3b8def9825d6bb` (#509–#512).
Final reviewed code/harness: `800547bb60c0b7926f77572b1236a2c198043b12`.
Production pkg/internal bytes equal approved correction 1ff193c0. Identities and tool/archive hashes are in
[identity.json](integration-9dcc0bae/identity.json).

## Independent review and correction

- [Exact merge review](integration-9dcc0bae/merge-review-8b4dd16f.md): REQUEST
  CHANGES at 8b4dd16f. Inherited #511 interface caching keyed only receiver type
  and generation, so same-type views from different local implementation modules
  called the first implementation at one call site. Exact new main also failed;
  the fb66 first-parent control passed.
- [Correction re-review](integration-9dcc0bae/correction-review-1ff193c0.md):
  APPROVE exact 1ff193c0. Both slots retain lexical module; nonempty argument
  scopes use existing specialization. Original source, alternating/concurrent
  views, generation/argument-scope probes and focused race checks pass. Restoring
  old methods.go makes the new regression fail `view 1 read 1`.
- [Pre-sample harness review](integration-9dcc0bae/harness-review-800547bb.md):
  APPROVE exact 800547bb. Independent baseline/current normal and race probes pass.
  Adapters are the only generated harness difference; fixture edits only format source.

Merge resolution preserves accessor exclusions, typed emission, default-expression
recursion and cancellation. String/Float getters reuse main's algorithms.
The Error.message contract and every implementation remain methods.

[Final evidence audit](integration-9dcc0bae/final-evidence-review-ca03ecf1.md): APPROVE ca03ecf1; zero code delta.

## Fresh local checks

[gates.json](integration-9dcc0bae/gates.json) records results on the final code.
Pinned Go 1.25.1, Node 24.13.0, Linux/amd64; Go compile concurrency limited to 2.
Runtime race launched at 1ff193c0; its runtime source/tests equal 800547bb byte for byte.

| Gate | Result |
| --- | --- |
| make verify, source documentation, book/link/highlighting checks | PASS |
| Full runtime race | PASS, 20.481s; 2,363 test/subtest pass events |
| Full LSP race | PASS, 109.600s; 191 pass events, zero skips |
| Full native build package | PASS, 284.081s; 596 pass events, zero skips |
| Complete e2e | PASS, 445.328s; 373 pass events, zero skips |
| Native Go debugger with SDK wrapper | PASS, 22 pass events, zero skips |
| Bundled native DAP, all extension tests | PASS, 24 tests, zero skips |
| All eight Makefile fuzz targets, 10s each, two workers | PASS |
| Linux standalone dist-check | PASS outside checkout, empty caches, no host Go/dlv/downloads |

Runtime race has two intentional skips: the opt-in fresh-process memory worker,
and CSV seed #3 containing CRLF excluded by the fuzz filter. No test/build failures
remain. Fixture formatting was corrected in 800547bb. DAP dependency/cache setup failures
were resolved; initial logs are bundled. No lost tool response caused a broad rerun.

All 20 core reads avoid callable dispatch; generated Go
SHA256 remains `1a197b745aad18a9c532997ad36b5aad899d4be66e091ea3b2b138ce6de1af55`.
Runtime sources nevertheless changed with main.

## Measured guard and isolated Logger reads

Historical baseline 1383851e versus exact final 800547bb, same SDK/host,
GOMAXPROCS=2/CPU=2, five alternating-order samples. All broader checks completed
before measurement. [All 80 records](integration-9dcc0bae/contention/samples.json),
[medians](integration-9dcc0bae/contention/medians.json), raw sample files and
[commands/provenance](integration-9dcc0bae/contention/metadata.json) are retained.
Normal/race live-value, stale-guard and blocked-cancellation probes passed.

Uncontended medians measure one complete runtime read, excluding construction/source
wrappers. Logger consumes its tag without Equal, transport, formatting or I/O:

| Read | Baseline ns/op | Current ns/op | B/op baseline → current | allocs/op baseline → current |
| --- | ---: | ---: | ---: | ---: |
| Guard public | 158.30 | 19.87 | 176 → 0 | 4 → 0 |
| Guard safety control | 19.42 | 21.58 | 0 → 0 | 0 → 0 |
| Logger public | 341.50 | 52.80 | 376 → 64 | 7 → 1 |
| Logger safety control | 51.27 | 51.41 | 64 → 64 | 1 → 1 |

Controls retain cancellation, mutex, live state, guard validation and result shape. Public reads removed binding
allocations; Logger still boxes its Alternative result. Control drift and
dispersion limit causal comparisons; these observations concern the integrated revisions.

Forced-contention release-to-result medians (ns): guard public 1198 → 995,
guard control 1120 → 1022; Logger public 2388 → 1339, Logger control 1344 → 1332.
The named reader was proven mutex-blocked before timing. Unlock, scheduling and
result delivery are included; pre-block binding/setup allocations are excluded.
Current Logger control includes a retained 9445ns sample. These measurements do not isolate dispatch or
establish a general contention speedup or throughput claim.

## Evidence boundaries

All nine historical 52-workload measurement files remain byte-for-byte unchanged;
[their hashes](integration-9dcc0bae/historical-measurements-unchanged.json) preserve
the original comparison. Coverage **78.0% at 12a26d19 is historical**, not fresh
integration coverage; it was not rerun. Earlier f253 CSV deadline failure remains
historically unexplained: fresh bounded passes do not establish its exact cause
or retroactively prove it fixed.

[Upstream main CI](https://github.com/manuscript-lang/manuscript/actions/runs/38665989875)
completed successfully, including macOS/Windows host jobs. That is upstream main
evidence; final accessor integration was executed locally on Linux/amd64.
After reviewed 800547bb, only this record, its evidence directory and the guide link
may change. The bundle records the exact empty code diff.
