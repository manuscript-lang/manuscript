# Integration normalization regression: completed evidence and open correction

**Attribution established; partial correction rejected; full rollback under checks.** The new same-path
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

## Rejected partial-revert results

**The partial candidate is rejected.** Root session 48019 exited 0 and all four
independent two-way comparisons completed with valid producer/output/error/
identity/checksum guards: original 100 vs baseline: 1400 rows; original 100 vs lazy:
1400; separate 72 vs baseline: 1296; separate 72 vs lazy: 1296. All **5392 raw rows**,
all summaries/ranges and paired signs/delta/ratio distributions are preserved in
`partial-revert-results/`, without pooling these phases with attribution or one
another. The per-comparison commands/exits and finished time are contemporaneous
in `record.json`; `phase-status.json` labels the overall exit provenance from
root’s actual tool session handoff. Build/test correctness did not imply
performance acceptance.

The original100 comparison against baseline still has late 1 MiB NFD **+11.06%**
(seven of seven slower), early 1 MiB NFD **+8.12%** (five of seven), and late 1 MiB
NFKD **+20.76%** (six of seven), plus other unfavorable common cases. All eight
large-prefix observations follow, including gains and mixed paired signs:

| Comparison | Case | Reference median ns | Partial median ns | Median change | Paired delta ns | Slower |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| full-vs-baseline | `early_unicode_1048576_NFC` | 37243485.625 | 35403211.812 | -4.94% | -782696.312 | 3/7 |
| full-vs-baseline | `late_unicode_1048576_NFC` | 34786528.000 | 34871981.625 | +0.25% | -394333.625 | 3/7 |
| full-vs-baseline | `early_unicode_1048576_NFD` | 21553549.438 | 23304473.750 | +8.12% | +2074617.750 | 5/7 |
| full-vs-baseline | `late_unicode_1048576_NFD` | 21004490.062 | 23327721.938 | +11.06% | +2151631.812 | 7/7 |
| full-vs-baseline | `early_unicode_1048576_NFKC` | 33306473.562 | 34561897.188 | +3.77% | +1005280.125 | 5/7 |
| full-vs-baseline | `late_unicode_1048576_NFKC` | 35011982.125 | 35513100.750 | +1.43% | +2439256.188 | 5/7 |
| full-vs-baseline | `early_unicode_1048576_NFKD` | 21053698.875 | 22421304.500 | +6.50% | +2517055.625 | 5/7 |
| full-vs-baseline | `late_unicode_1048576_NFKD` | 21100757.812 | 25480251.875 | +20.76% | +4992008.688 | 6/7 |

### Valid LimitExceeded tradeoff, measured separately

Every max0/max1 case expects the exact existing `StringError.LimitExceeded`, not
invalid input. Partial eager decoding restores full-input work before returning
that valid error. The following 16 cases compare the partial candidate against
lazy normalization; both variants return the checked same error. These are
**public end-to-end ns/op** including status validation/checksum arithmetic,
not isolated decode or allocation timings. Every range/outlier remains in the
CSV. Small 64-call lazy intervals may be short, so the table uses absolute times
and paired deltas; it does not promote huge ratios as precise speed estimates.

