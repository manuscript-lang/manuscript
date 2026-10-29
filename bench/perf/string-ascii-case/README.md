# ASCII case conversion construction

Rejected candidate: the focused run reproduced material empty-input overhead.
No runtime change or active e2e fixture is retained; the runtime is restored
to baseline and the patch/test source are archived in `exploratory/`.
The baseline is `1461546c8` on `perf/string-split-limits` (the same production
runtime as `d564eb3c3`). Public String signatures and Unicode rules stay unchanged.

## Source change and safety argument

The original ASCII path creates a Rust `Vec`, maps it in place, then copies it
again through `from_buf`/`from_bytes`. The rejected patch makes private `map_case` return `StrVal`.
It performs the same single `is_ascii` check and constructs an ASCII result
without that temporary vector:

- Up to `STR_INLINE_MAX`, copy into a fixed stack buffer, map its initialized
  prefix, then call existing `from_bytes`. Empty and one-byte ASCII results
  therefore still use the existing shared cache. The buffer is no longer
  mutated after passing its bytes to the copying constructor.
- For longer ASCII input, existing `heap_copy` allocates and initializes a fresh
  result. Map only its `text.len()` initialized bytes in place. No input bytes,
  `from_bytes` result, static cache, or trailing NUL is mutated.

The existing fresh-result constructor establishes the writable buffer; no Vec
ownership is adopted, and no allocator, tag, release, lifetime, or cleanup
machinery changes. The normal long-result limit check remains in that existing
constructor. ASCII mapping preserves byte count, scalar count, and embedded NUL.

Non-ASCII input retains the existing `from_utf8` expectation, whole-string Rust
`to_uppercase`/`to_lowercase`, `into_bytes`, and `from_buf` path. This preserves
malformed-input behavior, expansions, and contextual final sigma. The private
return-type change is covered by the exported wrappers and the existing sigma
test, which now uses the existing exported lower/`ret` test style. Two direct
unit cases preserve the malformed-UTF8 expectation without new runtime guards.

Doing nothing remains preferable if functional validation fails, constructor
contracts do not suffice, or the full matrix shows material Unicode/common-input
regressions. Removing a vector and copy predicts a reduction in unobservable
work; it does not establish an end-to-end performance gain. No code placement,
backend, or ownership investigation is part of this candidate.

## Prepared coverage and identities

The 80 cases cover upper/lower conversion for mixed ASCII, already-cased input,
and controls/punctuation/NUL at 0, 1, 2, 15, 16, 17, 31, 32, 128, 4096, and
1048576 bytes. Unicode controls include `ß`, `İ`, final/medial Greek sigma,
case-ignorable marks and formatting, and a 1 MiB ASCII prefix followed by Unicode.
That last control keeps long non-ASCII fallback costs visible.

Expected output comes from independent hand-written patterns/literals, including
Unicode results; no case-conversion operation generates an expected value.
Every timed conversion compares its complete output against the expected text,
then returns its byte count plus 17. Expected input/output construction and a
checked per-case warm-up occur outside timing. Conversion, validation, and result
release are included. Compilation, process startup, and output are excluded.

`identities.json` fixes every name, input byte count, iteration count, and total
checksum. Iterations are bounded: 100000 up to 128 bytes and for short Unicode,
4096 at 4 KiB, and 16 at 1 MiB. The existing strict shared runner rejects failed
producers and missing, duplicate, unknown, or changed identities before reporting.
The source tests are `exploratory/case-tests.ms`; they also
check that the original mixed-case input stays unchanged.

## Reproduce the archived candidate after a coordinated window

Do not build or measure while another coordinated corpus or timing job runs.
Build baseline and candidate native archives from this same worktree path,
saving the current source and restoring it through an exit trap on failure.
Build baseline with committed `1461546c8`, then apply `exploratory/runtime.patch`
and build
again with `cargo xtask runtime`. Preserve both archives and `ms_rt_hot.ll`, and
require identical pure-helper IR. Use the same pinned compiler for both programs:

