# Integration normalization regression: completed evidence and open correction

**Attribution established; correction remains unaccepted.** The new same-path
current-baseline comparisons expose material Unicode-prefix costs. Four-state
measurement reproduces all eight 1 MiB prefix median regressions with the
normalization change alone. Reversal alone is mostly near baseline for these
cases; the normalization source factor is sufficient to reproduce the concern.
This is not a claim of zero interaction, a compiler-mechanism diagnosis, or a
global no-cost/optimality result.

Current PR states as reported by root (no API lookup by this report author):
#1967 normalization head `05152904151ed68e8c8892bf8d167639bd7a0883` already merged
as `bb7198`; its regression needs priority correction or revert. #1969 reversal
head `0525bd107aa1eee7756c90cef44d73bdd45c45d9` is **draft and unmerged**, holding
composition acceptance pending assessment. No correction/partial-revert PR has
been accepted or published by this report-preparation agent.

## Configuration and distinct phases

Native baseline is main `db975ce2f01ddf8da108ec9045ecaf66a63ab22c`, archive
`42f47bd3db22793b355c74e4cc46ef6e94277d4d1a78eb5fe36ccc1df38c5012`.
Combined source is local integration commit
`0390f5d2d9deee4339a29c885f023e206a4f35ab`; its native archive is
`f571ef574c43fc8ce8787813f9c866b62bc7c679bcc6e42d0c7317c3c5fe324a`.
The serial factorial rebuild reproduced that exact combined archive. All current
programs use pinned compiler SHA-256
`23f2e89aafe312160062cda12010ce4511366ee8131e87847a00bbce36806c89`; helpers match
`8315efc0c1ae0b87ff80185ee282e4ede97e82afa6ecfe1825fe296549bc46ef`.
Native states came from the same integration worktree path. Normal CLI companion
metadata reports **Cranelift, Release**. Effective optimization beyond those
labels was not independently verified; no backend, assembly, placement or
ownership/constructor investigation occurred.

Earlier PR evidence used a different pinned compiler/current-source context.
Those historical results stay separate and are not erased by this new phase.
The following current data do not pool with earlier PR samples, with one another,
or with the still-unrun budget/correction controls. Recorded here on the same
coordinated Linux/Xeon VM; exact recorded commands, hashes and schedules are
preserved. Input frequencies on real applications and other platforms were not
measured.

### Initial combined comparison

`initial-combined/` preserves four completed two-way datasets: normalization full
100×2×7=1400 rows; normalization focused30×2×9=540; reversal full83×2×7=1162;
reversal focused18×2×9=324. Every original raw/summary/paired/per-pair file stays
intact. `record.json` contemporaneously records each build/comparison command and
exit; `launch-record.json` records root session73306 actual exit 0 after completion
from the tool transcript, not a contemporaneous runner-emitted record. Source and
identity snapshots are under `inputs/`; public metadata and build stderr are
ordinary named copies. All operation/output/error/checksum guards passed.

All eight large Unicode-prefix results from the normalization full phase follow:

| State/phase | Case | Before median ms | After median ms | Change | Paired delta ms | Slower |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| combined / initial-normalize-full | `early_unicode_1048576_NFC` | 29.902 | 32.260 | +7.89% | +2.564 | 5/7 |
| combined / initial-normalize-full | `late_unicode_1048576_NFC` | 30.370 | 32.781 | +7.94% | +2.684 | 5/7 |
| combined / initial-normalize-full | `early_unicode_1048576_NFD` | 18.517 | 21.092 | +13.91% | +2.844 | 7/7 |
| combined / initial-normalize-full | `late_unicode_1048576_NFD` | 18.199 | 21.509 | +18.19% | +2.377 | 7/7 |
| combined / initial-normalize-full | `early_unicode_1048576_NFKC` | 29.027 | 31.261 | +7.70% | +2.908 | 5/7 |
| combined / initial-normalize-full | `late_unicode_1048576_NFKC` | 29.631 | 32.941 | +11.17% | +3.538 | 7/7 |
| combined / initial-normalize-full | `early_unicode_1048576_NFKD` | 19.430 | 20.163 | +3.77% | +0.707 | 4/7 |
| combined / initial-normalize-full | `late_unicode_1048576_NFKD` | 19.195 | 19.848 | +3.40% | +1.389 | 6/7 |

### Four-state attribution using unchanged original100

