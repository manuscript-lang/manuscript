# Avoid redundant membership checks in Set algebra

The retained change removes redundant output-membership checks from Set intersection and difference. Their fresh output receives a subset of one unique input Set, so a separate duplicate check before copying cannot find a match. Symmetric difference benefits in its left half. Its right half retains its check because the two Sets can carry different equality implementations.

For identical intersection or disjoint difference of `n` keys, hash calls fall from `3n - 1` to `2n`; disjoint symmetric difference falls from `6n - 1` to `5n`. A runtime regression pins these counts. The existing copy helper has two compile-time specializations: ordinary callers keep their membership check, and the fresh-output filter omits it. First representatives, insertion order, deep copying and the exported ABI retain their existing contracts. List code is unchanged; its benchmark cases serve as controls.

## Reproduce

Baseline runtime: `7e2e62357d5cebc1f144b6ee86f38da247cd2f52`. Patch snapshots use zero-context unified diffs; apply them with `git apply --unidiff-zero` to their stated baseline. The implementation is `retained-set.patch`; its SHA-256, runtime source hashes and binary identities are recorded in `environment.json` and the sample files.

Build a baseline runtime in a separate worktree, then the candidate compiler:

```sh
git worktree add /tmp/ms-collection-baseline 7e2e62357d5cebc1f144b6ee86f38da247cd2f52
(cd /tmp/ms-collection-baseline && cargo xtask runtime)
cargo xtask runtime
cargo build --release --locked -p ms-cli
MS_RT_LIB=/tmp/ms-collection-baseline/target/ms-native/libms_native.a \
  target/release/ms build bench/perf/list-distinct/main.ms \
  --build-type Release -o /tmp/collections-before
target/release/ms build bench/perf/list-distinct/main.ms \
  --build-type Release -o /tmp/collections-after
python3 bench/perf/list-distinct/measure.py \
  /tmp/collections-before /tmp/collections-after /tmp/collection-samples.json --samples 8
taskset -c 0 python3 bench/perf/list-distinct/focused.py \
  /tmp/collections-before /tmp/collections-after /tmp/collection-focused.json --samples 10
python3 bench/perf/list-distinct/instructions.py \
  /tmp/collections-before /tmp/collections-after /tmp/collection-instructions
```

`MS_RT_LIB` selects the baseline native archive while both programs use the same compiler and source. The pure runtime IR built alongside the archives has the same SHA-256. Both build inventories report `backend: cranelift`, `build_type: Release`; results use that label. The native archives use Cargo's release profile and pinned Rust 1.99.1, with native debug information disabled by `xtask`. Linux amd64 measurements use an Intel Xeon Platinum 8573C, five available CPUs, and Linux 6.18.55. Other platforms were not measured. Select an allowed CPU instead of 0 when reproducing the Linux affinity command.

The producer times repeated operations and checksum traversal after constructing its inputs. Compilation, Python process launch and initial input construction are outside those elapsed times. One process per binary warms each case before sampling, then before/after order alternates. The full run uses eight pairs; longer focused controls use ten pairs on CPU 0. No builds or other benchmarks run during sampling.

The harness verifies exit status, stderr, output shape, positive elapsed time and independently computed checksums. It rejects duplicate workload identities, refuses to overwrite an output, and marks a report complete only after every selected workload and sample succeeds. Runtime/source tests additionally check ordering, custom hash collisions, first representatives and independent nested copies.

## Results

`instruction-counts.json` records whole-producer Callgrind `Ir`, including setup and checksum traversal; instrumented elapsed times are not used. The measured Set kernels execute 8–15% fewer instructions. List, union and conversion controls remain within 0.002% of baseline. Valgrind 3.24.0 was extracted into the workspace from the official Debian package recorded in `environment.json`.

`samples.json` retains the complete full run, including apparent regressions and timing variation. `focused-samples.json` retains longer controls. Times below are whole timed batches in milliseconds; brackets show minimum and maximum, with the median first. Parameters are `(kind, input size, distinct count or Set shift, repetitions)`. Both the ratio of medians and median paired ratio are displayed. Wall-clock ranges are wide, including variations in unchanged controls. These timings do not establish a general wall-clock speedup. Instruction and hash counts establish the removed work.

### Instructions

