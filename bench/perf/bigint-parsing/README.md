# Reuse owned digit scratch in BigInt parsing

Measured 2026-10-29 against main
`db975ce2f01ddf8da108ec9045ecaf66a63ab22c`. The private parser already owns a
validated vector of digit values. Pinned `num-bigint` 0.5.1's big-endian
constructor makes another vector and reverses it for power-of-two bases.
Reverse the owned vector in place and use the little-endian constructor for
bases 2/4/8/16/32. This removes one temporary digit-vector allocation/copy while
calling the same packing algorithm. Other bases keep the big-endian constructor.
No library upgrade, public API, digit/limit validation, sign or error-order change.

The larger-batch control supports retention for the measured **tiny power-base
parsing workloads**: approximately 14–20% paired wall/CPU improvement, with A/A
controls near flat. It does not establish every path as unchanged or faster,
isolated parser latency, or universal large-input gains.

## Configuration and provenance

Linux 6.18.55 x86_64, Intel Xeon Platinum 8573C KVM guest, five visible CPUs,
four-CPU quota (`400000 100000`), 16 GiB memory. Every producer pinned to CPU 0.
Rust 1.99.1; native runtime built by `cargo xtask runtime` with Cargo Release,
optimization level 3 and debug information overridden to zero. Both programs
used the same baseline-built release compiler and workload, explicit
**`MS_BACKEND=cranelift`**, `--build-type Release`, MIR/backend speed optimization,
and `MS_RT_LIB` to select preserved before/after native archives. This is not
LLVM-generated-program evidence. [artifacts.json](artifacts.json) records exact
compiler, archive, executable, source, harness and dataset hashes.

The dependency source inspected was pinned `num-bigint-0.5.1/src/biguint/convert.rs`:
`from_radix_be` uses `Vec::from(buf)` and reverses it for power bases;
`from_radix_le` validates and packs that already-reversed order without cloning.
Generic conversion remains `from_radix_be`. No allocation counter or RSS
measurement was made; the eliminated temporary is established from source.

## Workload and correctness contract

Four prebuilt inputs cycle through every producer. Classes are: tiny signed/zero
spellings; 4,096 dense valid digits; 4,032 leading zeros followed by 64 significant
digits; 4,096 zeros. Signs and letter case vary. Bases 2/4/8/16/32 are affected;
3/10/36 are generic controls. Input strings are copied once before timing.

Before the clock, four reference values are parsed and their complete canonical
text is checked against Python's independent normalization of the known-valid
spellings (case, leading zeros, signs and negative zero). Every timed parsed
value is compared fully with its checked reference; a mismatch exits nonzero.
Weighted signs contribute to a separately checked checksum. Final canonical
formatting and output happen outside the timer. Thus `ns_op` measures the
**parse + comparison + sign/checksum loop and normal result handling**, not
an isolated parser call. The arithmetic-fold Rust oracle independently checks
numeric values, avoiding a parser-versus-itself correctness claim.

The harness requires successful producer exit, empty stderr, exact identity and
output, complete phase joins and timing bounds. It validates the entire final
canonical output before recording its SHA-256/length, avoiding repeated 4 KiB
strings in raw data. Per-producer Unix start/end timestamps are outside internal
timing. Whole-producer CPU/wall times include startup/reference construction and
formatting; `ns_op` excludes startup, Python, compilation and final formatting.
One-shot cases are retained but justify no single-call performance claim.

## Fixed protocols and qualification

The main paired matrix is 32 identities at counts 1 and a batch of 200,000 tiny
or 4,096 long parses, eight balanced pairs plus warmup: 1,152 invocations.
The first interleaved candidate/A/A control has eight rotating identities,
eight phases plus warmup: 288 invocations. Short batches showed enough A/A
variation to prevent retention from those results alone.

One larger follow-up was fixed before running: tiny inputs in all eight bases
at five million parses, dense 8/16/32 and generic leading-zero base 3 at 65,536;
12 balanced rotating phases with interleaved candidate/A/A comparisons. It has
624 invocations, including 48 warmups. No further variant or timing session was
used to obtain the retention decision.

Primary evidence totals **2,064 successful invocations**, including **208 warmups
and 1,856 measured invocations**, across three files. All outliers are retained.
The clean producer window was 18:29:40–18:30:31 UTC and the larger session
18:37:42–18:44:01 UTC. Independent Sol 6.1 review verified all identities, oracles,
phase/order joins, timestamps, timing bounds and statistics.

An earlier complete pair of files (1,440 successful invocations) remains archived
as **transport-uncertain**. Its creation/completion window, 18:23:53–18:24:44,
could not be confidently separated from an 18:23 transport-disconnect notification.
It supports no retention claim. After confirming the same environment was healthy,
the complete protocol ran once using unchanged compiled artifacts and added
outside-timer timestamps; no rebuild or interrupted workload is credited as fast.

