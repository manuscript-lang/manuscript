# Rejected standard-iterator String reversal: 2026-10-31

The standard-iterator reversal candidate is **rejected**. Large reversals became
faster, but empty/one-byte reversals, normalization controls, repetitive substring
searches and whole-process peak RSS regressed. The production change was removed;
this PR retains evidence and two source tests, with no change under `crates/`.

## Candidate and provenance

On main `98854115f95bfeddbaa362382bfcff85c0499752`, the candidate added exactly
four lines: validate the input with `core::str::from_utf8`, then reverse Unicode
scalars with `chars().rev().collect::<String>()`. The existing body remained as
fallback. This was a separate experiment, not a revival of an earlier rejected
reversal PR. There was no padding, placement tuning or unchanged acceptance repeat.

[The exact patch](results-2026-10-31/reverse-only.patch),
[four source states](results-2026-10-31/states/),
[original build inventory](results-2026-10-31/states.json) and
[textual fallback proof](results-2026-10-31/fallback-source-proof.json) are retained.
The historical `states.json` field `restored_sources` means the candidate was
restored after constructing the four states. The later
[production restoration](results-2026-10-31/production-restoration.json) records
its rejection and exact restoration to baseline with an empty `crates/` diff.

All four native states were built serially in the same worktree path with the
same compiler and benchmark sources: baseline; the byte-search word candidate;
reversal alone; both changes. The word factor is a control, not a change proposed
by this evidence PR. Baseline→reverse isolates the standalone experiment and
word→both tests composition; all five predeclared contrasts remain in the data.

The frozen compiler SHA256 is
`c0206ad63cab27353feb941a70d4f500dca2856beeb184e4cd98cf3b997a4a85`.
Normal MS build metadata says `Release` and **`cranelift`**; this report preserves
that label and makes no backend attribution. Runtime/Rust builds used Rust
1.99.1 (`58cf8f9c3`, LLVM 23.1.1), release optimization, checked arithmetic and
frame pointers. Exact commands, source/native-archive/program hashes and ordinary
build metadata are retained. [Host](results-2026-10-31/host.json): Linux x86_64,
AMD EPYC 9V45, five exposed logical CPUs, timing pinned to CPU 0.
The C compiler version log is stored as lossless UTF-8 JSON, preserving its
original trailing blank line and source hash.

## Protocol and complete coverage

The [predeclared protocol](results-2026-10-31/protocol.md) ran each full suite
once after all builds/checks, with a checked warmup per producer and balanced
rotation/reversal order. Each variant occupied each position twice. This was
not all 4!/5! permutations. Setup/output were outside clocks; complete result
guards and checked checksums stayed observable. Concurrent builds were paused.

| Suite | Cases | Variants | Rounds | Raw rows |
| --- | ---: | ---: | ---: | ---: |
| scalar reversal | 83 | four native + Rust | 10 | 4,150 |
| normalization | 100 | four native | 8 | 3,200 |
| byte search | 220 | four native + Rust | 10 | 11,000 |
| lines | 16 | four native | 8 | 512 |
| literal search/materialized split | 63 | four native + Rust | 10 | 3,150 |
| **Total** | | | | **22,012** |

[Replay record](results-2026-10-31/replay-record.json): complete, all command
exits zero, all 17 recorded input-integrity checks and 34 program-integrity
checks true after the run. Validators reject missing/duplicate cases, changed
input bytes/iterations/checksums, invalid timing and failed producers. All raw
rows, per-case min/median/max, all 3,874 predeclared paired summaries and adverse
results remain. Ratio-of-medians percentages differ from paired median deltas.
These rounds are observations on one host, not confidence intervals.

## Gains retained alongside rejection

Selected reversal medians in microseconds per operation:

| Case | Baseline | Reversal candidate | Idiomatic Rust |
| --- | ---: | ---: | ---: |
| 1 MiB ASCII mixed | 3,355.88 | 553.09 | 1,212.59 |
| two-byte pattern ×65,536 | 1,628.16 | 507.90 | 422.42 |
| early Unicode +1 MiB ASCII | 3,614.16 | 556.27 | 931.16 |

All ten standalone paired reversal comparisons improved for these cases. The
Rust reference constructs an owned String with scalar reversal and the same
inputs, expected outputs, iterations and full output guards. The tiny-case
observation/function overhead matters; different allocation strategies and
these selected large results do not establish universal language parity.

## Costs that reject the change

All times below are nanoseconds per operation. Every row is retained in the
full [reversal](results-2026-10-31/reverse-paired.csv),
[normalization](results-2026-10-31/normalize-paired.csv) or
[text](results-2026-10-31/text-paired.csv) paired table.