| Comparison | Case | Reference median ns | Partial median ns | Median change | Paired delta ns | Slower |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| budget-vs-lazy | `early_unicode_4096_NFC_max0` | 83.003 | 7882.114 | +9396.19% | +7770.358 | 9/9 |
| budget-vs-lazy | `early_unicode_4096_NFC_max1` | 79.690 | 7936.780 | +9859.51% | +7860.432 | 9/9 |
| budget-vs-lazy | `late_unicode_4096_NFC_max0` | 99.249 | 7492.819 | +7449.50% | +7284.631 | 9/9 |
| budget-vs-lazy | `late_unicode_4096_NFC_max1` | 163.020 | 7730.140 | +4641.83% | +7600.914 | 9/9 |
| budget-vs-lazy | `early_unicode_4096_NFD_max0` | 29.419 | 7790.639 | +26381.27% | +7761.219 | 9/9 |
| budget-vs-lazy | `early_unicode_4096_NFD_max1` | 106.412 | 7405.918 | +6859.67% | +7325.959 | 9/9 |
| budget-vs-lazy | `late_unicode_4096_NFD_max0` | 81.105 | 7595.559 | +9265.12% | +7475.514 | 9/9 |
| budget-vs-lazy | `late_unicode_4096_NFD_max1` | 108.223 | 7662.336 | +6980.14% | +7523.935 | 9/9 |
| budget-vs-lazy | `early_unicode_1048576_NFC_max0` | 78.906 | 1680049.922 | +2129072.18% | +1679971.219 | 9/9 |
| budget-vs-lazy | `early_unicode_1048576_NFC_max1` | 73.031 | 1597877.219 | +2187836.29% | +1597806.156 | 9/9 |
| budget-vs-lazy | `late_unicode_1048576_NFC_max0` | 22418.016 | 1721385.672 | +7578.58% | +1702976.312 | 9/9 |
| budget-vs-lazy | `late_unicode_1048576_NFC_max1` | 18329.312 | 1631921.016 | +8803.34% | +1590745.109 | 9/9 |
| budget-vs-lazy | `early_unicode_1048576_NFD_max0` | 34.656 | 1651650.703 | +4765709.06% | +1651617.219 | 9/9 |
| budget-vs-lazy | `early_unicode_1048576_NFD_max1` | 69.594 | 1623193.625 | +2332284.19% | +1623121.906 | 9/9 |
| budget-vs-lazy | `late_unicode_1048576_NFD_max0` | 20706.875 | 1836370.156 | +8768.41% | +1814559.266 | 9/9 |
| budget-vs-lazy | `late_unicode_1048576_NFD_max1` | 21067.688 | 1667769.672 | +7816.24% | +1647094.438 | 9/9 |

Across these16 valid early-budget controls, the partial candidate is slower than
lazy normalization in every case: observed paired median added costs are about
**7.28–7.86 µs for 4 KiB** and **1.59–1.81 ms for 1 MiB**. These absolute paired
costs describe this phase; the short lazy intervals do not support similarly
precise enormous-ratio claims. Both sides returned the same validated limit error.

For the rejected partial candidate’s **1 MiB** controls specifically, early
NFC/NFD max0/max1 medians change from roughly **35–79 ns to 1.60–1.68 ms**;
late medians change from roughly **18–22 µs to 1.63–1.84 ms**. Each of these
eight comparisons is slower in **9/9 pairs**. Against the original eager baseline,
these eight partial-candidate budget medians are also about **3–29% higher**.
These are **rejected-partial measurements only**, not measurements of the full
rollback now under checks. Allocation counts and RSS were not measured.

Against the original eager baseline, the same controls are separate observations:

| Comparison | Case | Reference median ns | Partial median ns | Median change | Paired delta ns | Slower |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| budget-vs-baseline | `early_unicode_4096_NFC_max0` | 6433.829 | 7459.012 | +15.93% | +926.457 | 9/9 |
| budget-vs-baseline | `early_unicode_4096_NFC_max1` | 6076.598 | 8522.521 | +40.25% | +2166.802 | 8/9 |
| budget-vs-baseline | `late_unicode_4096_NFC_max0` | 6201.574 | 8642.744 | +39.36% | +1822.469 | 8/9 |
| budget-vs-baseline | `late_unicode_4096_NFC_max1` | 6913.237 | 8096.156 | +17.11% | +1246.234 | 8/9 |
| budget-vs-baseline | `early_unicode_4096_NFD_max0` | 6428.926 | 7862.269 | +22.30% | +687.560 | 9/9 |
| budget-vs-baseline | `early_unicode_4096_NFD_max1` | 6480.754 | 9287.176 | +43.30% | +2927.887 | 9/9 |
| budget-vs-baseline | `late_unicode_4096_NFD_max0` | 6532.806 | 7531.486 | +15.29% | +1117.087 | 9/9 |
| budget-vs-baseline | `late_unicode_4096_NFD_max1` | 6559.064 | 7211.409 | +9.95% | +1407.569 | 9/9 |
| budget-vs-baseline | `early_unicode_1048576_NFC_max0` | 1473127.203 | 1902317.500 | +29.13% | +413723.156 | 7/9 |
| budget-vs-baseline | `early_unicode_1048576_NFC_max1` | 1571818.156 | 1723290.828 | +9.64% | +207375.531 | 6/9 |
| budget-vs-baseline | `late_unicode_1048576_NFC_max0` | 1519889.906 | 1830821.797 | +20.46% | +310931.891 | 9/9 |
| budget-vs-baseline | `late_unicode_1048576_NFC_max1` | 1522146.422 | 1829715.953 | +20.21% | +141291.406 | 7/9 |
| budget-vs-baseline | `early_unicode_1048576_NFD_max0` | 1537166.781 | 1662691.156 | +8.17% | +104965.922 | 7/9 |
| budget-vs-baseline | `early_unicode_1048576_NFD_max1` | 1514779.281 | 1616343.359 | +6.70% | +97536.609 | 6/9 |
| budget-vs-baseline | `late_unicode_1048576_NFD_max0` | 1620098.859 | 1799731.469 | +11.09% | +100642.141 | 6/9 |
| budget-vs-baseline | `late_unicode_1048576_NFD_max1` | 1570112.062 | 1617516.609 | +3.02% | +47404.547 | 6/9 |