```sh
MS_RT_LIB=/tmp/ascii-case-before/libms_native.a /path/to/pinned-ms build \
    bench/perf/string-ascii-case/main.ms --build-type Release \
    -o /tmp/ascii-case-before-program
MS_RT_LIB=/tmp/ascii-case-after/libms_native.a /path/to/pinned-ms build \
    bench/perf/string-ascii-case/main.ms --build-type Release \
    -o /tmp/ascii-case-after-program
MS_RT_LIB=/tmp/ascii-case-after/libms_native.a /path/to/pinned-ms test \
    bench/perf/string-ascii-case/exploratory/case-tests.ms
cargo nextest run -p ms-rt -E 'test(string::tests::)'
```

Only after a separately coordinated timing window:

```sh
taskset -c 0 python3 bench/perf/string-lines/compare.py \
    /tmp/ascii-case-before-program /tmp/ascii-case-after-program \
    /tmp/ascii-case-samples.csv --pairs 7 \
    --identity-file bench/perf/string-ascii-case/identities.json
```

Record revision, source/patch/compiler/archive/helper/program hashes, machine,
actual Release backend, all raw samples, before/after ranges, and paired signs.
Keep every control and preserve a rejected patch if it regresses materially.
Before native work, static frontend checks and `cargo fmt --all --check` passed;
native checks and recorded comparisons are reported below.

## Recorded Linux comparison, 2026-10-29

Intel Xeon Platinum 8573C VM, five exposed CPUs, Linux 6.18.55, Rust 1.99.1,
static musl native runtime. Both archives were built from this same worktree path,
first at committed `1461546c8`, then with the saved candidate restored using an
exit trap. Baseline archive SHA-256 is
`182d498c374a572a420c0fcc7a93758d2a9c964e7c66bd3e7d795daaaad40112`;
candidate is `6bc4d67f0a58b79b8ebf97fd5cfe419eaec809ec86994a3f9a43cedc3819eb24`.
Both `ms_rt_hot.ll` files are byte-identical, SHA-256
`8315efc0c1ae0b87ff80185ee282e4ede97e82afa6ecfe1825fe296549bc46ef`.
The unchanged compiler SHA-256 is
`3179dc962e37f64961fc16715e7dcc758b78decffb84c2e67100acb0cb044145`.
Normal Release builds explicitly selected the cached LLVM tool directory;
no new backend/codegen inspection was performed.

[builds.json](builds.json) records source/patch/compiler/archive/helper/program,
benchmark, identity, raw-data, and test-log hashes. Both native source tests passed
in explicit Release and Debug profiles. All 22 string unit tests passed, including
both malformed-UTF8 cases. Frontend checks, Rust formatting, and whitespace checks
passed. No workspace-wide or corpus pass is claimed for this rejected candidate.

The full 80-case matrix ran for seven alternating pairs on CPU 0 without other
builds, tests, or timed work. All checked warm-ups, exact-output validations,
producer checks, and strict identities passed. [samples.csv](samples.csv) retains
all 1,120 raw rows; [summary.csv](summary.csv) retains every before/after median
and min/max range; [paired.csv](paired.csv) retains every paired sign and ratio.

All 60 nonempty ASCII medians improved (1.05–2.51x), including already-cased and
control/NUL inputs. This did not establish a safe overall win: five of six empty
medians regressed, and the original Unicode matrix also showed regressions.
Every original median regression follows, in nanoseconds per operation including
exact-output validation:

| Case | Before median | After median | Speedup | Slower pairs |
| --- | ---: | ---: | ---: | ---: |
| `upper_mixed_n0` | 14.9 | 19.5 | 0.764x | 5/7 |
| `lower_mixed_n0` | 13.4 | 18.3 | 0.735x | 7/7 |
| `lower_already_n0` | 13.0 | 17.2 | 0.755x | 6/7 |
| `upper_controls_n0` | 13.9 | 15.1 | 0.920x | 4/7 |
| `lower_controls_n0` | 11.3 | 22.3 | 0.507x | 6/7 |
| `lower_sharp_s` | 68.1 | 71.5 | 0.953x | 6/7 |
| `upper_turkish_i` | 65.6 | 69.1 | 0.950x | 4/7 |
| `upper_final_sigma` | 95.5 | 108.4 | 0.881x | 5/7 |
| `lower_final_sigma` | 92.0 | 97.2 | 0.946x | 4/7 |
| `upper_medial_sigma` | 119.1 | 134.8 | 0.883x | 5/7 |
| `lower_medial_sigma` | 152.7 | 157.3 | 0.971x | 5/7 |
| `upper_sigma_mark` | 97.5 | 103.0 | 0.946x | 4/7 |
| `lower_sigma_mark` | 71.7 | 78.8 | 0.910x | 5/7 |
| `lower_sigma_format` | 119.4 | 123.8 | 0.965x | 4/7 |
| `upper_long_prefix_unicode` | 326995.0 | 394058.8 | 0.830x | 5/7 |
| `lower_long_prefix_unicode` | 428251.1 | 490836.1 | 0.872x | 5/7 |

