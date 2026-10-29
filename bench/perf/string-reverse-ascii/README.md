# String reversal by existing scalar bytes

Final V3 candidate on baseline `4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`.
The 83-case seven-pair comparison and separate 18-case nine-pair focus are
complete. Production/source correctness, Rust formatting, and the serial strict
2393-case conformance selection pass. Workspace clippy and repository checks
also pass. Independent immutable review, required CI and publication remain
pending. Root owns all builds, gates and publication. This report is not merge
approval and makes no universal-speed claim.

## Final mechanism and contract

Reversal remains Unicode scalar reversal, including combining marks and ZWJ;
grapheme clusters are not preserved. Empty and one-byte ASCII use existing
constructors. Longer all-ASCII input copies to the existing vector type and
reverses its bytes. A non-ASCII first byte avoids a failed ASCII scan; a later
Unicode scalar pays for a failed scan before the scalar loop.

The final scalar loop groups width-one results first: malformed U+FFFD/width-one
results retain the original replacement encoding; other width-one results push
the decoded ASCII byte. Wider valid scalars copy their canonical original UTF-8
span. Literal U+FFFD is valid width three. This grouping avoids testing ASCII and
replacement cases on every wider scalar. Constructors, allocator, output
representation, resource/ownership machinery and public signatures are unchanged.
Malformed input retains one replacement scalar per invalid decoded byte. No
backend, compiler, assembly, code-placement or ownership investigation is included.

## Matched builds and correctness

The baseline archive and each candidate came from this same reverse worktree
path. Baseline source was temporarily restored with an exit trap protecting the
candidate. The same pinned compiler was used for all pairs: SHA-256
`cd158b8ca24e62776ba38aa8b774e57f4dd1434346d2edc7569211e7b848c0fc`.
All pure helpers match SHA-256
`8315efc0c1ae0b87ff80185ee282e4ede97e82afa6ecfe1825fe296549bc46ef`.
Final archive SHA-256 is
`8ff7c374d80c5468d82feba7651c59c0213f32985b47d7b5d1fb96960f7e8651`;
final full-program SHA-256 is
`532574466b05a70b5c3bb075a7d21526051bf584e294df46b37c083d23adeedb`.

Normal public CLI build JSON and companion metadata are copied verbatim under
[build-metadata](build-metadata/). Companion files label programs **Cranelift,
Release**. The explicit cached `MS_LLVM_TOOLS` selection does not establish an
effective backend or optimization level beyond that metadata; neither was
investigated. Artifact paths, snapshots and hashes are in [builds.json](builds.json).

All 22 native Rust string tests pass. Exact-byte cases cover all 128 ASCII
values, NUL, literal U+FFFD, mixed widths and boundaries, malformed/truncated/
overlong/surrogate/out-of-range bytes, including ASCII before/after Unicode.
Both original reverse source tests and the added ASCII/control fallback test
pass in Release and Debug (three tests in each profile). Logs retain exact test
names/results. The serial strict selected corpus also passes as recorded below;
workspace clippy/repository checks also pass. Any earlier CLI-usage preparation
failure is retained separately from successful test logs.

## Workload and method

Recorded 2026-10-29 on the coordinated Intel Xeon Platinum 8573C Linux VM (five
exposed CPUs, Linux 6.18.55, Rust 1.99.1). Runner/producers use CPU 0 with no
concurrent timed jobs or native builds. Other platforms and application input
frequencies were not measured.

The 83 identities preserve the original 79 controls and add Unicode before/after
4 KiB and 1 MiB ASCII prefixes. ASCII lengths span 0/1/2 and boundaries around
8/16/32/64 bytes through 1 MiB. Unicode covers two-, three-, four-byte scalars,
mixed widths, NUL, combining marks, ZWJ and literal replacement characters.
Independent reversed literal patterns construct expected outputs; `reverse`
never constructs an oracle. Every timed call checks the complete result and
consumes output byte length plus 17 in a checked checksum. Timings include full
validation and result release. Setup, expected-value construction, checked warm-up,
compilation, startup and printing are outside timing. These are end-to-end
operation timings, not isolated reversal-kernel costs.

The full final data are `width-samples.csv` (1162 rows: 83 × two × seven).
`width-summary.csv` preserves every median and range; `width-paired.csv` preserves
paired signs/delta/ratio distributions; `width-paired-samples.csv` preserves all
581 normalized pairs. All inventories/checksums/iteration counts, medians, ranges,
and paired signs/deltas were independently recomputed. No sample was discarded.

## Final full comparison