All eight 1 MiB exact/one-byte-short cases vs each reference are preserved in
`large-exact-and-short-budgets.csv`; successful outputs use known exact bytes
(NFD 1048582, NFKC 1048580), and short budgets check exact LimitExceeded. These are
not substitutes for the early-budget cases or proof that the partial candidate
restores every unlimited-input result. `all-case-statistics.csv` and
`unfavorable-medians.csv` include all 344 partial phase/case rows and every adverse
median; original raw files preserve exact integer elapsed/checksum values.

### Source and format provenance

`partial-revert-results/inputs/raw72-before-format.ms.txt` preserves the prepared 72
source (SHA c3822d1b36e063b367d4a9aecede333c047b63a3b9527bf47168e5cea090c2b8).
The **executed formatted72** is `executed-formatted72.ms`, SHA
1027fb09cf38831da47425b97f4946222091d137b1352165b695c2420fbb6ef6, matching all
three budget-program build records. The original 72 identity SHA
c21f72b4380cf6b2784d2dfafd939ff4e15438895d42b7c97128caa019d408dc is unchanged;
oracle snapshots remain adjacent. The original100 source is unchanged, with
SHA 252fa9d83f11dd9ba817cd1a8324b423c147f0e4959cee02e14bc0a10540eeb4. The standalone 48-case
version remains **prepared/unrun**, preserved separately; its cases are included
in the executed 72-case program. Metadata/log copies use
ordinary names; no executable/native archive/helper IR is copied into this report.

The completed candidate preparation stays under the historically named
`unvalidated-partial-revert/`; its former status is archived in
`history/attribution-before-partial-results.md`. This later result rejects that
candidate. Restored Unicode `Vec<char>` storage has the previously stated payload
lower bounds, **not a measured peak-memory or RSS claim**. No allocator/cache or
ownership investigation was performed.

## Full rollback remains under current-main checks

Root has prepared a full rollback of `normalize_kind` on current main 85cf in
`/workspace/manuscript-normalization-revert`: a 23-line production change restoring
the baseline function while keeping all tests and prior evidence. Root reports
independent static review passed; serial current-main checks, benchmarks and
conformance are currently running. No active full-rollback log/result is copied
or hashed here, and no full-rollback pass or timing claim is made. The string
lane remains open until that decision, required gates and publication complete.

## Memory accounting limit

Restoring eager Unicode decoding also restores full-input character storage and
predecode before a valid `LimitExceeded` can be returned. A Rust `char` occupies
4 bytes. For these prefix inputs, scalar payload alone requires at least 16,392 bytes for 4 KiB plus two Unicode scalars, and 4,194,312
bytes for 1 MiB plus two scalars. Canonical/compatibility 65536 inputs each contain
131,072 scalars, at least 524,288 bytes of character payload.
These are **payload lower bounds**, not measured capacity, total peak memory,
allocation count or RSS; vector spare capacity/normalizer/output storage may add
more. ASCII shortcut cases avoid this Unicode input vector. No allocator/cache
internals or retention probes were performed.

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

Raw prepared 48/72 source snapshots use `.ms.txt` archive names, preserving exact
unformatted bytes without making them active benchmark inputs. Executed formatted
72 remains `.ms`. Original paths inside immutable oracle/metadata JSON retain
provenance; `manifest.json` records the archive-name mapping explicitly.

Historical Rust document snapshots also use `.rs.txt`: the four
`source-states/{baseline,normalize_only,reverse_only,combined}.rs.txt` files and
`unvalidated-partial-revert/string.rs.txt`. Their bytes and source hashes are
unchanged; they are document snapshots, not crate modules or active tests.
`source-states/reconstruction-proof.json` points to the archive names, and
`manifest.json` records all five old-to-new aliases. Archived patch headers and
original build metadata retain the actual production source paths as provenance.
