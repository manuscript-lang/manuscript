# Independent final evidence audit

APPROVE the evidence record at exact commit `ca03ecf12bdcb1ab9b0c9406ed9f4e1e38cc1307` against reviewed code/harness `800547bb60c0b7926f77572b1236a2c198043b12`. No concrete finding or remaining code-review blocker was established. This judgment accepts the recorded results and their stated limits; it does not authorize publication, establish a general contention speedup, or substitute for the user's final delivery decision.

Audit checkout: `/workspace/manuscript-accessor-design`; exact HEAD and clean tracked status verified. This was an evidence-only audit: no tests, benchmarks, builds or measurements rerun, and no tracked source edited.

## Exact code and evidence boundary

Independently enumerated `git diff --name-only 800547bb ca03ecf1`: all 69 changed files match code-evidence-proof.json exactly and fall within the stated whitelist: the main integration record, its new integration-9dcc0bae evidence directory, and the existing verification guide update. The guide identifies the latest record and correctly preserves earlier measurements/coverage as historical.

`git diff 800547bb ca03ecf1 -- pkg internal` is empty. Exact pkg tree IDs are `164a541ba25abc0f84e9250b2132207dbc5d4837` at both revisions; exact internal tree IDs are `ed00d718906c4a129f7030b29e96c00da48a318b` at both revisions. The contention Go template and Python driver also retain their reviewed Git blob IDs (`ef24bae9ff16daecd0a1a9dc3a4424c86d2705e1` and `d90b9737bba47501861422d5b2d02a9d4c3c1537`). Production is unchanged from independently approved correction 1ff193c0. Preserved fb66c3b4 implementation and 789a4452 correction remain ancestors.

The copied original merge review, correction review and pre-sample harness review are byte-for-byte identical to my original /tmp reports. The immutable original rejection remains visible alongside the exact correction approval; no report has been rewritten into retroactive approval.

## Raw sample and calculation audit

Parsed all 20 saved benchmark output files independently, reconstructed all 80 records and compared them field-for-field with samples.json. Recomputed all 16 medians from their five raw records: every value matches medians.json and the main record's tables/prose. Provenance identifies historical baseline 1383851e and exact current 800547bb, pinned Go 1.25.1, GOMAXPROCS=2, CPU=2, five samples, 200ms uncontended / 200 fixed release iterations. The 20 benchmark commands alternate revision order as specified.

Confirmed unchanged generated adapter hashes match the previously independently approved/validated harness. Full-safety controls retain cancellation, actual mutex operations, live state, exact guard-holder validation and original result representation. Isolated Logger consumes only the tag, with no Equal/transport/formatting/I/O. The retained normal/race parity logs cover public reads and controls.

Uncontended public medians are accurately reported: guard 158.30 to 19.87 ns/op with 176 to 0 B/op and 4 to 0 allocs/op; Logger 341.50 to 52.80 ns/op with 376 to 64 B/op and 7 to 1 allocs/op. The accompanying controls are also reported, including the guard control drift from 19.42 to 21.58 ns/op. These are observations for integrated revisions rather than isolated attribution to accessor syntax.

Release-to-result medians also match the raw data: guard public 1198 to 995 ns, guard control 1120 to 1022 ns, Logger public 2388 to 1339 ns, Logger control 1344 to 1332 ns. Current Logger control sample 3 is retained at 9445 ns/op, 65 B/op, 1 alloc/op. The report explicitly disclaims general contention speedup, throughput and isolated dispatch conclusions, and identifies the excluded pre-block binding/setup allocations and included unlock/scheduling/result delivery. That interpretation is appropriately cautious given the synthetic coordination and dispersion.

All measured broad execution gates had completed before the measurement-host record and first raw sample. The later evidence-only book validation is separately retained and does not overlap the sampled interval.

## Gate and artifact audit

Verified all 81 entries in raw-artifact-hashes.json against actual raw files, including exact byte lengths and SHA256. Independently decoded each raw Go JSONL stream and reproduced every gates.json package result, elapsed duration, test/subtest pass count, skip and failure list:

- Runtime race: pass, 20.481s, 2363 pass events; precisely the two disclosed skips.
- LSP race: pass, 109.600s, 191 pass events, no skips.
- Native build package: pass, 284.081s, 596 pass events, no skips.
- e2e: pass, 445.328s, 373 pass events, no skips.
- Native debugger: pass, 5.895s, 22 pass events, no skips.

Runtime race was launched at HEAD 1ff193c0 and completed while 800547bb was being committed. Independently verified `git diff 1ff193c0 800547bb -- pkg/runtime` is empty, including test files, so its runtime source/test identity matches the reviewed final code. Recording the launch revision explicitly is sufficient; a broad rerun is unnecessary. The primary agent plans an evidence-only followup adding this provenance precision.

These counts are correctly labeled test/subtest pass events rather than distinct top-level tests. The DAP log reports 24 passed, zero failed/skipped. Read the verify, fuzz, book, extension and standalone distribution logs: they support the recorded successful gates. All eight named fuzz targets have bounded 10-second commands and PASS outputs; these are bounded fuzz results, not exhaustive proofs. Both committed gzip book logs decompress to the exact hashed raw bytes. Linux distribution output supports packaged compilation/tooling/debugging/profile execution without host Go/dlv/downloads. The emitted program SHA256 recalculates to `1a197b745aad18a9c532997ad36b5aad899d4be66e091ea3b2b138ce6de1af55`; its recorded emission partition has 20 direct reads with receiver-only helpers and no callable dispatch in those cases.

Independently verified all nine historical measurement files against both their recorded SHA256 and exact fb66c3b4 Git bytes. They remain unchanged; the fresh guard/Logger experiment does not replace or rewrite the historical 52-workload comparison.

## Limits retained accurately

Coverage 78.0% belongs to exact historical 12a26d19, as coverage-summary.json states; no fresh integration coverage is claimed. Runtime memory-worker and CRLF CSV seed skips agree with their source conditions and raw logs. Fresh CSV fuzz passes do not explain the older f253 deadline failure, and the record does not claim that failure was retroactively fixed.

Recorded upstream main CI jobs all completed successfully, including macOS and Windows host jobs. The record correctly keeps this separate from Linux/amd64 local execution of the final accessor integration; it makes no cross-platform final-branch execution claim. Publication remains explicitly held, with no push or PR.

No further implementation changes or broad reruns are indicated by this evidence audit. An evidence-only followup containing this audit and the final delivery bundle may preserve the same code/harness identity, with a fresh exact-HEAD whitelist proof. Any subsequent production/harness change would require a new exact review.