## Focused longer control run and rejection

A single bounded follow-up retained the exact runtime patch and all six empty
plus all 14 Unicode cases, using 1,000,000 short-case iterations and 128 long-prefix
iterations, with nine alternating CPU 0 pairs. Expected output and all producer
checks remained exact. [focused-controls.ms](focused-controls.ms) and
[focused-identities.json](focused-identities.json) preserve the program/inventory;
[focused-samples.csv](focused-samples.csv) retains all 360 raw rows;
[focused-summary.csv](focused-summary.csv) retains every range; and
[focused-paired.csv](focused-paired.csv) retains every paired sign/ratio.
These separate focused processes omit the full matrix's preceding nonempty ASCII
allocations; the original evidence is retained rather than replaced.

All six empty medians regressed by 2.7–10.2 ns, with six to eight of nine slower
pairs. The Unicode results mostly reversed, so the original Unicode regressions
are **not** claimed as stable. The complete focused matrix follows:

| Case | Before median ns | After median ns | Speedup | Slower pairs |
| --- | ---: | ---: | ---: | ---: |
| `upper_mixed_n0` | 14.1 | 16.8 | 0.839x | 6/9 |
| `lower_mixed_n0` | 14.2 | 20.6 | 0.688x | 7/9 |
| `upper_already_n0` | 12.4 | 19.6 | 0.631x | 6/9 |
| `lower_already_n0` | 13.6 | 23.8 | 0.571x | 7/9 |
| `upper_controls_n0` | 12.6 | 20.2 | 0.621x | 7/9 |
| `lower_controls_n0` | 13.2 | 18.0 | 0.731x | 8/9 |
| `upper_sharp_s` | 108.9 | 100.6 | 1.082x | 1/9 |
| `lower_sharp_s` | 94.5 | 83.2 | 1.135x | 5/9 |
| `upper_turkish_i` | 82.4 | 70.1 | 1.176x | 2/9 |
| `lower_turkish_i` | 108.1 | 94.1 | 1.149x | 3/9 |
| `upper_final_sigma` | 102.6 | 97.8 | 1.048x | 4/9 |
| `lower_final_sigma` | 100.7 | 93.8 | 1.074x | 2/9 |
| `upper_medial_sigma` | 152.9 | 150.9 | 1.013x | 5/9 |
| `lower_medial_sigma` | 156.9 | 168.5 | 0.931x | 5/9 |
| `upper_sigma_mark` | 101.7 | 98.3 | 1.035x | 3/9 |
| `lower_sigma_mark` | 85.3 | 86.7 | 0.983x | 3/9 |
| `upper_sigma_format` | 108.2 | 105.1 | 1.029x | 4/9 |
| `lower_sigma_format` | 132.2 | 124.4 | 1.063x | 5/9 |
| `upper_long_prefix_unicode` | 429955.9 | 354300.5 | 1.214x | 4/9 |
| `lower_long_prefix_unicode` | 588242.7 | 478683.1 | 1.229x | 3/9 |

The candidate is **rejected** because the empty-input regression reproduced.
The proposed construction improvement does remove a temporary allocation/copy
for nonempty ASCII, but its common empty-input cost remains unresolved. No further
variant or code-layout investigation was attempted. The patch and functional
test source remain in [exploratory/runtime.patch](exploratory/runtime.patch) and
[exploratory/case-tests.ms](exploratory/case-tests.ms); no active fixture or runtime
change is included in this evidence-only branch. This branch inherits the held,
unmerged split-limit baseline solely to reproduce the experiment; it must not
be merged as a runtime fix. There is no publication or merge recommendation.