Representative results follow; all values are ns per operation. The tables use
ratio-of-medians change; paired median candidate-minus-baseline deltas and slower
pair counts remain separate.

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ascii_mixed_n1` | 24.2 | 6.6 | -72.88% | -18.013 | 0/7 |
| `ascii_mixed_n2` | 34.3 | 27.1 | -21.09% | -7.811 | 0/7 |
| `ascii_mixed_n16` | 153.9 | 36.7 | -76.15% | -119.330 | 0/7 |
| `ascii_mixed_n64` | 524.6 | 45.6 | -91.31% | -478.895 | 0/7 |
| `ascii_mixed_n4096` | 31582.3 | 1068.8 | -96.62% | -30103.985 | 0/7 |
| `ascii_mixed_n1048576` | 8731961.0 | 398899.8 | -95.43% | -8286224.250 | 0/7 |
| `two_byte_copies1` | 76.7 | 69.4 | -9.44% | -9.898 | 1/7 |
| `combining_copies65536` | 3162807.1 | 1796718.6 | -43.19% | -1166313.688 | 0/7 |
| `replacement_copies65536` | 1096084.4 | 796800.0 | -27.30% | -299920.736 | 0/7 |

All 81 nonempty full-matrix medians improve. Full mixed empty input retains
about **+1.5 ns**, with **seven of seven slower pairs** and paired median
**+0.924564 ns**. The duplicate empty-control median improves, with two of seven
slower pairs and paired median −0.275530 ns. These different empty observations
remain separate. Every unfavorable full-run median is retained below; full ranges
and per-pair outliers remain in the CSVs.

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ascii_mixed_n0` | 5.2 | 6.7 | +28.81% | +0.925 | 7/7 |

The four Unicode-prefix controls specifically retain failed-scan and mixed-input
costs. All four results follow, including unfavorable measurements.

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `late_unicode_4096` | 31887.7 | 10661.1 | -66.57% | -21226.594 | 0/7 |
| `early_unicode_4096` | 32462.8 | 11344.6 | -65.05% | -21230.454 | 0/7 |
| `late_unicode_1048576` | 8825549.7 | 2589406.0 | -70.66% | -6053275.875 | 0/7 |
| `early_unicode_1048576` | 8289290.2 | 2436970.6 | -70.60% | -5843556.250 | 0/7 |

The pure two-byte family improves across all seven full-matrix sizes (about
1.104–1.256×, five to seven of seven faster pairs). That family was not separately
repeated in the focused 18-case program; this is full-matrix evidence only.

## Separate focused controls and remaining cost

