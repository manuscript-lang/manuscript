# Reversal composed with the exact normalization rollback

**Reversal candidate rejected; #1969 closed unmerged. All four comparisons and recorded local gates complete; authoritative run exited0.**
This report adds evidence for reversal PR #1969 on top of normalization correction PR
#1975. It keeps the older isolated reversal, failed combined normalization and
rejected partial-correction datasets intact and distinct. Root rejected this reversal candidate based on material full-run composition
costs. **#1969 closed unmerged at 2026-10-29 19:48:29 UTC**, with original head
`0525bd107aa1eee7756c90cef44d73bdd45c45d9` unchanged, according to root's verified
update response. The finished result will be preserved on an evidence-only
branch; no candidate merge or new performance PR is planned. Publication is still
pending.

The local validation commit is
`e8bad27e6462a0d7ecfcd863c4a81519bfc3e05d`, with correction baseline
`1e36515bbbf63127b1d626fbe7f33ab0fbcf9ac1`. Read-only [source proof](source-proof.json)
confirms that `normalize_kind` remains byte-exact to public `db975ce2` both before
and after, and the runtime reversal function is byte-exact to original reversal
head `0525bd107aa1eee7756c90cef44d73bdd45c45d9`. The `string.rs` delta is +89/−2:
+25/−2 runtime reversal lines and 64 added test lines. The original reversal
runtime change is composed with the exact eager normalization implementation.

**At evidence collection (latest root verification: 2026-10-29 19:56 UTC)**,
correction #1975 was **open**, pending normal gates/auto-merge at
`1e36515bbbf63127b1d626fbe7f33ab0fbcf9ac1`. #1967 normalization is already
**merged** as `bb7198ea3c5d77fa1e59b39444ab68f5304a079a` from head
`05152904151ed68e8c8892bf8d167639bd7a0883`. #1969 is **closed and unmerged** at
unchanged original head `0525bd107aa1eee7756c90cef44d73bdd45c45d9`, verified by
root's update response. These are handoff states, not API observations by this
report author.

The authoritative protocol is `/tmp/string-round2/check-reversal-restored.py`,
root tool cell `82826`. It reuses the correction gate's pinned compiler
`448c69c6523a27f36b89ec4a8f5cb3fba6b6fa2c8e45070204e0a208f2bcebd3`
and harness, since compiler source is unchanged. Native before hash is
`46c96e329f68f665e8bc41e3490d6150f19c20f959c57f2026d2a8077ce9d6d0`,
which reproduces the correction's after state; native after is
`cef44afa6c46e706fad5b5232172db4a0fbd1e8c76f7e1a7baf036d8c1e4e608`.
Helpers match `8315efc0c1ae0b87ff80185ee282e4ede97e82afa6ecfe1825fe296549bc46ef`.
These hashes are root's completed native-state records; no archive or helper IR
is copied. Completed program metadata reports **Release / cranelift**; effective backend
and optimization beyond labels remain unverified.

Four performance phases stay separate: normalization original100 with seven
pairs, normalization focused30 with nine pairs, reversal original83 with seven
pairs and reversal focused18 with nine pairs. Each comparison validates producer
status, exact identity, operation count and checksum, with warmup excluded and
alternating process order pinned to CPU 0. Completed phases will retain every raw
sample, paired delta/sign/range, and unfavorable median without filtering.
Common normalization paths are composition controls, not proof of compiler,
backend, allocation, ownership or placement mechanisms.

Only completed artifacts are staged. The [final producer record](record.json)
contains exact commands and per-step exits; [the launch record](launch-record.json)
labels authoritative root cell `82826` actual exit **0** as an **after-run tool
transcript handoff**, not a producer-generated overall status. No phase failed or
was overwritten. Earlier derived per-phase records remain labeled snapshots from
before final completion; final status is in [status.json](status.json). This
packaging task ran no builds, native writers, timings, reruns or unrelated probes.

## Completed normalization original100 phase