| Case | Before Ir | After Ir | After/before |
| --- | ---: | ---: | ---: |
| ('int', 100000, 1, 10) | 91,945,515 | 91,944,309 | 1.0000 |
| ('int', 100000, 32, 10) | 92,611,013 | 92,610,965 | 1.0000 |
| ('int', 10000, 10000, 10) | 47,865,466 | 47,865,408 | 1.0000 |
| ('string', 8, 8, 2000) | 12,255,387 | 12,255,349 | 1.0000 |
| ('string', 10000, 32, 10) | 29,093,613 | 29,093,573 | 1.0000 |
| ('string', 10000, 10000, 10) | 120,862,616 | 120,862,566 | 1.0000 |
| ('intersection', 1024, 0, 10) | 4,964,109 | 4,219,751 | 0.8501 |
| ('difference', 1024, 1024, 10) | 4,896,586 | 4,151,150 | 0.8478 |
| ('difference', 100000, 100000, 2) | 150,470,064 | 135,738,331 | 0.9021 |
| ('symmetric_difference', 1024, 1024, 10) | 9,127,813 | 8,382,361 | 0.9183 |
| ('union', 1024, 0, 10) | 2,631,283 | 2,631,245 | 1.0000 |
| ('union', 1024, 1024, 10) | 4,832,954 | 4,832,910 | 1.0000 |
| ('int_set', 10000, 1, 10) | 11,430,516 | 11,430,482 | 1.0000 |
| ('int_set', 10000, 10000, 10) | 35,169,168 | 35,169,106 | 1.0000 |
| ('string_set', 10000, 32, 10) | 31,176,848 | 31,176,768 | 1.0000 |
| ('string_set', 10000, 10000, 10) | 85,500,360 | 85,500,350 | 1.0000 |

### Full timing run

| Case | Before ms, median [min, max] | After ms, median [min, max] | Ratio of medians | Median paired ratio |
| --- | ---: | ---: | ---: | ---: |
| ('int', 0, 1, 20000000) | 99.96 [88.68, 135.53] | 118.01 [84.74, 138.30] | 1.181 | 1.233 |
| ('int', 8, 8, 500000) | 112.83 [89.44, 146.71] | 110.86 [102.52, 146.61] | 0.983 | 0.994 |
| ('int', 16, 16, 150000) | 102.01 [86.25, 128.94] | 110.36 [98.29, 137.57] | 1.082 | 1.131 |
| ('int', 17, 17, 150000) | 118.54 [92.82, 140.43] | 111.44 [93.49, 132.22] | 0.940 | 1.042 |
| ('int', 1024, 1024, 3000) | 132.52 [102.32, 197.57] | 129.64 [119.49, 157.23] | 0.978 | 0.953 |
| ('int', 10000, 10000, 300) | 267.21 [173.06, 332.17] | 323.97 [193.11, 462.07] | 1.212 | 1.354 |
| ('int', 100000, 100000, 30) | 306.24 [173.73, 375.66] | 323.31 [183.49, 376.74] | 1.056 | 0.994 |
| ('int', 100000, 32, 100) | 107.04 [72.05, 143.58] | 93.26 [79.43, 130.15] | 0.871 | 0.829 |
| ('int', 100000, 1, 100) | 112.14 [62.28, 176.51] | 111.88 [63.49, 148.31] | 0.998 | 0.925 |
| ('string', 8, 8, 150000) | 117.79 [68.74, 173.03] | 120.52 [70.49, 169.16] | 1.023 | 1.000 |
| ('string', 17, 17, 50000) | 109.16 [94.11, 199.26] | 112.27 [100.01, 166.01] | 1.028 | 0.968 |
| ('string', 1024, 1024, 1000) | 163.46 [108.85, 214.96] | 144.54 [129.23, 214.55] | 0.884 | 1.045 |
| ('string', 10000, 10000, 100) | 225.22 [151.50, 301.87] | 207.10 [174.04, 306.66] | 0.920 | 0.906 |
| ('string', 100000, 100000, 10) | 329.52 [269.90, 627.27] | 290.41 [251.74, 434.17] | 0.881 | 0.900 |
| ('string', 100000, 32, 100) | 248.41 [216.15, 336.34] | 284.89 [223.98, 324.95] | 1.147 | 1.196 |
| ('intersection', 8, 0, 200000) | 59.03 [42.41, 67.03] | 45.31 [35.68, 67.92] | 0.768 | 0.848 |
| ('intersection', 1024, 0, 3000) | 130.79 [99.95, 159.00] | 99.16 [85.10, 130.09] | 0.758 | 0.775 |
| ('intersection', 100000, 0, 30) | 307.10 [267.92, 378.16] | 275.22 [242.51, 422.37] | 0.896 | 0.943 |
| ('difference', 8, 8, 200000) | 57.47 [43.50, 70.14] | 41.11 [32.73, 56.56] | 0.715 | 0.687 |
| ('difference', 1024, 1024, 3000) | 117.74 [97.49, 153.21] | 119.76 [87.95, 755.73] | 1.017 | 0.965 |
| ('difference', 100000, 100000, 30) | 293.76 [264.54, 341.85] | 305.66 [264.64, 562.54] | 1.041 | 0.998 |
| ('symmetric_difference', 8, 8, 100000) | 49.98 [44.06, 63.66] | 47.85 [40.85, 64.11] | 0.957 | 0.969 |
| ('symmetric_difference', 1024, 1024, 1500) | 161.34 [132.17, 173.54] | 146.79 [134.44, 466.86] | 0.910 | 0.988 |
| ('symmetric_difference', 100000, 100000, 15) | 373.08 [305.09, 533.34] | 364.71 [317.98, 536.07] | 0.978 | 1.020 |
| ('union', 8, 0, 200000) | 27.63 [25.79, 37.96] | 31.52 [29.13, 39.35] | 1.141 | 1.128 |
| ('union', 1024, 0, 3000) | 46.79 [42.89, 62.93] | 48.59 [43.13, 69.93] | 1.039 | 1.059 |
| ('union', 1024, 1024, 1500) | 51.62 [43.48, 72.15] | 64.16 [48.58, 83.66] | 1.243 | 1.260 |
| ('union', 100000, 0, 30) | 114.85 [92.72, 194.08] | 118.37 [104.61, 134.42] | 1.031 | 1.040 |
| ('union', 100000, 100000, 15) | 123.98 [104.00, 182.69] | 124.90 [110.13, 165.90] | 1.007 | 0.975 |
| ('int_set', 100000, 100000, 30) | 159.06 [138.90, 219.33] | 164.13 [146.05, 237.11] | 1.032 | 1.055 |
| ('int_set', 100000, 1, 100) | 102.54 [83.84, 120.59] | 101.55 [76.59, 139.98] | 0.990 | 1.032 |
| ('string_set', 100000, 100000, 10) | 143.52 [119.74, 431.13] | 143.42 [123.25, 308.87] | 0.999 | 1.007 |
| ('string_set', 100000, 32, 100) | 348.55 [272.15, 425.60] | 454.31 [272.11, 857.55] | 1.303 | 1.211 |

