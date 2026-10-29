# Direct padding result construction

Candidate on current-main baseline `4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`.
Rejected after one focused control comparison: common no-op costs remain
unresolved. The runtime is restored exactly to the baseline, with no active
fixture; the candidate patch and source tests are archived in `exploratory/`.

The original productive padding path fills a temporary `Vec` with exact capacity,
then `from_buf` copies the completed result through `from_bytes`. The archived candidate
changes only that destination construction: a stack buffer followed by the existing
constructor up to `STR_INLINE_MAX`, otherwise one existing `alloc_str(total)` result.
Scalar counting, no-op/negative/empty-padding guards, checked byte-size arithmetic,
cycle/remainder calculation, `fill_repeated`, and partial-cycle copying are unchanged.
No new fast-path guard, count cache, allocation/tag/drop machinery, or public API
change is included.

For left padding, the repeated pattern and scalar-prefix remainder fill
`[0, pad_len)`, and original text fills `[pad_len, total)`. For right padding,
text fills `[0, text.len())` and padding fills `[text.len(), total)`. These ranges
initialize exactly the checked result length; the existing heap constructor's
trailing NUL stays untouched. Short results pass through `from_bytes`, preserving
empty/one-byte cache and inline construction. Inputs are never mutated.

Doing nothing remains preferable if end-to-end padding plus validation does not
improve or materially regresses common/control cases. Fewer source-level copies
alone are not a timing result. Existing repeated-fill doubling remains unchanged.

## Independent expected outputs and coverage

`generate.py` constructs expected text by cycling Python Unicode code points with
`itertools.cycle`/`islice`, independently of the runtime's quotient/remainder byte
fill. It never calls padding to generate expected values. Large oracle segments
are emitted as compact literal/repeat expressions outside timing; no padding call
appears in expected generation. `oracle.json` records targets, padding, input scalar
counts, output byte counts, and exact expected UTF-8 SHA-256 values.

The 98 fixed identities cover both directions, ASCII one/multi-byte patterns,
mixed-width Unicode with partial cycles, NUL, empty text, negative/shorter/equal
no-op targets, empty padding, short/cache/inline boundaries, 4 KiB and approximately
1 MiB scaling, and large inputs with only three additional scalars. Six changing-
output cases exercise both grow/shrink orders and Unicode output sizes. Numeric
`target` labels count scalars, so Unicode output can be larger in bytes.

Every timed operation compares the complete output with independent expected text
before contributing its byte length plus 17. Timings are **padding plus full-output
validation**, including result release. Input/expected construction, List lookups
for changing-case setup, checked warm-up, compilation, process startup, and CSV
printing are outside each measured interval. Large no-op results still perform
full output equality; these are not isolated scalar-count measurements.

Byte-based iteration bounds are 128 operations for input/output at least 256 KiB,
4096 at least 4 KiB, 10000 at least 128 bytes, and 100000 below that. Changing cases
perform 128 pad operations as 32 cycles of four output sizes, so their elapsed
values are normalized per pad operation too. Their checksum uses the weighted
sum of all four expected output lengths. Each case has checked untimed warm-up.
Changing-size cases disclose allocation-phase effects; they do not replace fixed-
size or no-op controls.

`identities.json` fixes all names, byte sizes, operation counts, and checksums. The
shared `string-lines/compare.py --identity-file` runner rejects producer failures
and missing/duplicate/unknown/changed identities before emitting comparison rows.
No duplicate validator is added. Generate sources with `python3 generate.py`, then
format the generated benchmark and archived test source with the pinned compiler's `fmt` command before hashing.
All generated JSON/text/source files use LF endings; CSV reporters must use LF too.

The focused fixture is `exploratory/source-tests.ms`: exact boundary,
partial-cycle and NUL results; unchanged no-op text; large output/small growth; and
preflight string-limit faults in both directions. Native checks cover this fixture
in explicit Release and Debug profiles and the existing Rust string unit tests.

## Coordinated reproduction

The baseline and candidate archives must be built from the same worktree path,
with original source saved/restored on failure. Apply the archived
`bench/perf/string-padding/exploratory/runtime.patch` to the named baseline
when reproducing the candidate. Root saved the baseline at
`/tmp/string-round2/before`; candidate goes to `/tmp/string-round2/padding-after`.
Require matching `ms_rt_hot.ll` and use the unchanged pinned compiler
`/tmp/string-round2/ms` (SHA-256
`cd158b8ca24e62776ba38aa8b774e57f4dd1434346d2edc7569211e7b848c0fc`).
Normal builds explicitly select cached LLVM tools; preserve build logs and do not
claim a backend fallback without evidence. `target` is an untracked shared symlink
and must never be added to Git.

```sh
. /tmp/string-env.sh
MS_LLVM_TOOLS=/workspace/.cache/ms/llvm/d19868df5ca10629 \
MS_RT_LIB=/tmp/string-round2/before/libms_native.a /tmp/string-round2/ms build \
    bench/perf/string-padding/main.ms --build-type Release \
    -o /tmp/string-round2/padding-before-program
MS_LLVM_TOOLS=/workspace/.cache/ms/llvm/d19868df5ca10629 \
MS_RT_LIB=/tmp/string-round2/padding-after/libms_native.a /tmp/string-round2/ms build \
    bench/perf/string-padding/main.ms --build-type Release \
    -o /tmp/string-round2/padding-after-program
```