`factorial/results/` preserves 2800 raw rows (100 cases × 4 states × 7 rounds), four
validated warmups, all 32 validated producer statuses, and every stdout/stderr.
Its input-integrity record confirms unchanged source/identities/parser/protocol/
program hashes before and after. All four programs use the **original100 source**
SHA-256 `252fa9d83f11dd9ba817cd1a8324b423c147f0e4959cee02e14bc0a10540eeb4` and
identities `fd34146cd146a6bb37064d4ba662fd9360cc0a483a75ebe2243dbeb5642c0348`,
not the new72 controls. The fixed seven-round rotation/reversal is **near-balanced**
(1–2 appearances per position), not fully balanced. Every round's order is
preserved. Medians/ranges and per-round paired differences/signs vs baseline
remain separate; a ratio of medians is not a paired median. No confidence or
universal causality claim is inferred from seven rounds.

Root session8145 actually exited 0. `launch-record.json` records its exact invoked
argv from the tool transcript **after** the run; the runner itself emitted the
protocol, inputs, raw samples, statuses, summaries and before/after integrity.

Normalization-only large-prefix results are:

| State/phase | Case | Before median ms | After median ms | Change | Paired delta ms | Slower |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| normalize_only / factorial-original100 | `early_unicode_1048576_NFC` | 32.147 | 34.454 | +7.18% | +2.467 | 5/7 |
| normalize_only / factorial-original100 | `late_unicode_1048576_NFC` | 31.452 | 35.538 | +12.99% | +3.424 | 6/7 |
| normalize_only / factorial-original100 | `early_unicode_1048576_NFD` | 19.752 | 22.573 | +14.28% | +3.583 | 6/7 |
| normalize_only / factorial-original100 | `late_unicode_1048576_NFD` | 20.065 | 22.909 | +14.17% | +2.913 | 5/7 |
| normalize_only / factorial-original100 | `early_unicode_1048576_NFKC` | 30.752 | 34.072 | +10.80% | +3.696 | 6/7 |
| normalize_only / factorial-original100 | `late_unicode_1048576_NFKC` | 31.047 | 34.392 | +10.77% | +1.445 | 6/7 |
| normalize_only / factorial-original100 | `early_unicode_1048576_NFKD` | 19.795 | 21.574 | +8.99% | +2.324 | 6/7 |
| normalize_only / factorial-original100 | `late_unicode_1048576_NFKD` | 20.154 | 21.876 | +8.55% | +1.951 | 5/7 |

The observed normalization-only median penalties span
**7.18–14.28%**, with five or six of seven slower paired rounds. The factor reproduces the
concern without reversal; it is not merely a combined-only observation. Reversal
and combined results remain below, including unfavorable signs/deltas:

| State/phase | Case | Before median ms | After median ms | Change | Paired delta ms | Slower |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| reverse_only / factorial-original100 | `early_unicode_1048576_NFC` | 32.147 | 32.394 | +0.77% | -0.463 | 3/7 |
| reverse_only / factorial-original100 | `late_unicode_1048576_NFC` | 31.452 | 31.760 | +0.98% | +0.308 | 4/7 |
| reverse_only / factorial-original100 | `early_unicode_1048576_NFD` | 19.752 | 20.022 | +1.36% | +0.697 | 4/7 |
| reverse_only / factorial-original100 | `late_unicode_1048576_NFD` | 20.065 | 19.740 | -1.62% | -1.043 | 1/7 |
| reverse_only / factorial-original100 | `early_unicode_1048576_NFKC` | 30.752 | 30.921 | +0.55% | -0.158 | 3/7 |
| reverse_only / factorial-original100 | `late_unicode_1048576_NFKC` | 31.047 | 32.541 | +4.81% | -0.622 | 3/7 |
| reverse_only / factorial-original100 | `early_unicode_1048576_NFKD` | 19.795 | 19.900 | +0.53% | +0.305 | 4/7 |
| reverse_only / factorial-original100 | `late_unicode_1048576_NFKD` | 20.154 | 19.988 | -0.82% | -0.724 | 2/7 |
| combined / factorial-original100 | `early_unicode_1048576_NFC` | 32.147 | 35.157 | +9.36% | +3.207 | 5/7 |
| combined / factorial-original100 | `late_unicode_1048576_NFC` | 31.452 | 35.373 | +12.47% | +3.080 | 5/7 |
| combined / factorial-original100 | `early_unicode_1048576_NFD` | 19.752 | 22.384 | +13.32% | +2.957 | 6/7 |
| combined / factorial-original100 | `late_unicode_1048576_NFD` | 20.065 | 22.663 | +12.94% | +1.883 | 5/7 |
| combined / factorial-original100 | `early_unicode_1048576_NFKC` | 30.752 | 33.564 | +9.15% | +2.952 | 6/7 |
| combined / factorial-original100 | `late_unicode_1048576_NFKC` | 31.047 | 34.660 | +11.64% | +3.985 | 6/7 |
| combined / factorial-original100 | `early_unicode_1048576_NFKD` | 19.795 | 21.043 | +6.30% | +1.639 | 6/7 |
| combined / factorial-original100 | `late_unicode_1048576_NFKD` | 20.154 | 21.879 | +8.56% | +2.171 | 5/7 |