| Contrast / case | Before median | After median | Median change | Paired median delta | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline→reverse / empty ASCII mixed | 2.14 | 4.66 | +117.59% | +2.49 | 10/10 |
| baseline→reverse / one-byte ASCII mixed | 10.05 | 13.35 | +32.81% | +3.37 | 10/10 |
| word→both / one ASCII NFKD | 35.05 | 53.12 | +51.57% | +18.60 | 8/8 |
| word→both / composed NFKD | 48.64 | 70.31 | +44.56% | +21.69 | 8/8 |
| word→both / reordered NFKD | 60.87 | 84.35 | +38.56% | +22.92 | 8/8 |
| baseline→reverse / ASCII 4096 NFC | 228,133.85 | 242,509.15 | +6.30% | +12,082.76 | 8/8 |
| baseline→reverse / repetitive index near miss | 1,488.73 | 1,707.69 | +14.71% | +159.96 | 9/10 |
| word→both / repetitive contains near miss | 1,483.72 | 1,618.65 | +9.09% | +119.01 | 10/10 |

Other empty/one-byte reversal cases also added roughly 2.5–3.6 ns in every pair.
The standalone 65,536-copy (320 KiB) ASCII NFKC control rose 7.00%, eight of eight slower
pairs. Full byte/line distributions are retained even where changes are small,
mixed in sign or below these selected costs. The experiment does not identify
the mechanism behind unrelated control changes, nor claim the word candidate
caused them. It rejects this complete combined result rather than trading
common-path costs away for a large reversal win.

## Separate peak-memory evidence

[All 50 child records](results-2026-10-31/rss-results/record.json) retain metrics,
exact stdout and stderr: five position-balanced rotations of five variants,
each for a 4 MiB ASCII and 5 MiB mixed input. Every child guarded the full reversed
output, printed its exact byte length and exited zero. The repository's C
single-child launcher avoids inheriting Python's high-water RSS.

| Workload | Baseline and word KiB | Reversal and both KiB | Increase | Rust median KiB |
| --- | ---: | ---: | ---: | ---: |
| ASCII 4 MiB | 16,660 | 17,680 | +1,020 / +6.12% | 13,368 |
| mixed 5 MiB | 20,756 | 22,032 | +1,276 / +6.15% | 16,440 |

The native values were identical across all five repetitions for each state.
This measures whole-process maximum RSS including inputs, expected strings,
setup and output. Allocation counts and steady-state/retained memory were not
measured; no allocator explanation is inferred.

## Inputs, verification and limits

The exact compact 63-case text workload and independent oracle are retained
under [inputs/text](results-2026-10-31/inputs/text/), including all expected
results and content hashes. Rust byte indices are converted to scalar indices
inside the operation. Capped split truncates pieces using `take`, not `splitn`;
empty separators split scalars without artificial boundary empties. Materialized
split returns List[String]/Vec<String> and compares every full result. Rust
retains its prebuilt corpus; MS constructs each case before measurement. Both
exclude setup. Tiny observation costs and representation differences remain.

The earlier input-size-only and giant-literal text preparations are separately
labeled [unmeasured](results-2026-10-31/unmeasured-preparations/). Their generators,
identities, original source/binary hashes and unchanged semantic-content mapping
remain; giant generated literals can be reconstructed from their generators.
They contribute no timing rows. Compaction and the work-budget correction
preceded all timing. Earlier pre-compaction native build logs/metadata remain
separate. No executable, native archive, Python bytecode or helper IR is published.

Two retained called-source tests verify scalar reversal across UTF-8 widths,
combining/ZWJ/NUL cases and byte-boundary sizes with Unicode at either end.
Baseline/reversal/both passed both profiles before final formatting; the final
formatted source passed both reversal profiles and then both restored-baseline
profiles (two tests, zero failures each). Eight scoped pure-search/normalization
tests passed; the existing formatting and workspace all-target Clippy logs pass.
The initial repo-check formatting failure, its correction and final baseline
repo-check success are all retained. Full workspace nextest/conformance and
excluded runtime/compiler mechanisms were not exercised; this is not a clean
claim for those paths or later main revisions.

Run the portable, read-only evidence check without executing native programs:

```sh
python3 bench/perf/string-reverse-standard/validate.py
```

Original build/replay/analyze scripts and their absolute commands are historical
artifacts, not commands to execute blindly: their original paths and binaries
are intentionally absent in a fresh checkout. To repeat discovery, use an
isolated checkout at the pinned base, reconstruct each saved source state,
build normally with the recorded flags/compiler/archive selections, materialize
the `.ms.txt`/`.rs.txt` input copies, and run the frozen balanced validator after
all CPU work stops. A future candidate needs fresh current-main/final-head
controls and independent review. This rejected patch is not proposed for merge.