### Longer controls

| Case | Before ms, median [min, max] | After ms, median [min, max] | Ratio of medians | Median paired ratio |
| --- | ---: | ---: | ---: | ---: |
| ('int', 100000, 1, 500) | 351.96 [336.37, 433.97] | 376.91 [350.71, 511.36] | 1.071 | 1.055 |
| ('string', 100000, 32, 300) | 692.08 [666.75, 859.81] | 709.02 [673.40, 941.69] | 1.024 | 1.034 |
| ('string', 100000, 100000, 20) | 493.26 [456.50, 544.46] | 495.51 [467.69, 545.01] | 1.005 | 1.002 |
| ('difference', 1024, 1024, 10000) | 353.02 [340.19, 437.37] | 294.41 [276.93, 348.76] | 0.834 | 0.829 |
| ('symmetric_difference', 1024, 1024, 5000) | 445.79 [427.77, 483.72] | 481.35 [458.77, 595.77] | 1.080 | 1.101 |

## Rejected List alternatives

`rejected-return-bool.patch`, `rejected-return-bool-main.ms`, and `rejected-return-bool-samples.json` retain an initial candidate and its exact producer source. It returned an insertion boolean from the whole copy helper, moving duplicate visits through that helper. Despite fewer hash calls, the 100,000-element single-value Int workload regressed by 43.6% in that run. This experiment used baseline `4c0a1cb820e772f56a0c831a0f2fe37fbc96a9a7`; assess its absolute times within that before/after pair.

The `inlined-helper`, `outlined-helper`, `hinted-helper`, and `forced-inline-list` patches and data retain subsequent experiments against the pinned main revision. The first has its exact producer in `inlined-helper-main.ms`; later variants use `main.ms`. They reduce List instruction counts, but repeated common-case timings remain inconsistent. Global outlining also added roughly five instructions per new key to conversion. No List rewrite or inlining policy is retained in the fix.

## Validation and coverage

- `cargo nextest run -p ms-rt`: 152 tests passed, including the exact Set hash-count and balanced live-allocation regression.
- `cargo clippy --workspace --all-targets -- -D warnings`, `cargo fmt --all --check`, and `cargo run --release --locked -q -p ms-repo-check` passed on the rebased revision.
- `list-distinct.ms`: five tests passed in Debug and Release; the existing `collections.ms` fixture passed thirteen Release tests. List cases exercise the unchanged shared copy path.
- Selected frozen `list-parity` and `map-transforms` conformance cases passed. A manual replay of the older `collections` corpus fixture differed in diagnostic positions; it is tagged `aliasing`, which the routine corpus run excludes. The whole corpus and whole workspace Nextest run were not run here.
- Manual harness checks rejected failed exits, malformed output, non-positive elapsed time, changed checksums and stderr. A failed first run remained incomplete, and an existing output was not overwritten.

The bounded additional source pass inspected Map equality, list concatenation and flattening, Set relation checks, and Queue/PriorityQueue operations. Their existing early exits, bulk copies, amortized compaction and heap operations yielded no additional measured finding. This report covers the scoped Set change and this host.
