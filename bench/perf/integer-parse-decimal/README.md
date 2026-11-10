# Decimal Optional parsing

## 2026-11-10: rejected significant-digit bound (#3357)

**The candidate is rejected. Production parsing is unchanged and #3357 remains open.**

`String.parse_int()` used a short byte parser through 18 digits, then validated
UTF-8 over the entire input before calling the standard integer parser. This
made an immediately invalid or overflowing prefix scan an irrelevant suffix.
The [candidate](variants/bounded-decimal.patch) applied a significant-digit bound
above 19 digits: skip leading ASCII zeros, bound the remaining part, then use safe
standard parsing plus a checked signed conversion. Its semantic tests passed,
but it regressed short early-invalid input in a longer confirmation. The source
implementation was restored; no further candidates or cause investigation followed.

This Optional method can reject either malformed or overflowing data as `none`.
The Result parser `math.parse_int` must retain full syntax validation because it
reports a malformed suffix as EBADMSG even after a numerically overflowing prefix.
The rejected candidate preserved public syntax, numeric results, error contracts
and unlimited leading zeros; those properties did not establish a performance pass.

The neighboring baseline operation is `string.parse_int` in the latest dated
[stdlib baseline](../baseline-2026-10-28.md). Its archived 8.69 ns/op is from a
different machine; compare the paired measurements here, not those absolute times.

### Protocol

The same compiler built at main `3107528e8` compiles the same [producer](main.ms)
in LLVM Release mode against the original and candidate native archives, selected
with `MS_RT_LIB`. An identical copy of the original executable is the A/A control.
[repeat.py](repeat.py) pins producers to one CPU and runs 12 phases, rotating and
reversing binary order so all three positions and pair orders balance. Each case
has an untimed warmup and tiny-output control. The first run used only 5,000
iterations for the two-byte early-invalid case; the confirmation increased that
and the shortest overflow case to 2,000,000 iterations per sample. No build or test runs during timing.
Every timed parse is checked against its complete expected Optional value; its
residue contributes to a checked checksum. The formatting control checks every
complete radix string. Construction, startup, compilation and printing are outside
the internal timer. Raw page faults describe the whole producer, including setup.
No instruction counts were collected; the environment lacked perf/callgrind tools.

Linux x86_64, AMD EPYC 9V74, four-core CPU quota, 16 GiB memory limit; Rust 1.99.1
(`58cf8f9c3`), LLVM 23.1.1. Shared-host noise remains in every sample.

Build the baseline compiler and save its native archive. In an isolated worktree,
apply `variants/bounded-decimal.patch` with `git apply` and build the candidate
archive with `cargo xtask runtime`. Use that same baseline compiler for both
producers; the archived patch adds only the candidate runtime path, since the
semantic tests are already retained in this evidence change:

```sh
MS=/path/to/baseline/ms
MS_RT_LIB=/path/to/original.a "$MS" build bench/perf/integer-parse-decimal/main.ms --build-type Release -o /tmp/decimal-before
MS_RT_LIB="$PWD/target/ms-native/libms_native.a" "$MS" build bench/perf/integer-parse-decimal/main.ms --build-type Release -o /tmp/decimal-after
cp /tmp/decimal-before /tmp/decimal-aa
python3 bench/perf/integer-parse-decimal/repeat.py /tmp/decimal-before /tmp/decimal-aa /tmp/decimal-after > samples.jsonl
```

### Results

The confirmation uses all 12 phases with no outlier removal. Values are median
internal ns/op; ratios are medians of within-phase candidate/baseline and A/A
ratios. The identical binary A/A control varied materially for the largest
buffers, so their absolute medians do not establish a precise speedup.

| Case | Baseline | Candidate | Ratio | A/A |
| --- | ---: | ---: | ---: | ---: |
| format | 66.75 | 67.74 | 1.0049 | 1.0001 |
| plain | 8.19 | 8.32 | 1.0152 | 1.0054 |
| max | 22.26 | 22.40 | 1.0025 | 1.0000 |
| min | 22.74 | 23.08 | 1.0095 | 1.0106 |
| overflow19 | 21.72 | 22.34 | 1.0274 | 1.0006 |
| invalid19 | 8.82 | 7.80 | 0.8968 | 0.9848 |
| zero, 19 zero bytes | 23.48 | 17.68 | 0.7466 | 0.9994 |
| zero, 4,096 zero bytes | 4679.44 | 1231.65 | 0.2633 | 1.0002 |
| late, 4,096 zero bytes | 4690.34 | 1246.76 | 0.2643 | 1.0022 |
| early, 1 zero bytes | 3.92 | 4.25 | 1.0762 | 1.0045 |
| early, 1,000 zero bytes | 26.59 | 4.11 | 0.1544 | 0.9995 |
| early, 100,000 zero bytes | 2213.62 | 4.10 | 0.0019 | 0.9948 |
| early, 1,000,000 zero bytes | 18665.42 | 4.10 | 0.0002 | 1.0102 |
| overflow, 1 zero bytes | 21.78 | 4.23 | 0.1942 | 0.9948 |
| overflow, 1,000 zero bytes | 39.21 | 4.10 | 0.1047 | 0.9986 |
| overflow, 100,000 zero bytes | 2109.10 | 4.23 | 0.0020 | 1.0336 |
| overflow, 1,000,000 zero bytes | 20647.54 | 4.11 | 0.0002 | 0.9777 |

The latest dated baseline's exact `strings_bench.ms::string.parse_int` case was
rerun with both archives in four phases, alternating order, seven 100 ms samples
per invocation. The median of per-invocation medians was 5.61 ns/op
before and 5.88 ns/op for the candidate (paired ratio 1.0500).
This independent ordinary-input control also regressed.

For each runtime archive, the exact control command was:

```sh
MS_RT_LIB=/path/to/archive.a "$MS" bench bench/perf/stdlib/strings_bench.ms --filter string.parse_int --time 100ms --samples 7 --json
```

Run baseline then candidate in phases 0 and 2, reversing them in phases 1 and 3.

Short early-invalid parsing regressed about 7.6% in the longer confirmation while
its A/A control stayed near 1.0. Ordinary 19-digit overflow also slowed about
2.7%. The reason for these small-input regressions is unestablished; the large
suffix improvement does not justify merging them. No backend, disassembly,
ownership, or lifetime investigation was performed.

The new unit test `decimal_parsing_with_long_leading_zeros_matches_standard_parser`
and called source test in `integer-radix.ms` retain semantic controls for future
work; they also pass against the original implementation.

Raw evidence: [initial samples](samples-2026-11-10.jsonl),
[longer confirmation](confirmation-2026-11-10.jsonl), and
[dated-baseline control](stdlib-samples-2026-11-10.jsonl). Whole-producer major page
faults were zero throughout; minor faults include construction and startup and
are not a parsing allocation measurement.