| File | Qualification | Invocations |
| --- | --- | ---: |
| [paired](results/paired.jsonl) | Primary full matrix | 1,152 |
| [controls](results/controls.jsonl) | Primary short controls/A/A | 288 |
| [long-controls](results/long-controls.jsonl) | Primary predeclared larger batches | 624 |
| [transport-uncertain-paired](results/transport-uncertain-paired.jsonl) | Excluded from retention | 1,152 |
| [transport-uncertain-controls](results/transport-uncertain-controls.jsonl) | Excluded from retention | 288 |

## Larger-batch results

Values are median ns/iteration [minimum–maximum]. Ratios are medians of matched
within-phase after/before ratios, not ratios of raw medians. CPU ratios use
whole-producer CPU time. A/A always uses the identical baseline executable.

| Class | Base | Before | After | Paired ratio | CPU ratio | A/A ratio | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| tiny | 2 | 94.51 [90.38–137.66] | 77.58 [74.93–162.61] | 0.842 | 0.842 | 1.001 | 10/12 |
| tiny | 4 | 93.15 [88.38–214.98] | 78.90 [74.15–174.89] | 0.828 | 0.829 | 1.012 | 12/12 |
| tiny | 8 | 86.82 [84.20–192.15] | 76.69 [72.17–150.02] | 0.861 | 0.861 | 1.004 | 11/12 |
| tiny | 16 | 97.12 [90.84–283.46] | 81.79 [78.61–88.11] | 0.847 | 0.848 | 1.000 | 12/12 |
| tiny | 32 | 94.78 [88.06–108.91] | 76.21 [74.26–90.86] | 0.799 | 0.799 | 0.999 | 11/12 |
| tiny | 3 | 75.28 [70.87–92.95] | 75.70 [73.58–204.18] | 1.003 | 1.003 | 1.025 | 6/12 |
| tiny | 10 | 75.67 [71.80–123.62] | 77.78 [74.64–105.16] | 1.038 | 1.038 | 1.017 | 5/12 |
| tiny | 36 | 78.19 [73.55–121.74] | 75.85 [73.96–95.93] | 0.957 | 0.959 | 0.986 | 8/12 |
| dense | 8 | 12339.24 [12025.99–21324.40] | 12050.70 [11702.45–13774.98] | 0.953 | 0.953 | 0.984 | 11/12 |
| dense | 16 | 13241.10 [12487.19–28322.73] | 12573.34 [11943.74–25443.15] | 0.944 | 0.944 | 0.968 | 10/12 |
| dense | 32 | 15366.38 [14499.10–17658.49] | 15233.35 [14219.06–20218.92] | 1.004 | 1.004 | 1.000 | 6/12 |
| leading-zero | 3 | 10084.49 [9673.07–10933.87] | 10012.36 [9575.79–10724.09] | 1.003 | 1.003 | 1.002 | 6/12 |

Tiny affected bases improve in 10/12 to 12/12 pairs with matching CPU gains.
Decimal remains uncertain: raw medians **75.67 → 77.78 ns**, paired wall/CPU
**1.038/1.038**, five of 12 faster pairs, A/A **1.017**. Decimal equivalence or an
all-path no-regression claim is not established. Dense base 32 is effectively
flat; dense 8/16 gains are smaller. Retention rests on reproducible tiny power-base
gains and the removed temporary copy, with these limits preserved.

## Original clean batch distributions

All 32 batched identities, including unfavorable/noisy cases, are shown. These
shorter batches alone were insufficient for the retention decision.