`width-focused-samples.csv` preserves 324 rows: 18 cases × two variants × nine
pairs. Short controls use two million iterations, prefix 4 KiB controls 8192,
and large controls 64. The focused program is a separate workload/process scope;
its results do not replace or pool with the full matrix. Every focused result is
shown below, with all ranges/outliers retained in `width-focused-summary.csv`,
`width-focused-paired.csv` and `width-focused-paired-samples.csv`.

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ascii_mixed_n0` | 5.9 | 6.3 | +6.88% | +0.084 | 5/9 |
| `ascii_mixed_n1` | 31.2 | 7.1 | -77.11% | -18.229 | 0/9 |
| `ascii_mixed_n2` | 48.8 | 30.3 | -37.97% | -21.103 | 0/9 |
| `ascii_mixed_n1048576` | 10863161.1 | 552075.2 | -94.92% | -10090570.484 | 0/9 |
| `ascii_controls_n0` | 5.9 | 7.0 | +19.63% | +0.467 | 7/9 |
| `ascii_controls_n1` | 26.3 | 8.1 | -69.27% | -19.227 | 0/9 |
| `ascii_controls_n2` | 40.9 | 29.8 | -27.21% | -10.550 | 1/9 |
| `ascii_controls_n1048576` | 10688899.4 | 462676.0 | -95.67% | -10098329.828 | 0/9 |
| `combining_copies1` | 89.9 | 58.0 | -35.51% | -31.931 | 1/9 |
| `combining_copies2` | 139.0 | 91.0 | -34.54% | -57.830 | 0/9 |
| `combining_copies65536` | 3543986.3 | 2036575.1 | -42.53% | -1544340.859 | 0/9 |
| `replacement_copies1` | 46.0 | 39.6 | -13.87% | -8.635 | 1/9 |
| `replacement_copies2` | 63.4 | 51.1 | -19.36% | -12.723 | 3/9 |
| `replacement_copies65536` | 1319201.4 | 964069.4 | -26.92% | -357433.984 | 0/9 |
| `late_unicode_4096` | 38818.5 | 11792.8 | -69.62% | -26145.630 | 0/9 |
| `early_unicode_4096` | 36658.3 | 13404.3 | -63.43% | -25464.010 | 0/9 |
| `late_unicode_1048576` | 9888150.2 | 3197494.7 | -67.66% | -6697250.281 | 0/9 |
| `early_unicode_1048576` | 10779267.6 | 3103852.2 | -71.21% | -6818795.922 | 0/9 |

All 16 nonempty focused medians improve. Empty mixed input retains about +0.4 ns
by median (five of nine slower, paired median +0.084 ns), and empty controls about
+1.1 ns (seven of nine slower, paired median +0.467 ns); checked outliers are wide.
Full-matrix empty controls have different directions. These empty costs are
retained rather than rounded away or declared resolved. Frequency in real
programs was not measured, so applications dominated by empty calls may weigh
this tradeoff differently. Final acceptance requires independent assessment and
normal gates; broad ASCII gains do not excuse reproducible common-input costs.

## Prior variants, retained separately

- **V0, span copy only:** [../string-reverse-spans](../string-reverse-spans/)
  contains all 79-case/seven-pair data and separate ten-case/nine-pair focus,
  source/patch/build evidence. It was discarded, not an unrun proposal.
- **V1, bulk ASCII plus spans:** `bulk-ascii-runtime.patch`, `samples.csv`,
  `summary.csv`, `paired*.csv` preserve 83/seven pairs. `focused-*.csv` and
  `focused-controls.ms` preserve 18/nine pairs. Large ASCII gains were accompanied
  by adverse Unicode-prefix observations; no acceptance followed from ASCII alone.
- **V2, byte push:** `byte-push-runtime.patch` and `byte-push-*.csv` preserve
  83/seven pairs. This explicitly pushed ASCII inside the Unicode loop while
  retaining span copy for wider scalars. Its observations remain separate.
- **V3, width grouping:** `runtime.patch` and `width-*.csv` are the final candidate;
  width-one ASCII/error predicates are avoided on wider scalars. This was a causal
  operation removal, not arbitrary placement/inline tuning. No additional variant
  or broader performance claim is proposed.

V1 full/focused Unicode-prefix results follow. Their costs remain visible even
if final results improve; they are distinct executable versions.

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `late_unicode_4096` | 32091.0 | 40296.2 | +25.57% | +5272.671 | 6/7 |
| `early_unicode_4096` | 34118.3 | 39925.9 | +17.02% | +2329.869 | 7/7 |
| `late_unicode_1048576` | 9131875.0 | 11540672.2 | +26.38% | +3124902.875 | 7/7 |
| `early_unicode_1048576` | 9174739.4 | 10534392.1 | +14.82% | +2025377.062 | 6/7 |

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `late_unicode_4096` | 35428.2 | 37964.7 | +7.16% | +2748.955 | 6/9 |
| `early_unicode_4096` | 35659.5 | 37478.4 | +5.10% | +2121.266 | 6/9 |
| `late_unicode_1048576` | 9128601.5 | 10031105.9 | +9.89% | +627932.484 | 8/9 |
| `early_unicode_1048576` | 8885541.5 | 10310947.2 | +16.04% | +834051.688 | 8/9 |

Every V2 unfavorable median is preserved below; original raw/paired data retains
all other cases and ranges.

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ascii_mixed_n0` | 5.7 | 6.2 | +9.34% | -0.181 | 3/7 |
| `ascii_controls_n0` | 5.0 | 5.2 | +5.56% | -0.055 | 3/7 |
| `two_byte_copies2` | 116.1 | 139.4 | +20.03% | +22.107 | 7/7 |
| `two_byte_copies8` | 372.6 | 425.0 | +14.05% | +33.133 | 5/7 |
| `two_byte_copies32` | 1524.0 | 1663.7 | +9.17% | +134.556 | 5/7 |
| `two_byte_copies256` | 12251.7 | 13152.1 | +7.35% | +846.248 | 4/7 |
| `two_byte_copies65536` | 3162788.0 | 3295522.8 | +4.20% | -15146.125 | 3/7 |
| `three_byte_copies65536` | 3873815.1 | 4099648.5 | +5.83% | +225833.375 | 4/7 |
| `four_byte_copies1` | 93.4 | 95.0 | +1.63% | +3.962 | 4/7 |
| `four_byte_copies32` | 2135.3 | 2156.5 | +1.00% | +17.024 | 5/7 |
| `zwj_copies8` | 417.2 | 441.0 | +5.70% | +23.792 | 4/7 |
| `zwj_copies256` | 12956.4 | 13346.5 | +3.01% | -836.081 | 2/7 |
| `replacement_copies1` | 36.7 | 42.3 | +15.00% | +5.018 | 4/7 |
| `replacement_copies32` | 473.9 | 474.0 | +0.01% | +21.230 | 4/7 |

