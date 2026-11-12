# Current-main confirmation: 2026-11-12

Baseline compiler/runtime/stdlib: main `15e35bc8a853b917f7c3c054fd1b95c3337ed633`; proposed uses the same compiler/runtime with this PR's encoder changes. Both executables use the identical revised fixture. All compiler checks remain enabled; there is no compiler, ownership, ABI or API change in this follow-up.

The original fixture's branch-local setup was rejected by current main's compiler. The revised fixture uses ordinary typed setup helpers selected through documented literal matching. The five timed loops, output/error checks, warmup counts and CSV results are unchanged. Input reads, conversions and dispatch remain outside timing. Supported invocations preserve output and error behavior; unsupported operations now return 2 before file reads and malformed setup may fail in a different order. Those are outside the measured fixture contract. The earlier results remain historical because setup lifetimes may differ.

Same AMD EPYC 9V74 VM, CPU4, GCC 14.2.0 `-O3 -march=x86-64-v3 -mtune=generic`; Manuscript production LLVM Release. Same allocating C exact/growing controls, complete output validation and consumed checksum. Seven alternating paired runs over all 31 cases, equal calibrated counts, no outlier removal. Exact commands and binary/source hashes are in [metadata](metadata.json) and [samples](samples.json).

| Case | Baseline ns | Proposed ns | C exact ns | C grow ns | Paired ratio | Range |
|---|---:|---:|---:|---:|---:|---:|
| hex-random-0 | 33.27 | 5.88 | 13.87 | 13.94 | 0.179 | 0.167–0.188 |
| b64-random-0 | 33.42 | 5.49 | 14.26 | 13.80 | 0.167 | 0.142–0.169 |
| hex-random-1 | 63.44 | 44.49 | 13.83 | 15.75 | 0.701 | 0.654–0.720 |
| b64-random-1 | 83.28 | 34.04 | 14.80 | 16.86 | 0.408 | 0.377–0.448 |
| hex-random-2 | 69.21 | 46.76 | 14.17 | 16.87 | 0.676 | 0.628–0.698 |
| b64-random-2 | 85.70 | 36.25 | 15.27 | 17.39 | 0.428 | 0.415–0.651 |
| hex-random-3 | 90.80 | 48.78 | 14.63 | 17.02 | 0.534 | 0.517–0.545 |
| b64-random-3 | 90.27 | 27.45 | 14.70 | 16.95 | 0.309 | 0.246–0.321 |
| hex-random-13 | 163.05 | 77.04 | 20.41 | 45.00 | 0.467 | 0.448–0.509 |
| b64-random-13 | 182.36 | 71.91 | 21.10 | 42.77 | 0.397 | 0.366–0.429 |
| hex-random-64 | 441.11 | 166.05 | 57.49 | 165.92 | 0.383 | 0.371–0.396 |
| b64-random-64 | 373.75 | 210.93 | 52.35 | 139.77 | 0.563 | 0.547–0.722 |
| hex-random-1024 | 4924.90 | 2002.42 | 767.75 | 1113.67 | 0.408 | 0.392–0.419 |
| b64-random-1024 | 3435.92 | 2710.56 | 644.83 | 1052.78 | 0.824 | 0.621–0.847 |
| hex-random-65536 | 312426.56 | 133027.27 | 48445.51 | 61917.38 | 0.428 | 0.395–0.459 |
| b64-random-65536 | 193658.66 | 181298.31 | 41078.46 | 59923.52 | 0.907 | 0.693–1.116 |
| hex-random-1048576 | 5080076.04 | 2240943.28 | 802807.93 | 986541.38 | 0.439 | 0.422–0.468 |
| b64-random-1048576 | 3244658.85 | 2850330.51 | 653472.72 | 926806.61 | 0.888 | 0.824–0.956 |
| hex-zeros-65536 | 300673.13 | 136745.09 | 48742.69 | 60824.93 | 0.447 | 0.417–0.470 |
| b64-zeros-65536 | 198710.31 | 173932.69 | 39475.92 | 56241.35 | 0.880 | 0.867–0.968 |
| b64-boundary-12287 | 35747.28 | 31825.41 | 7403.41 | 10860.13 | 0.900 | 0.878–0.914 |
| b64-boundary-12288 | 35535.02 | 31923.04 | 7530.82 | 10986.25 | 0.901 | 0.883–0.980 |
| b64-boundary-12289 | 36249.79 | 31507.44 | 7323.34 | 10875.31 | 0.874 | 0.783–0.896 |
| b64-boundary-65535 | 190973.80 | 173236.05 | 39271.97 | 55721.42 | 0.895 | 0.881–0.927 |
| b64-boundary-65537 | 192545.78 | 175518.47 | 40236.19 | 59433.11 | 0.917 | 0.853–0.955 |
| hex-boundary-8191 | 37374.97 | 16099.27 | 5986.76 | 8038.60 | 0.428 | 0.412–0.601 |
| hex-boundary-8192 | 39177.88 | 15914.68 | 5988.45 | 7931.69 | 0.407 | 0.377–0.428 |
| hex-boundary-8193 | 37481.10 | 16951.46 | 5987.86 | 7948.64 | 0.451 | 0.433–0.476 |
| hex-boundary-16383 | 82252.36 | 34497.79 | 12106.21 | 15864.89 | 0.427 | 0.392–0.454 |
| hex-boundary-16384 | 79754.02 | 33814.92 | 12614.20 | 15620.26 | 0.448 | 0.424–0.505 |
| hex-boundary-16385 | 77879.20 | 32461.86 | 12170.63 | 15754.22 | 0.439 | 0.387–0.453 |

All case medians improve; individual noisy pairs remain visible. The shortest actual sample was 20.99ms. Nonempty outputs still trail exact-capacity C; this is not C parity.

Seven A/A pairs on four controls: median B/A ratios 0.959–1.030, individual range 0.824–1.205. [Raw A/A](aa.json).

Five paired exec-specific VmHWM controls, using the same protocol as the original report. These are process peaks including setup, not isolated allocations; compare baseline and proposed within this revised fixture.

| Case | Baseline peak KiB | Proposed peak KiB |
|---|---:|---:|
| hex-random-13 | 1468 | 1460 |
| b64-random-13 | 1468 | 1460 |
| hex-random-65536 | 2048 | 2044 |
| b64-random-65536 | 1956 | 1820 |
| hex-random-1048576 | 9716 | 9720 |
| b64-random-1048576 | 7700 | 6596 |

Validation: all 293 independent output/error fixtures pass for **both** newly built executables (586 runs), including UTF/hex invalid-budget and malformed controls retained by the fixture. All 42 focused codec tests pass again in both Debug and LLVM Release on the current compiler. [Correctness records](correctness.json), [test output](tests.json), [RSS records](rss.json).

Reproduce with the parent directory's commands, using the baseline commit above, the revised `probe.ms` for both compilers and `--pairs 7`. CPU timing and RSS runs remain separate. Independent review approved the fixture equivalence for supported invocations; production source is unchanged from the already reviewed bounded encoding implementation.