## Complete distributions and unfavorable observations

`all-case-statistics.csv` contains every case from all four initial datasets and
all three factorial state-vs-baseline comparisons: medians, per-state ranges,
median change, paired delta/ranges and signs. `unfavorable-medians.csv` retains
every unfavorable median without a significance or frequency filter. Original
raw files and full paired/range outputs remain the source of truth. A nominal
unfavorable median with favorable paired signs is kept, not promoted to a stable
cost. `factorial/interaction-samples.csv` records per-round C−N−R+B and
(C/N)/(R/B) descriptively; it does not explain machine/codegen mechanisms.

## Reconstructable source states

`source-states/` contains exact source snapshots and normalization-only,
reversal-only and combined patches **against public db975ce2 string.rs**. These
patches reconstruct the combined file without requiring the local integration
commit to be remotely available. The baseline snapshot/hash is included; source
commits 051529/0525 and source/native/program hashes are recorded in the manifest.
The report copies source, commands, metadata, logs and hashes, **not binaries,
native archives or helper IR**. Those remain at their recorded original paths.
All four state source factors and compiler/native hashes are explicit; no
production source was edited while preparing this report.

## Open partial-revert candidate and budget tradeoff

`unvalidated-partial-revert/` contains only the now-completed preparation records,
source/patch and runtime/native-test logs. Root session74824 completed runtime
build and 22 string tests with exit 0. Candidate native hash is
`7e102752b7870a1eb1c6b4852f89caf225f2d40d4dc5ea96fce51d2631affe59`; helpers match.
The intended one-factor correction keeps the exact ASCII bypass and restores the
baseline eager Unicode decode-to-`Vec<char>` body, without reversal or new helper,
reserve, guard or constructor changes. Correctness/build success does **not**
establish performance acceptance. No partial-revert timing result is included.

Restoring eager Unicode decoding also restores full-input character storage and
predecode before a valid `LimitExceeded` can be returned. A Rust `char` occupies
4 bytes. For these prefix inputs, scalar payload alone requires at least 16,392 bytes for 4 KiB plus two Unicode scalars, and 4,194,312
bytes for 1 MiB plus two scalars. Canonical/compatibility 65536 inputs each contain
131,072 scalars, at least 524,288 bytes of character payload.
These are **payload lower bounds**, not measured capacity, total peak memory,
allocation count or RSS; vector spare capacity/normalizer/output storage may add
more. ASCII shortcut cases avoid this Unicode input vector. No allocator/cache
internals or retention probes were performed.

The eager path can lose valid zero/one-byte-budget early-exit gains even when it
restores unlimited Unicode speed. Normalization can also look ahead through a
complete combining segment, so no general bounded-prefix guarantee is claimed
for the lazy path. `prepared-controls/` keeps 48 and separate 72 source/oracle/
identity snapshots, explicitly **not run yet**. The 72-case version contains the original 48 plus 16
NFC/NFD early/late prefix max0/max1 exact limit errors and eight NFD/NFKC 1 MiB exact/
one-byte-short output budgets. Small-pattern literal oracles determine bytes and
exact error identities. Their short 64-call fast paths may have poor timing
resolution; no precise ratio is promised before measurement.

Root plans four independent two-way comparisons using the unchanged shared
runner: original 100 correction-vs-baseline and correction-vs-lazy (7 pairs each),
then separate 72 budget controls vs baseline and lazy (9 pairs each). They must
remain distinct and preserve all unfavorable costs, original phases and raw
samples. Correction/revert choice, further gates and publication are still open;
this report does not declare the string lane complete.

## Immutable evidence and preparation boundary

`source-states/reconstruction-proof.json` verifies every snapshot against its
named source commit and replays each state patch purely in memory against the
public baseline. Replaying the combined patch reconstructs the exact combined
snapshot without relying on a remotely published integration commit. The report
includes no executable, native archive or helper IR copies.

`evidence-whitespace.json` lists exact byte-preserved patch/log/report whitespace
exceptions for future staging review. Raw data, producer stdout/stderr, completed
records and archived source patches have not been rewritten. The two launch
records explicitly disclose their after-run transcript provenance. The final
manifest hashes every staged file; original paths inside raw metadata remain
provenance and are not rewritten to suggest a different execution context.