## Final local gate evidence and input integrity

Rust formatting completed with actual exit **0**; its completed record is
`checks/fmt.log`. Root's sole serial conformance invocation also exited **0**:
**2393/2393 selected fixtures passed**, comprising 1603 check, 531 run and 259 test
outcomes; failed, expected-failed, unexpected-passed and unrecorded counts are all
zero. Lint reports 4153 available fixtures and zero problems. The command preserves
the existing selected phases, strict expectations, `aliasing` exclusion,
expect-fail input and shard `0/1`; no filter or expectation was changed for this
candidate. This is a serial pinned-input local result, not a claim that a make
invocation or required CI passed.

The completed [log](checks/conform-pinned.log),
[Markdown report](checks/conform-pinned-report.md), and
[JSON report](checks/conform-pinned-report.json) preserve exact outcomes.
[checks/conform-input-integrity.json](checks/conform-input-integrity.json) records
the exact command plus **immediate before and after hashes** of compiler, runtime,
pure helper, harness and expect-fail input. Every hash, size and recorded file
mode matches. The dedicated `/tmp/string-round2/reverse-width-conform-inputs`
snapshot directory was mode 555 before execution; executables were 555 and data
444. It was never a scheduled build destination. Root was the sole gate executor,
with delegates limited to documentation/read-only work and no builds during the
replay. The validated runtime hash is the same final V3 archive recorded above.

Freshness: root checked `origin/main`
`db975ce2f01ddf8da108ec9045ecaf66a63ab22c` at 17:44 UTC against baseline `4be5d6d8c`.
There was no difference in string/UTF-8/ABI/Cargo/toolchain/AGENTS/runtime/create-pr
paths; no rebase was requested. Root serialized workspace clippy
(`--workspace --all-targets --locked -- -D warnings`) and `make repo-check`; both
completed with actual exit **0**. Their completed logs and exact commands/exits in
`checks/final-gates.json` are retained and hashed. No production source changed
during this report work.

## Reproduction and pending gates

The checkout includes the reviewed shared runner extension with strict
`--identity-file` validation while preserving its default line inventory. Preserve
same-path matched runtimes, pinned compiler, identical helpers and public JSON.
Do not run a comparison during coordinated builds/tests/other timings.

```sh
. /tmp/string-env.sh
MS_RT_LIB=/tmp/string-round2/reverse-before/libms_native.a MS_LLVM_TOOLS=/workspace/.cache/ms/llvm/d19868df5ca10629 /tmp/string-round2/ms build bench/perf/string-reverse-ascii/main.ms --build-type Release -o /tmp/string-round2/reverse-before/ascii-program --json
MS_RT_LIB=/tmp/string-round2/reverse-width-after/libms_native.a MS_LLVM_TOOLS=/workspace/.cache/ms/llvm/d19868df5ca10629 /tmp/string-round2/ms build bench/perf/string-reverse-ascii/main.ms --build-type Release -o /tmp/string-round2/reverse-width-after/program --json
taskset -c 0 python3 bench/perf/string-lines/compare.py /tmp/string-round2/reverse-before/ascii-program /tmp/string-round2/reverse-width-after/program bench/perf/string-reverse-ascii/width-samples.csv --pairs 7 --identity-file bench/perf/string-reverse-ascii/identities.json
```

Build `focused-controls.ms` with the same archives, then use `--pairs 9` and
`focused-identities.json`. All raw data and variant evidence must stay intact;
regeneration should use new output paths. No CI timing threshold is introduced.
Final immutable artifact review and normal required CI remain pending. Local
formatting, workspace clippy, repository checks and controlled serial conformance
pass are recorded above with completed logs and input proof. Workspace nextest's known
excluded `ms-build::debug_artifacts` path is outside this lane. No tests/allowlists
will be altered or skipped to obtain a pass. The shared target symlink is not
part of the change. No production commit, push or PR has been performed by this
report-preparation agent.

## Evidence byte preservation

Saved unified patches retain required single-space blank-context prefixes. The
four patch artifacts are `../string-reverse-spans/runtime.patch`,
`bulk-ascii-runtime.patch`, `byte-push-runtime.patch`, and `runtime.patch`.
The generated `checks/conform-pinned-report.md` retains its original final blank
line. These byte-preserved evidence files can produce whitespace-check warnings;
their hashes are intentional. Source, reports and logs were not rewritten to
hide a check failure. Root will perform the staged diff check with these exact
evidence exceptions disclosed.