[Completed-phase metadata](normalize-full/completed-phase.json) records the exact
build/comparison commands, phase exits, program hashes and unchanged source and
identity pins. Root confirmed `normalize-full 0` and `100 cases 1400 validated
rows`. Its derived phase record was captured before overall completion; final
root exit0 is recorded separately in the launch record. The [archived source](normalize-full/source.ms.txt) and
[identities](normalize-full/identities.json) match both program build records.
[Source states](source-states/reversal-on-correction.patch) and the
[run protocol](protocol/check-reversal-restored.py) preserve reconstruction and
reproduction. These protocol scripts contain original state-changing commands;
they are archived as documentation, not executed by this packaging task.

All **1400 raw samples**, [100 complete distributions](normalize-full/all-case-statistics.csv),
[700 paired samples](normalize-full/paired-samples.csv) and
[56 unfavorable medians](normalize-full/unfavorable-medians.csv) are retained,
including every paired sign and range. The 44 favorable medians remain alongside
them. Derived medians use exact integer elapsed/iterations; the original summary
retains one-decimal rounding. A median change and median paired difference are
different statistics, and mixed paired signs remain visible. No outlier is
excluded and no confidence or mechanism claim is inferred from seven pairs.

The unchanged normalization control exposes an unfavorable common path:
**early 1 MiB NFC is +14.94%, +3.707181 ms median paired delta, 7/7 slower**.
Other large-prefix results include gains and mixed signs, so the full completed
phase does not establish a blanket no-cost composition result:

| Case | Before median ms | Composed median ms | Median change | Paired delta ms | Faster / slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `early_unicode_1048576_NFC` | 32.383536 | 37.221288 | +14.94% | +3.707181 | 0 / 7 |
| `late_unicode_1048576_NFC` | 32.163634 | 32.140689 | -0.07% | +0.003700 | 3 / 4 |
| `early_unicode_1048576_NFD` | 19.647418 | 20.656764 | +5.14% | +1.514689 | 2 / 5 |
| `late_unicode_1048576_NFD` | 19.825962 | 20.280706 | +2.29% | -0.093946 | 4 / 3 |
| `early_unicode_1048576_NFKC` | 31.699366 | 31.132718 | -1.79% | -0.113529 | 4 / 3 |
| `late_unicode_1048576_NFKC` | 33.877767 | 32.347316 | -4.52% | -1.530451 | 4 / 3 |
| `early_unicode_1048576_NFKD` | 21.032976 | 21.339098 | +1.46% | +0.989533 | 2 / 5 |
| `late_unicode_1048576_NFKD` | 20.155553 | 21.386771 | +6.11% | -0.529943 | 4 / 3 |

The original normalization function is unchanged between the two states. These
observations are costs measured in this composition comparison, not proof of a
compiler/backend/placement mechanism or a repeated workload-frequency estimate.
All ASCII, empty, small, canonical and compatibility controls remain in the full
CSV, including unfavorable medians without a frequency or significance filter.
The focused normalization and full reversal phases follow separately. Focused
reversal follows separately; completed final gates are recorded below.

## Completed focused normalization30 phase

This separate, planned comparison completed with producer exit0, **30 cases,
540 raw rows and nine pairs**. [Its source](normalize-focused/source.ms.txt),
[identities](normalize-focused/identities.json) and
[completed-phase record](normalize-focused/completed-phase.json) remain distinct
from the original100 phase. It includes **19 unfavorable medians** and
**11 favorable medians**, all preserved in the
[complete distributions](normalize-focused/all-case-statistics.csv) and
[unfavorable distributions](normalize-focused/unfavorable-medians.csv), with
[270 raw paired observations](normalize-focused/paired-samples.csv). Original
summary and paired files remain byte-exact copies. Every expected identity,
operation count, checksum and unique complete pair was checked offline.

The focused results retain common-path costs as well as mixed observations:

| Case | Before median ms | Composed median ms | Median change | Paired delta ms | Faster / slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `canonical_scale_65536_NFD_full` | 3.390832 | 3.769575 | +11.17% | +0.473299 | 3 / 6 |
| `early_unicode_1048576_NFD` | 22.291115 | 22.436009 | +0.65% | +0.517264 | 2 / 7 |
| `late_unicode_1048576_NFD` | 22.469400 | 23.306731 | +3.73% | +0.837331 | 4 / 5 |