Only after explicit timing isolation:

```sh
taskset -c 0 python3 bench/perf/string-lines/compare.py \
    /tmp/string-round2/padding-before-program /tmp/string-round2/padding-after-program \
    bench/perf/string-padding/samples.csv --pairs 7 \
    --identity-file bench/perf/string-padding/identities.json
```

Preserve full distributions and report ratio-of-medians separately from paired
signs, deltas, and ratios. Retain every control and reject material regressions.
Record revision, source, patch, compiler, archive, helper, program, identity, and
raw-data hashes after normalizing LF endings; do not hash pre-normalized CSV text.

## First matched comparison, 2026-10-29

Both archives were built from this same current-main worktree path, with identical
pure-helper IR and unchanged pinned compiler. [builds.json](builds.json) records
full source/patch/fixture/compiler/archive/helper/program/runner and data hashes.
Normal commands requested Release with the explicit cached `MS_LLVM_TOOLS` path
and supplied no other backend override. Verbatim companion build metadata under
[build-metadata](build-metadata/) labels both programs `backend: "cranelift"`.
Effective optimization beyond this recorded configuration is unverified in this
restricted pass; no LLVM-vs-Cranelift or fallback claim is inferred from flags.
No backend/codegen probe was performed.

The four source tests passed in both explicit Release and Debug; all 20 selected
string Rust tests passed. Logs are preserved in [checks](checks/). Both frontend
checks and Rust formatting passed. No workspace-wide or corpus result is claimed
for this candidate yet.

The 98-case comparison used seven alternating CPU 0 pairs with no concurrent
builds/tests/timed work. Both checked producer warm-ups and all 14 recorded producer
runs completed with zero exit status; every strict identity/checksum and every
exact output check passed. [samples.csv](samples.csv) preserves all 1,372 rows and
[summary.csv](summary.csv) every before/after median and min/max range.
[paired-samples.csv](paired-samples.csv) contains every pair's raw normalized times,
signed after-minus-before delta, ratio, and percent change.
[paired.csv](paired.csv) separately aggregates paired signs/delta medians/ranges
and paired ratios; these are not the ratio-of-medians printed by the shared runner.

Large productive examples improve about 1.49–1.66x for targets of 1,048,576
scalars; all six changing-size medians improve 1.20–1.63x. These wins do not justify
unresolved no-op costs. Every first-matrix median regression follows; values are
ns per operation **including full-output validation**, and paired delta is the
median after-minus-before difference (negative favors candidate):

| Case | Before median | After median | Median ratio | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `start_ascii_target1` | 11.2 | 12.7 | 0.882x | -0.290 | 2/7 |
| `start_unicode_target1` | 13.2 | 14.1 | 0.932x | 2.801 | 5/7 |
| `start_noop_empty_negative` | 11.4 | 11.8 | 0.961x | -0.259 | 3/7 |
| `start_noop_tiny_negative` | 29.3 | 32.7 | 0.895x | 2.930 | 4/7 |
| `start_noop_tiny_empty_padding` | 32.5 | 44.2 | 0.736x | 7.474 | 4/7 |
| `start_noop_long_ascii_negative` | 198746.9 | 223830.6 | 0.888x | 21388.328 | 5/7 |
| `start_noop_long_ascii_empty_padding` | 189523.9 | 277303.3 | 0.683x | 20906.273 | 4/7 |
| `start_noop_long_unicode_empty_padding` | 224356.6 | 228237.4 | 0.983x | 20052.570 | 4/7 |
| `start_positive_shorter` | 30.6 | 40.3 | 0.759x | 11.685 | 6/7 |
| `start_empty_text_byte` | 54.9 | 62.4 | 0.879x | 4.917 | 5/7 |
| `start_empty_text_unicode_heap` | 121.7 | 131.3 | 0.927x | -25.578 | 2/7 |
| `start_mixed_text_unicode_target5` | 100.2 | 107.6 | 0.931x | -12.466 | 3/7 |
| `start_nul_target2` | 53.6 | 56.7 | 0.946x | -0.137 | 3/7 |
| `end_ascii_target4096` | 590.5 | 658.5 | 0.897x | 67.919 | 4/7 |
| `end_unicode_target4096` | 1538.1 | 1679.9 | 0.916x | -273.370 | 2/7 |
| `end_noop_empty_negative` | 13.4 | 18.4 | 0.728x | -0.496 | 3/7 |
| `end_noop_tiny_negative` | 34.4 | 39.5 | 0.870x | -0.379 | 3/7 |
| `end_noop_tiny_empty_padding` | 35.4 | 36.2 | 0.977x | 3.442 | 4/7 |
| `end_noop_long_ascii_empty_padding` | 234341.9 | 256220.5 | 0.915x | 16810.609 | 5/7 |
| `end_positive_shorter` | 36.4 | 40.0 | 0.911x | -4.233 | 3/7 |
| `end_empty_text_byte` | 50.3 | 50.3 | 0.999x | -10.692 | 3/7 |
| `end_mixed_text_unicode_target17` | 134.1 | 142.7 | 0.940x | -16.850 | 2/7 |
| `end_nul_target16` | 80.0 | 81.5 | 0.982x | -20.704 | 3/7 |

