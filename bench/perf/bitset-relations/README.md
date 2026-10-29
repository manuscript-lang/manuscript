# BitSet relation checks without temporary algebra results

Baseline: `4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`, measured 2026-10-29 on Linux 6.18.55 x86_64, Intel Xeon Platinum 8573C,5 allowed CPUs; timing processes pinned to CPU 0. The generated inventories both report **Cranelift, Release**. The runtime archive uses Cargo release defaults (`cargo xtask runtime`, musl target, native debug=0); Rust 1.99.1. See environment.json for hashes and selected build overrides. No compiler/backend code or settings changed. Other platforms were not measured.

`is_subset_of`, `is_superset_of`, and `is_disjoint_from` formerly constructed a complete difference/intersection and then tested whether it was empty. They now compare words directly, with early exit for a decisive word. Subset treats missing right words as zero; disjoint only visits the overlapping length. No result bitmap is built. Algebra outputs and input word arrays retain their original representation; arbitrary exposed words and trailing zeros remain valid inputs. There are no comparison callbacks to reorder.

## Reproduce

Build/save the compiler at the pinned baseline, then build the candidate after applying retained.patch (`git apply --unidiff-zero`):

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
# Save this binary at the baseline before applying the patch and rebuilding.
/path/to/baseline-ms build bench/perf/bitset-relations/main.ms --build-type Release -o /tmp/bitset-before
target/release/ms build bench/perf/bitset-relations/main.ms --build-type Release -o /tmp/bitset-after
taskset -c 0 python3 bench/perf/bitset-relations/measure.py /tmp/bitset-before /tmp/bitset-after /tmp/bitset-samples.json --samples 8
taskset -c 0 python3 bench/perf/bitset-relations/focused.py /tmp/bitset-before /tmp/bitset-after /tmp/bitset-focused.json --samples 8
python3 bench/perf/bitset-relations/instructions.py /tmp/bitset-before /tmp/bitset-after /tmp/bitset-instructions
```

Use an allowed CPU and a new output path. Valgrind 3.24.0 was extracted from the official Debian package already documented in `../list-distinct/environment.json`; this environment uses `VALGRIND_LIB=/workspace/shared/valgrind/usr/libexec/valgrind` and `--valgrind /workspace/shared/valgrind/usr/bin/valgrind`.

Both binaries use the same source and native runtime archive; only embedded BitSet source changes. Each process constructs its inputs before the internal timer. Timed work includes the query loop and checksum. Compile, process launch, input setup and warmups are excluded. Eight alternating before/after pairs cover 39 cases: 3 query directions,0/1/8/1024/65536 words, full-scan true/late false and early false. Superset reverses operands, so its meaning matches subset. Producer exit status, stderr, exact output shape, positive elapsed time and an independently known Bool-count checksum are checked. Output paths cannot be overwritten and a report is complete only after every expected row succeeds. The validator also rejected failed exits, missing fields, zero elapsed time, bad checksums and stderr in manual error checks.

## Results

All 39 ratio-of-median results improved in samples.json. Full-scan ratios are robustly below baseline across sizes; longer focused full scans are retained separately. Early answers demonstrate reduced traversal, but the shortest candidate timings include clock overhead, so do not interpret their large wall ratios as precise per-operation speedups. Instruction counts are whole-producer Callgrind Ir, including setup and checksum; instrumented elapsed times are ignored. Ir decreases on every case. At 65536 words setup dominates the short instruction-count workload, so those ratios understate the isolated query work reduction.

Whole timed batch milliseconds, median [min,max], plus median paired ratio. Raw samples include all variation.

| Query,words,answer,repeats | Before ms | After ms | Paired ratio |
| --- | ---: | ---: | ---: |
| ('subset', 0, 'true', 2000000) | 23.2708 [12.1831,37.2139] | 7.0992 [4.3460,9.5535] | 0.327 |
| ('subset', 1, 'true', 500000) | 16.5934 [7.8678,30.4432] | 2.6093 [1.6348,4.6015] | 0.185 |
| ('subset', 1, 'early', 500000) | 9.8263 [7.4178,18.2764] | 1.2116 [0.5937,3.5859] | 0.120 |
| ('subset', 1, 'late', 500000) | 10.3045 [5.7302,13.4227] | 1.7267 [0.5327,2.6119] | 0.146 |
| ('subset', 8, 'true', 200000) | 18.3026 [16.2060,22.4752] | 3.3005 [1.0702,5.0905] | 0.177 |
| ('subset', 8, 'early', 200000) | 14.7906 [11.4725,17.8663] | 0.2151 [0.2017,0.9808] | 0.014 |
| ('subset', 8, 'late', 200000) | 11.7140 [8.7781,13.5477] | 1.4101 [0.9694,2.8657] | 0.126 |
| ('subset', 1024, 'true', 2000) | 6.3569 [4.8706,8.3011] | 1.9216 [1.3048,3.8626] | 0.297 |
| ('subset', 1024, 'early', 2000) | 4.8112 [3.1487,10.0754] | 0.0035 [0.0034,0.1543] | 0.001 |
| ('subset', 1024, 'late', 2000) | 6.2069 [4.4888,11.9758] | 1.6946 [1.4330,3.2994] | 0.291 |
| ('subset', 65536, 'true', 30) | 8.5720 [5.7580,18.6047] | 1.9223 [1.2715,2.6238] | 0.241 |
| ('subset', 65536, 'early', 30) | 6.0370 [3.5519,10.4133] | 0.0020 [0.0018,0.0025] | 0.000 |
| ('subset', 65536, 'late', 30) | 6.5625 [4.7058,8.9789] | 1.5411 [1.2216,11.3983] | 0.244 |
| ('superset', 0, 'true', 2000000) | 11.1021 [9.6352,14.9759] | 4.6493 [3.9078,5.7593] | 0.421 |
| ('superset', 1, 'true', 500000) | 6.5772 [5.4130,7.8371] | 1.5575 [1.1325,1.8565] | 0.242 |
| ('superset', 1, 'early', 500000) | 8.5434 [6.0873,11.8065] | 1.3149 [0.9893,2.7271] | 0.158 |
| ('superset', 1, 'late', 500000) | 7.4128 [6.1193,9.6933] | 1.7049 [1.0798,3.6966] | 0.264 |
| ('superset', 8, 'true', 200000) | 12.9043 [8.7587,18.2286] | 2.0562 [1.2969,4.3328] | 0.161 |
| ('superset', 8, 'early', 200000) | 10.4974 [8.3695,13.5155] | 0.5338 [0.3377,1.2342] | 0.050 |
| ('superset', 8, 'late', 200000) | 11.4115 [8.8576,20.6817] | 1.5334 [1.0284,4.8377] | 0.145 |
| ('superset', 1024, 'true', 2000) | 7.9332 [3.9886,12.9087] | 2.4358 [1.3194,5.2207] | 0.346 |
| ('superset', 1024, 'early', 2000) | 4.4323 [3.5587,16.6631] | 0.0050 [0.0049,0.0066] | 0.001 |
| ('superset', 1024, 'late', 2000) | 5.7322 [3.9442,6.8396] | 1.7674 [1.1078,2.7370] | 0.314 |
| ('superset', 65536, 'true', 30) | 6.5126 [4.7265,9.6364] | 1.3892 [1.1156,2.7982] | 0.220 |
| ('superset', 65536, 'early', 30) | 5.6993 [4.3680,9.1446] | 0.0018 [0.0015,0.0025] | 0.000 |
| ('superset', 65536, 'late', 30) | 9.8420 [4.3478,17.1170] | 2.7079 [1.8144,6.1494] | 0.355 |
| ('disjoint', 0, 'true', 2000000) | 14.1660 [12.1659,16.7920] | 6.3447 [3.8586,10.1774] | 0.434 |
| ('disjoint', 1, 'true', 500000) | 9.0927 [6.9010,12.3961] | 1.4742 [1.0697,2.2964] | 0.179 |
| ('disjoint', 1, 'early', 500000) | 7.5371 [6.4020,9.5230] | 1.8486 [1.4191,2.1532] | 0.250 |
| ('disjoint', 1, 'late', 500000) | 14.8053 [5.8242,46.8601] | 1.9148 [1.0325,10.3182] | 0.232 |
| ('disjoint', 8, 'true', 200000) | 12.0276 [10.2196,24.1620] | 2.1876 [1.3142,4.5720] | 0.144 |
| ('disjoint', 8, 'early', 200000) | 10.0790 [6.2869,27.2945] | 0.4714 [0.2700,5.0868] | 0.053 |
| ('disjoint', 8, 'late', 200000) | 18.0331 [9.0287,92.2531] | 2.6391 [1.1298,128.0088] | 0.150 |
| ('disjoint', 1024, 'true', 2000) | 4.5934 [3.2490,10.9476] | 1.0902 [0.8204,2.7413] | 0.251 |
| ('disjoint', 1024, 'early', 2000) | 5.0486 [3.0292,29.8457] | 0.0056 [0.0052,0.0075] | 0.001 |
| ('disjoint', 1024, 'late', 2000) | 11.1832 [3.4937,106.3493] | 1.5213 [0.8582,50.3757] | 0.186 |
| ('disjoint', 65536, 'true', 30) | 13.5111 [6.5285,50.8028] | 3.8230 [0.9117,16.4493] | 0.329 |
| ('disjoint', 65536, 'early', 30) | 5.5032 [3.6549,13.6357] | 0.0021 [0.0018,0.0031] | 0.000 |
| ('disjoint', 65536, 'late', 30) | 6.8416 [4.3946,16.4754] | 1.7537 [0.9494,49.7612] | 0.340 |

Whole-producer instruction examples:

| Case | Before Ir | After Ir | After/before |
| --- | ---: | ---: | ---: |
| ('subset', 0, 'true', 10000) | 335,784 | 124,615 | 0.371 |
| ('subset', 1, 'true', 10000) | 1,554,843 | 264,777 | 0.170 |
| ('subset', 1024, 'true', 10) | 324,129 | 147,329 | 0.455 |
| ('superset', 0, 'true', 10000) | 374,624 | 165,769 | 0.442 |
| ('superset', 1, 'true', 10000) | 1,574,837 | 304,785 | 0.194 |
| ('superset', 1024, 'true', 10) | 322,997 | 147,381 | 0.456 |
| ('disjoint', 0, 'true', 10000) | 374,624 | 164,623 | 0.439 |
| ('disjoint', 1, 'true', 10000) | 1,555,983 | 264,785 | 0.170 |
| ('disjoint', 1024, 'true', 10) | 302,517 | 106,421 | 0.352 |

## Validation and scope

Independent Sol 6.1 review found no correctness or harness issues. `bitset-relations.ms` has two tests: a 100-pair matrix compares predicates to unchanged algebra operations and verifies unchanged inputs, and boundary/decisive-word cases cover 63/64, first/last words, unequal lengths and self-comparison. Both pass in Debug and Release. The frozen `e2e/stdlib/bitset` test fixture passes. Repository checks, source formatting and standard-library documentation checks pass. Source lint exits successfully with the existing unreachable-return warning in BitSet.next and two intentional strict argument-parse warnings in the benchmark. This source-only change does not alter an API or native ABI. Full workspace Nextest and the full conformance corpus were not rerun locally; normal CI remains the merge gate. Windows/main workflow details were not inspected.

Longer full-scan controls, eight pairs:

| Query,words,answer,repeats | Before median [min,max] ms | After median [min,max] ms | Paired ratio |
| --- | ---: | ---: | ---: |
| ('subset', 1024, 'true', 40000) | 154.508 [112.076,238.010] | 60.734 [34.455,80.517] | 0.357 |
| ('subset', 1024, 'late', 40000) | 160.969 [135.023,331.245] | 71.987 [55.926,88.784] | 0.395 |
| ('subset', 65536, 'true', 600) | 151.327 [125.961,178.969] | 46.858 [35.469,65.205] | 0.313 |
| ('subset', 65536, 'late', 600) | 174.714 [135.465,215.147] | 57.793 [39.679,72.926] | 0.311 |
| ('superset', 1024, 'true', 40000) | 181.214 [144.618,225.690] | 47.548 [36.506,91.139] | 0.299 |
| ('superset', 1024, 'late', 40000) | 193.286 [125.825,334.329] | 64.920 [43.194,110.062] | 0.302 |
| ('superset', 65536, 'true', 600) | 235.497 [153.620,647.668] | 56.773 [34.924,137.687] | 0.266 |
| ('superset', 65536, 'late', 600) | 229.242 [151.940,352.125] | 58.840 [39.233,165.293] | 0.246 |
| ('disjoint', 1024, 'true', 40000) | 129.088 [101.676,175.769] | 39.624 [23.347,50.456] | 0.287 |
| ('disjoint', 1024, 'late', 40000) | 150.372 [129.471,185.047] | 33.080 [29.158,48.014] | 0.223 |
| ('disjoint', 65536, 'true', 600) | 144.092 [120.349,182.080] | 38.508 [29.960,56.346] | 0.279 |
| ('disjoint', 65536, 'late', 600) | 133.940 [115.390,210.778] | 52.071 [31.501,86.270] | 0.355 |
