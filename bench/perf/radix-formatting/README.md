# Rejected integer radix formatting specializations

Measured 2026-10-29. **None of these radix changes is retained.** All three
candidates improved some wide conversions but slowed common short values.
[PR #1959](https://github.com/manuscript-lang/manuscript/pull/1959) records the
unmerged experiment. The evidence branch restores production `num.rs` to main;
rejected code and its differential test are preserved as patches in `variants/`.
These results are a tradeoff, not a claim that generic division is globally
optimal or that all numeric paths have been optimized.

## Candidates and pinned baselines

1. **V1, powers only:** shift/mask extraction for bases 2/4/8/16/32, original
   division loops for other bases. Initial baseline was
   `493c66835d6fd578651799826132f175b54b7e2a`; published prototype
   `ce91970b5a74944abde040a58de4d41c326378c6`. Initial wide gains survived paired
   checks, but integration with main
   `7137182cedbe1fd3f52e4e61d6ccf799e9daa371` exposed common decimal regressions.
2. **V2, decimal plus powers:** add radix-10 early returns through existing
   `push_i64`/`format_u64`, before the large buffers and power predicate. Expanded
   controls found short unsigned and zero regressions. Rejected.
3. **V3, decimal only:** the single predeclared fallback removes both power
   branches and keeps only the decimal returns. It also regressed common paths.
   The stop rule applies: no further radix variants or repeated timing sessions.

V2 and V3 use main713 for their baseline. Their native baseline and frozen
compiler are identical; V3 reuses the exact V2 baseline executable. All production
formatting behavior, signs, zero, lowercase digits, append semantics, allocation
ownership and wrapper validation were intended to remain unchanged. No language
or public API change was proposed.

## Configuration and measurement contract

Linux 6.18.55 x86_64, Intel Xeon Platinum 8573C KVM guest, five visible CPUs,
four-CPU quota (`400000 100000`), 16 GiB. Every producer was pinned to CPU 0.
Rust 1.99.1. Native runtime: `cargo xtask runtime`, Cargo Release optimization
level 3 with debug information overridden to zero. Each generated program used
explicit **`MS_BACKEND=cranelift`**, `--build-type Release`, MIR/backend speed
optimization, the same compiler/workload per pair, and per-build `MS_RT_LIB`.
This is not LLVM-generated-program evidence. LLVM, Windows and macOS performance
were not measured. Full hashes, source identities, environment and dataset
checksums are in [artifacts.json](artifacts.json).

`ns_op` is wall time measured inside the compiled producer, excluding compilation,
Python, process startup, argument parsing and final row formatting. Whole-producer
wall/CPU time is retained separately; CPU includes startup. Inputs vary over a
1,000-value cycle. Every output length contributes to an independently computed
checksum, and final text is checked exactly. Producers exit nonzero on mismatch;
the harness requires successful exit, empty stderr, exact row identity and timing
bounds, and fails on missing samples. This is not a full-text oracle for every
intermediate output. The Rust differential test checks complete formatter bytes.
One-shot results are startup/clock sensitive and support no small-call claim.

All samples, warmups, outliers and rejected variants are retained. Across eight
raw files there are **4,880 successful producer invocations**, comprising
**464 warmups and 4,416 measured invocations**. No failed workload is counted as
fast. The initial disk-full build/validation attempt ran no timing workload;
after removal of the completed first lane's obsolete Cargo incremental cache,
the archive and focused checks were rebuilt successfully before V2 timing.
No runtime archive, source evidence or codegen artifact was removed for recovery.
No allocation counter, instruction count or RSS measurement was made.

## Protocol and all retained data

`repeat.py` runs 18 identities at counts 1 and one million, eight balanced pairs
plus warmup. Initial V1 also has an identical-binary A/A run. `controls.py` uses
12 phases of interleaved candidate/A/A comparisons, rotating case order: small
signed decimal and zero decimal at 10 million, wide base 3/16 at two million.
The integration run used this same fixed protocol after the main Float change.

After integration rejected V1, `final_controls.py` was fixed before V2 timing:
all signed/unsigned small and zero combinations at bases 3/10/36 (five million),
plus wide signed bases 2/16/3/36/10 and unsigned base 10 (one million). Twelve
phases, balanced label order and interleaved A/A comparisons. This is 936
invocations, including 72 warmups. V3 uses the same protocol once. Both V2 and V3
also passed 112 small baseline/candidate output controls before timing.

| Dataset | Variant and purpose | Producer invocations |
| --- | --- | ---: |
| [candidate-pinned](results/candidate-pinned.jsonl) | V1 initial paired matrix | 648 |
| [aa-pinned](results/aa-pinned.jsonl) | V1 identical-binary calibration | 648 |
| [long-controls](results/long-controls.jsonl) | V1 predeclared follow-up | 208 |
| [integration-main713](results/integration-main713-v1-rejected.jsonl) | V1 integrated with main Float change | 208 |
| [v2-pinned](results/v2-pinned.jsonl) | V2 full paired matrix | 648 |
| [v2-controls](results/v2-controls.jsonl) | V2 expanded common controls/A/A | 936 |
| [v3-pinned](results/v3-pinned.jsonl) | V3 full paired matrix | 648 |
| [v3-controls](results/v3-controls.jsonl) | V3 same expanded protocol | 936 |

## Why V1 was rejected

Initial wide power-of-two conversions won all eight pairs. The first small
decimal signal was inconclusive: candidate paired ratio 1.097, identical-binary
ratio 1.091; the first longer control gave candidate 1.014. It was not discarded.
After integration, small decimal slowed 10.7% while A/A stayed flat; zero decimal
also slowed. Hexadecimal gains persisted but could not justify the regression.

Values below are median ns/op [minimum–maximum]. Ratios are medians of matched
within-phase after/before ratios, not ratios of raw medians.

| Operation | Base | Before ns/op | After ns/op | Paired ratio | CPU ratio | A/A ratio | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| signed-small | 10 | 42.83 [39.26–67.01] | 47.42 [43.20–60.79] | 1.107 | 1.108 | 1.001 | 2/12 |
| zero | 10 | 36.20 [31.35–38.59] | 38.30 [34.73–50.74] | 1.075 | 1.076 | 0.960 | 2/12 |
| signed-wide | 3 | 277.11 [260.87–369.64] | 278.29 [261.46–296.58] | 0.983 | 0.988 | 0.996 | 8/12 |
| signed-wide | 16 | 110.34 [105.66–276.18] | 66.52 [54.73–78.70] | 0.550 | 0.557 | 1.011 | 12/12 |

## Why V2 was rejected

Unsigned zero in base 3 slowed 24.9%, compared with 3.1% A/A variation; CPU time
corroborates. Several other short cases also regressed despite wide conversion
gains. All expanded controls are shown, including noisy and favorable cases.

| Operation | Base | Before ns/op | After ns/op | Paired ratio | CPU ratio | A/A ratio | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| signed-small | 3 | 53.37 [44.58–88.81] | 53.05 [47.00–76.04] | 0.936 | 0.939 | 0.980 | 7/12 |
| signed-small | 10 | 43.98 [39.33–138.03] | 42.82 [35.43–86.93] | 0.934 | 0.941 | 0.964 | 7/12 |
| signed-small | 36 | 40.41 [35.87–77.69] | 43.81 [38.71–72.32] | 1.043 | 1.046 | 1.012 | 5/12 |
| unsigned-small | 3 | 48.79 [43.71–96.95] | 50.34 [45.53–104.16] | 1.064 | 1.063 | 1.058 | 4/12 |
| unsigned-small | 10 | 38.75 [36.48–73.57] | 40.30 [37.82–75.08] | 1.046 | 1.045 | 0.979 | 2/12 |
| unsigned-small | 36 | 38.84 [34.83–65.14] | 42.76 [38.51–79.49] | 1.080 | 1.080 | 1.012 | 2/12 |
| zero | 3 | 38.73 [33.55–119.82] | 41.51 [35.74–61.15] | 1.057 | 1.057 | 0.958 | 4/12 |
| zero | 10 | 38.72 [32.44–76.73] | 40.06 [37.22–58.80] | 1.027 | 1.022 | 0.992 | 5/12 |
| zero | 36 | 37.49 [33.13–74.71] | 40.73 [36.49–62.38] | 1.077 | 1.083 | 1.055 | 2/12 |
| unsigned-zero | 3 | 33.88 [30.00–58.05] | 42.05 [37.65–67.70] | 1.249 | 1.249 | 1.031 | 1/12 |
| unsigned-zero | 10 | 35.59 [28.82–52.07] | 39.83 [35.98–49.98] | 1.173 | 1.172 | 0.992 | 4/12 |
| unsigned-zero | 36 | 34.71 [30.51–54.14] | 38.44 [34.47–65.37] | 1.107 | 1.112 | 1.024 | 2/12 |
| signed-wide | 2 | 489.19 [418.53–588.64] | 124.75 [109.66–258.51] | 0.280 | 0.280 | 1.023 | 12/12 |
| signed-wide | 16 | 117.42 [110.24–249.54] | 73.83 [50.81–172.47] | 0.564 | 0.569 | 1.061 | 11/12 |
| signed-wide | 3 | 300.12 [271.32–645.00] | 297.02 [268.95–383.87] | 0.980 | 0.978 | 0.982 | 7/12 |
| signed-wide | 36 | 92.44 [75.11–129.08] | 95.21 [81.28–252.34] | 0.998 | 0.998 | 1.029 | 6/12 |
| signed-wide | 10 | 151.93 [132.24–198.17] | 58.76 [52.53–76.66] | 0.380 | 0.386 | 0.868 | 12/12 |
| unsigned-wide | 10 | 162.00 [136.61–412.22] | 71.54 [55.30–113.46] | 0.423 | 0.426 | 1.023 | 12/12 |

## Why V3 was rejected

The decimal-only fallback still slowed unsigned small decimal by 10.1% versus
flat A/A, unsigned small base 36 by 14.8%, unsigned zero base 3 by 16.6%, and
signed zero base 36 by 16.9%. CPU time corroborates. Wide decimal improved more
than twofold but does not justify these common-path costs. No exact compiler or
layout cause is established; this lane did not inspect backend/codegen internals.

| Operation | Base | Before ns/op | After ns/op | Paired ratio | CPU ratio | A/A ratio | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| signed-small | 3 | 47.81 [44.12–56.81] | 48.86 [43.79–72.52] | 1.051 | 1.048 | 0.970 | 4/12 |
| signed-small | 10 | 39.29 [36.90–87.09] | 39.40 [36.45–525.53] | 0.996 | 0.997 | 1.010 | 6/12 |
| signed-small | 36 | 38.50 [34.11–48.08] | 39.42 [36.28–64.37] | 1.068 | 1.067 | 0.945 | 4/12 |
| unsigned-small | 3 | 46.99 [41.80–280.06] | 48.94 [43.83–393.21] | 1.036 | 1.035 | 1.018 | 2/12 |
| unsigned-small | 10 | 36.66 [33.87–46.32] | 42.06 [38.23–326.73] | 1.101 | 1.102 | 0.990 | 3/12 |
| unsigned-small | 36 | 36.65 [32.50–434.34] | 40.75 [36.98–670.63] | 1.148 | 1.145 | 1.019 | 2/12 |
| zero | 3 | 35.38 [31.90–1024.05] | 35.31 [30.37–1491.18] | 0.971 | 0.971 | 0.991 | 8/12 |
| zero | 10 | 36.07 [32.52–2019.45] | 39.41 [31.33–1260.64] | 1.067 | 1.070 | 1.066 | 5/12 |
| zero | 36 | 33.64 [30.18–535.49] | 39.19 [32.19–610.28] | 1.169 | 1.178 | 1.004 | 1/12 |
| unsigned-zero | 3 | 31.24 [27.66–582.69] | 39.34 [32.52–96.23] | 1.166 | 1.174 | 0.978 | 2/12 |
| unsigned-zero | 10 | 32.47 [28.33–135.45] | 39.09 [33.45–305.42] | 1.160 | 1.158 | 1.038 | 2/12 |
| unsigned-zero | 36 | 33.31 [28.40–93.80] | 35.91 [31.34–45.05] | 1.096 | 1.083 | 0.924 | 2/12 |
| signed-wide | 2 | 440.93 [392.51–4323.59] | 420.19 [393.33–3138.67] | 0.960 | 0.962 | 1.015 | 9/12 |
| signed-wide | 16 | 110.09 [101.40–325.01] | 114.39 [94.84–334.00] | 1.050 | 1.041 | 0.947 | 4/12 |
| signed-wide | 3 | 270.00 [249.17–2439.17] | 269.62 [252.99–14600.25] | 1.012 | 1.013 | 1.019 | 3/12 |
| signed-wide | 36 | 88.66 [74.25–124.02] | 85.51 [71.82–139.18] | 1.001 | 1.018 | 1.023 | 6/12 |
| signed-wide | 10 | 131.82 [119.86–194.84] | 50.72 [47.32–99.73] | 0.385 | 0.388 | 1.018 | 12/12 |
| unsigned-wide | 10 | 141.65 [124.14–204.50] | 63.05 [54.14–85.08] | 0.443 | 0.443 | 0.964 | 12/12 |

## Correctness, checks and reproduction

Independent Sol 6.1 review verified all datasets, phase/order joins, identities,
checksum/final-text oracles, timing bounds and summary calculations, and rejected
all three candidates. The candidate differential test covers 4,296 values across
all 35 bases through both signed and unsigned helpers: 300,720 exact comparisons
plus append-prefix checks. Public-method source checks passed Debug and explicit
Cranelift Release, including signed minimum and high unsigned decimal bits.

Focused numeric tests, formatting, workspace Clippy and repository checks passed
for V2 and V3. The initial V1 full workspace run had 1,227 tests run: 1,223 passed,
four failed and one configured skip. Three were the previously observed missing
LLVM debug-consumer checks; the additional parser/formatter mutation failure in
`sort-with-capturing-comparator.ms` was not baseline-qualified or individually
retried. Workspace doc tests passed. Rebased V1 strict conformance passed
2,393/2,393 (1,603 check, 531 run, 259 test). These are not claims that a final
radix fix passed full checks or was merged: there is no retained radix fix.

To reproduce a rejected integrated variant, create two worktrees at main713,
apply its `variants/*.patch` to only the candidate, build both native archives,
and use one compiler with the matching workload for both. V1 used
`variants/v1-main.ms`; V2/V3 use `main.ms`. For the original pre-integration V1
snapshot, use commit `ce91970b5` and its parent baseline. Compiler/source/archive
hashes identify the measured snapshots; different build paths need not reproduce
byte-identical binaries.

```sh
git worktree add /tmp/radix-before 7137182cedbe1fd3f52e4e61d6ccf799e9daa371
git worktree add /tmp/radix-after 7137182cedbe1fd3f52e4e61d6ccf799e9daa371
(cd /tmp/radix-after && git apply /absolute/path/to/variants/v3-decimal-only.patch)
(cd /tmp/radix-before && cargo xtask runtime)
(cd /tmp/radix-after && cargo xtask runtime)
MS_BACKEND=cranelift MS_RT_LIB=/tmp/radix-before/target/ms-native/libms_native.a \
  /path/to/ms build /absolute/path/to/main.ms --build-type Release -o /tmp/radix-before-program
MS_BACKEND=cranelift MS_RT_LIB=/tmp/radix-after/target/ms-native/libms_native.a \
  /path/to/ms build /absolute/path/to/main.ms --build-type Release -o /tmp/radix-after-program
python3 repeat.py /tmp/radix-before-program /tmp/radix-after-program --cpu 0 > /tmp/paired.jsonl
python3 final_controls.py /tmp/radix-before-program /tmp/radix-after-program --cpu 0 > /tmp/controls.jsonl
```

Use `controls.py` for V1's four-identity protocol. Python 3.11+ and Linux/POSIX
resource and affinity APIs are required. Select an available CPU when CPU 0 is
unavailable. Finish builds and other CPU-heavy checks before measuring.