Budget, negative-budget, invalid-form, empty and one-byte controls also remain
in the full CSV. Very short error paths are retained in absolute ns/op and paired
ranges; their percentage changes do not establish proportionately precise costs.
This focused source has no early 1 MiB NFC case and cannot replace or invalidate
the full phase's **+14.94%, 7/7 slower** observation. The datasets are not pooled,
and favorable focus results do not erase the full failed evidence. Root's rejection and unmerged closure remain based on the recorded material
composition costs. The preplanned strict conformance completed later with no
failures.

## Completed reversal original83 phase

The original83 reversal comparison completed with producer exit0, **1162 raw
rows and seven pairs**. [Source](reverse-full/source.ms.txt),
[identities](reverse-full/identities.json), [completed-phase metadata](reverse-full/completed-phase.json),
[83 complete distributions](reverse-full/all-case-statistics.csv),
[581 paired samples](reverse-full/paired-samples.csv) and
[all 3 unfavorable medians](reverse-full/unfavorable-medians.csv) remain
separate from both normalization phases and historical reversal runs. Every
expected identity, operation count, checksum, unique row and complete pair was
validated offline; the original paired summaries agree.

There are **80 favorable and 3 unfavorable medians**. Large ASCII and
Unicode examples show the measured gains in this reversal phase:

| Case | Before median ms | Composed median ms | Median change | Paired delta ms | Faster / slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ascii_mixed_n1048576` | 9.162636 | 0.447730 | -95.11% | -8.708180 | 7 / 0 |
| `ascii_controls_n1048576` | 8.828972 | 0.480681 | -94.56% | -8.348291 | 7 / 0 |
| `mixed_copies65536` | 7.949822 | 5.973715 | -24.86% | -1.353465 | 6 / 1 |
| `late_unicode_1048576` | 8.928921 | 2.932614 | -67.16% | -5.916579 | 7 / 0 |
| `early_unicode_1048576` | 8.726820 | 2.715958 | -68.88% | -6.010861 | 7 / 0 |

Every unfavorable median is also shown below, including mixed paired signs.
Full per-state and paired ranges remain in the CSV. The tiny empty-case interval
is reported in absolute nanoseconds; its relative ratio is not a proportionately
precise cost estimate.

| Case | Before median ns | Composed median ns | Median change | Paired delta ns | Faster / slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ascii_mixed_n0` | 6.722619 | 7.343448 | +9.23% | +0.197893 | 3 / 4 |
| `three_byte_copies65536` | 4174024.937500 | 4490672.312500 | +7.59% | +44601.562500 | 3 / 4 |
| `zwj_copies256` | 14048.984260 | 14492.923450 | +3.16% | -1121.789970 | 5 / 2 |

The three-byte 65536-copy control has a +7.59% ratio of medians, +44.602 µs
median paired difference and 4/7 slower pairs; the ZWJ 256-copy unfavorable
median has favorable median paired difference and 5/7 faster pairs. Neither
observation is filtered or promoted into a universal mechanism claim. Reversal
workload gains do not erase the already retained material normalization costs.
The candidate remains rejected and closed unmerged; focused reversal and strict
conformance are preplanned evidence collection, not a reopening of acceptance.

## Completed focused reversal18 phase

The final preplanned performance comparison completed with producer exit0,
**18 cases, 324 raw rows and nine pairs**. [Source](reverse-focused/source.ms.txt),
[identities](reverse-focused/identities.json),
[completed-phase metadata](reverse-focused/completed-phase.json),
[18 complete distributions](reverse-focused/all-case-statistics.csv) and
[162 paired samples](reverse-focused/paired-samples.csv) remain separate from
full reversal and both normalization phases. There are **14 favorable and four
unfavorable medians**, without sample filtering or case exclusions. All
unfavorable observations are retained, including tiny absolute costs:

| Case | Before median ns | Composed median ns | Median change | Paired delta ns | Faster / slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ascii_mixed_n0` | 6.591663 | 7.678032 | +16.48% | -0.115130 | 5 / 4 |
| `ascii_controls_n0` | 6.858306 | 8.565449 | +24.89% | +1.536451 | 3 / 6 |
| `replacement_copies2` | 55.211998 | 60.832768 | +10.18% | +6.982264 | 3 / 6 |
| `replacement_copies65536` | 981422.453125 | 1042366.328125 | +6.21% | -32934.312500 | 6 / 3 |

[All unfavorable distributions](reverse-focused/unfavorable-medians.csv) retain
per-state and paired ranges. The empty ASCII and two-copy replacement costs stay
in absolute ns/op; large relative changes on short intervals do not imply
proportionately precise estimates. The 65536-copy replacement median is +6.21%,
while its median paired difference is favorable and six of nine pairs are faster;
those differing statistics are preserved. Focused gains and mixed signs do not
erase the full-run normalization costs or reopen the rejected candidate.

## Packaging and gate status

All four preplanned performance datasets are complete and kept separately:

| Phase | Cases | Pairs | Raw rows | Paired rows | Unfavorable medians |
| --- | ---: | ---: | ---: | ---: | ---: |
| normalization full | 100 | 7 | 1400 | 700 | 56 |
| normalization focused | 30 | 9 | 540 | 270 | 19 |
| reversal full | 83 | 7 | 1162 | 581 | 3 |
| reversal focused | 18 | 9 | 324 | 162 | 4 |

These counts describe separate experiments, not pooled timing statistics. Run
`python3 verify_evidence.py` from this directory to verify all archived hashes,
source pins, complete raw identity/checksum/operation pairs and retained adverse
cases without executing native programs. [Status](status.json) records the
final gate boundary. All **30 recorded steps exited0**: native before/after,
fmt, **24 runtime string tests**, workspace Clippy, repository check, **10 source
tests in each Release and Debug**, eight program builds, four comparisons, corpus
lint and strict conformance. [Completed check logs](checks/string-tests.log) and
[the final record](record.json) preserve their actual commands and exits.

The actual completed [JSON conformance report](checks/conform-report.json) and
[log](checks/conform.log) both report **2394/2394 passing**: check **1603/1603**,
run **532/532**, test **259/259**, with zero failures, expected failures,
unexpected passes or unrecorded fixtures. This is the selected strict
`run,check,test` scope with `aliasing` excluded, not all 4154 discovered fixtures.
[Corpus lint](checks/corpus-lint.log) reports **4154 fixtures, zero problems**.
The [immediate pre/post input-integrity proof](checks/conform-input-integrity.json)
records identical hashes, sizes and modes for dedicated read-only compiler,
harness, native archive, helper IR and expectation snapshots. All builds and
timing ended before the suite; no native writer ran during conformance. The
[Markdown report](checks/conform-report.md) is preserved byte for byte too.
No binaries, native archives, helper IR or active artifacts are staged here.

## Bounded fresh source pass on the correction

At **2026-10-29 19:57 UTC**, root fetched main at
`f7659657ccf5549455cb1f78baac49b5505416bd` and ran
`git diff --exit-code 85cfb96b889ec4176cfe71a42d74acfd091cbe60 origin/main -- crates/ms-rt/src/string.rs`,
which exited **0**. Later main changes had not altered String source since the
main revision used to prepare the correction. This source-only freshness check
does not add runtime or platform validation and required no rebase or new native
measurement. The command/result are root's handoff evidence.

Root supplied these findings from its independent fresh audit of correction
source `1e36515bb` ([archived correction String source](source-states/before.rs.txt),
`crates/ms-rt/src/string.rs`, source SHA-256
`d9124ee3a902263ee12b9daa6668dab4e6609044e40e72c5074c167e1be4a2c0`). This is
bounded source coverage, not a new timing or allocation measurement by the report
packager:

- Trim boundaries already use an ASCII path plus decoding at the boundary.
- Find uses generic long search and bounded short/16 candidate paths.
- Repeat uses a one-byte fill or doubling.
- Join sizes exactly and copies directly into the output.
- `to_bytes` uses one allocation and copy.
- `from_scalars` validates and encodes in one pass, with an ASCII shortcut.

A possible capacity-growth cost in `from_scalars` remains **unmeasured**, not a
retained issue. The considered alternatives add a pass or ASCII memory. These
observations do not establish universal optimality or remove the need to measure
a concrete future proposal. Compiler/backend mechanisms, allocation/ownership
internals, cleanup, HTTP and Windows paths remain outside this bounded work.

Root will copy this completed report into
`bench/perf/string-reverse-ascii/restored-normalization` and publish an
**evidence-only branch** after immutable informal review. The rejected candidate
will not be merged, and no new performance PR is proposed. Earlier isolated,
failed combined and rejected partial artifacts remain intact.