The first matrix left acceptance **on hold**, pending the focused check below. For example, left positive-shorter padding changed
30.6→40.3ns with six of seven slower pairs and a+11.685ns paired median. Some other
ratio-of-medians regressions have favorable paired medians/signs, which is why all
raw distributions remain visible rather than choosing a single statistic.

The focused 50-case source/inventory is preserved in
[focused-controls.ms](focused-controls.ms) and
[focused-identities.json](focused-identities.json). It retains all explicit
no-op/negative/empty-padding and target-one cases, positive-shorter, mixed/empty-
text cases, observed4KiB productive slowdowns, and nearby productive winners.
Short intervals use 1M operations, 4KiB/12KiB controls 65536, and approximately
1MiB controls 256. Its recorded comparison below does not replace the original
98-case evidence. No new runtime variant or placement investigation was
part of this focused check.

## Focused controls and rejection, 2026-10-29

The unchanged runtime variant was compared with the same saved baseline using
50 focused cases and nine alternating CPU 0 pairs. All checked warm-ups and all
18 recorded producer runs completed with zero exit status and passed exact output,
full identity, and checksum validation. No concurrent native build/test/timed work
ran. [focused-samples.csv](focused-samples.csv) preserves all 900 rows;
[focused-summary.csv](focused-summary.csv) every median/range;
[focused-paired-samples.csv](focused-paired-samples.csv) every signed delta and ratio;
and [focused-paired.csv](focused-paired.csv) the paired statistics separately.
The existing companion metadata labels the focused programs `cranelift`; effective
optimization remains unverified beyond the recorded configuration.

The productive end-ASCII/Unicode 4KiB slowdowns reversed: focused median speedups
are 1.101x/1.051x, each with six of nine faster pairs. Several initial large ASCII
no-op median regressions reversed too. These are **not** claimed as stable costs.

Common no-op costs remain unresolved. Left positive-shorter padding changed
35.6→39.8ns, with six of nine slower pairs and a +6.538ns paired median, following
30.6→40.3ns and six of seven slower pairs (+11.685ns paired median) in the full run.
The focused end-tiny-negative case changed 32.0→36.8ns, with eight of nine slower
pairs and a +3.173ns paired median; its original paired signs were mixed, despite
an unfavorable ratio of medians. Large Unicode controls and other small cases
also remain noisy. The complete focused median-regression inventory follows;
paired delta is after minus before and is in ns, including full-output validation:

| Case | Before median | After median | Median ratio | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `start_byte_target1` | 13.9 | 14.0 | 0.986x | 1.941 | 8/9 |
| `start_ascii_target1` | 13.4 | 15.5 | 0.865x | 2.772 | 7/9 |
| `start_noop_empty_empty_padding` | 14.5 | 15.9 | 0.909x | 1.796 | 6/9 |
| `start_noop_tiny_negative` | 36.7 | 37.3 | 0.983x | 2.814 | 6/9 |
| `start_noop_tiny_empty_padding` | 35.7 | 39.9 | 0.893x | -2.344 | 3/9 |
| `start_noop_long_unicode_negative` | 180439.1 | 187069.5 | 0.965x | 12356.273 | 6/9 |
| `start_positive_shorter` | 35.6 | 39.8 | 0.892x | 6.538 | 6/9 |
| `end_ascii_target1` | 11.6 | 13.0 | 0.896x | -0.001 | 4/9 |
| `end_noop_empty_negative` | 12.6 | 14.4 | 0.881x | 0.525 | 6/9 |
| `end_noop_tiny_negative` | 32.0 | 36.8 | 0.868x | 3.173 | 8/9 |
| `end_noop_tiny_empty_padding` | 33.2 | 35.5 | 0.935x | 2.302 | 5/9 |
| `end_noop_long_unicode_negative` | 189066.0 | 201418.1 | 0.939x | 4922.398 | 5/9 |
| `end_noop_long_unicode_empty_padding` | 194687.6 | 218203.6 | 0.892x | 15588.285 | 7/9 |
| `end_positive_shorter` | 34.0 | 34.4 | 0.989x | 0.315 | 5/9 |
| `end_empty_text_unicode_small` | 70.0 | 81.8 | 0.856x | 11.762 | 5/9 |

The variant is **rejected**: large productive wins do not resolve the repeated
common no-op costs. No causal mechanism for those costs is established, and no
additional variant, code-layout investigation, or backend probe was attempted.
[exploratory/runtime.patch](exploratory/runtime.patch) preserves the exact tested
change and [exploratory/source-tests.ms](exploratory/source-tests.ms) its four
functional tests. The runtime is restored to baseline and no active e2e fixture
is retained. The shared identity-file runner extension remains because these
benchmarks use it. There is no runtime-change PR or merge recommendation.