| Class | Base | Before ns/iteration | After | Paired ratio | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| tiny | 2 | 91.63 [81.07–110.31] | 75.19 [71.40–90.08] | 0.868 | 8/8 |
| dense | 2 | 9877.43 [9087.30–10949.93] | 9792.75 [8434.41–10899.06] | 1.009 | 4/8 |
| leading-zero | 2 | 10086.07 [9594.18–10571.65] | 9621.27 [8681.68–10930.32] | 0.959 | 6/8 |
| zero | 2 | 10170.49 [9211.54–11134.13] | 9942.17 [8849.00–10530.59] | 0.984 | 5/8 |
| tiny | 4 | 88.58 [81.28–119.77] | 77.38 [70.17–91.91] | 0.860 | 6/8 |
| dense | 4 | 9363.50 [8945.46–11546.59] | 9737.43 [8733.21–10269.67] | 1.033 | 3/8 |
| leading-zero | 4 | 9605.18 [8985.86–11330.84] | 9913.62 [9003.24–10486.54] | 1.008 | 3/8 |
| zero | 4 | 9581.69 [9180.72–10253.36] | 9287.65 [8649.32–11979.30] | 0.956 | 5/8 |
| tiny | 8 | 86.20 [73.77–100.35] | 71.15 [63.27–75.34] | 0.796 | 8/8 |
| dense | 8 | 11646.55 [11294.01–13311.51] | 11800.94 [11064.53–14102.50] | 1.027 | 3/8 |
| leading-zero | 8 | 12340.69 [11012.85–14459.53] | 11918.67 [11441.12–13901.56] | 0.994 | 4/8 |
| zero | 8 | 12931.32 [11084.92–19575.58] | 12961.44 [10757.42–19249.81] | 0.979 | 5/8 |
| tiny | 16 | 90.90 [83.71–105.34] | 83.53 [69.52–93.33] | 0.885 | 6/8 |
| dense | 16 | 12357.86 [11384.55–17705.98] | 11849.68 [11505.71–13599.58] | 1.013 | 3/8 |
| leading-zero | 16 | 9955.24 [9098.34–11969.19] | 9580.88 [8570.62–13467.00] | 0.974 | 5/8 |
| zero | 16 | 10218.46 [9160.27–15585.52] | 10103.45 [8602.95–13535.38] | 1.032 | 4/8 |
| tiny | 32 | 93.09 [83.94–108.37] | 76.39 [71.68–98.51] | 0.867 | 7/8 |
| dense | 32 | 15806.62 [13905.39–23077.47] | 16149.86 [14929.75–18999.69] | 1.030 | 3/8 |
| leading-zero | 32 | 12926.17 [11806.00–14169.90] | 12722.39 [11689.84–14226.39] | 0.971 | 5/8 |
| zero | 32 | 12363.47 [11392.83–13538.17] | 11626.76 [11108.91–12876.38] | 0.955 | 5/8 |
| tiny | 3 | 71.65 [67.89–82.03] | 70.49 [65.59–78.15] | 1.024 | 3/8 |
| dense | 3 | 17479.73 [15552.13–18947.39] | 16686.16 [15597.39–20179.14] | 0.965 | 5/8 |
| leading-zero | 3 | 9448.71 [8928.37–11010.68] | 10121.70 [9035.31–12491.55] | 1.057 | 2/8 |
| zero | 3 | 10017.91 [9087.49–12670.22] | 9774.24 [8447.81–11072.05] | 0.949 | 5/8 |
| tiny | 10 | 71.65 [63.42–93.80] | 72.87 [64.57–81.80] | 0.975 | 5/8 |
| dense | 10 | 34384.11 [32039.26–40416.46] | 33802.77 [32367.36–43431.94] | 0.971 | 5/8 |
| leading-zero | 10 | 10894.50 [9590.88–12034.22] | 10614.98 [9731.68–13909.89] | 0.986 | 5/8 |
| zero | 10 | 9779.55 [8976.35–11658.77] | 9911.70 [8575.64–10822.10] | 0.989 | 4/8 |
| tiny | 36 | 79.65 [66.51–95.58] | 80.40 [70.42–101.11] | 1.045 | 1/8 |
| dense | 36 | 72386.99 [69377.53–76747.09] | 68971.93 [68014.06–84422.64] | 0.984 | 5/8 |
| leading-zero | 36 | 10071.51 [9268.62–11245.43] | 10282.98 [8819.87–11917.90] | 0.984 | 4/8 |
| zero | 36 | 9007.34 [8554.82–9897.11] | 9131.48 [8081.28–10772.06] | 1.014 | 4/8 |

## Functional checks and reproduction

The arithmetic-fold regression checks **21,840 generated spelling cases** across
all 35 supported bases, 26 digit lengths, signs, case and leading zeros, including
the first 64-bit packing boundary for each power base. These are generated cases,
not necessarily distinct strings. Each is checked with omitted/exact/one-short
limits. Additional malformed/non-ASCII/invalid-argument cases preserve strict
validation and limit-before-data error precedence.

Six BigInt crate tests passed. Five public source tests passed Debug and explicit
Cranelift Release, including all five power bases, negative zero, case, leading
zeros and strict digit limits. Formatting, workspace Clippy and repository checks
passed. Full workspace/conformance and final CI results are recorded in the PR;
these focused checks are not a claim that all full gates already passed.

Create baseline and candidate worktrees, build their native archives, and use
one compiler/workload for both standalone programs. For example:

```sh
git worktree add /tmp/bigint-before db975ce2f01ddf8da108ec9045ecaf66a63ab22c
(cd /tmp/bigint-before && cargo xtask runtime)
cargo xtask runtime
cargo build --release --locked -p ms-cli
MS_BACKEND=cranelift MS_RT_LIB=/tmp/bigint-before/target/ms-native/libms_native.a \
  target/release/ms build bench/perf/bigint-parsing/main.ms --build-type Release -o /tmp/bigint-before-program
MS_BACKEND=cranelift MS_RT_LIB="$PWD/target/ms-native/libms_native.a" \
  target/release/ms build bench/perf/bigint-parsing/main.ms --build-type Release -o /tmp/bigint-after-program
python3 bench/perf/bigint-parsing/repeat.py /tmp/bigint-before-program /tmp/bigint-after-program --cpu 0 > /tmp/paired.jsonl
python3 bench/perf/bigint-parsing/controls.py /tmp/bigint-before-program /tmp/bigint-after-program --cpu 0 > /tmp/controls.jsonl
python3 bench/perf/bigint-parsing/long_controls.py /tmp/bigint-before-program /tmp/bigint-after-program --cpu 0 > /tmp/long-controls.jsonl
```

Python 3.11+ and Linux/POSIX affinity/resource APIs are required. Select an
available CPU if CPU 0 is unavailable. Finish builds and other CPU-heavy checks
before measuring. No LLVM-generated-program or Windows/macOS performance claim,
allocation/RSS measurement, or globally fastest-program claim is made.
