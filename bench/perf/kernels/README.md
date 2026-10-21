# Whole-program kernels

`programs/` measures one operation per loop and several of its results come from proofs that fit those exact loops. These kernels are ordinary programs written the way a user would write them (no attempt to match a compiler proof), each compared with hand-written Go that uses a slice, struct or map directly. Every sample must report the same checksum. Reproduce with `MS=./target/release/ms GO=go sh bench/perf/kernels/run.sh 5`; compare only runs from the same machine.

Reference run of the Rust `ms` after #930 (2026-10-21; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1; median of 7, microseconds). "Rust" is the same algorithms hand-written with `Vec`/`HashMap` at `opt-level=3`; "Rust, overflow checks" adds `-C overflow-checks=on`. Ratios are Manuscript over the other language.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 73141 | 41256 | 0.56x | 29280 | 0.40x | 31627 | 0.43x | 27750 | 0.38x | 31878 | 0.44x | 1.41x | 1.30x |
| nbody_200k | 10822 | 12819 | 1.18x | 7201 | 0.67x | 7437 | 0.69x | 8865 | 0.82x | 9497 | 0.88x | 1.78x | 1.72x |
| life_128x128_50 | 61478 | 25516 | 0.42x | 3698 | 0.06x | 3795 | 0.06x | 34944 | 0.57x | 53396 | 0.87x | 6.90x | 6.72x |
| matmul_200 | 12983 | 24269 | 1.87x | 7689 | 0.59x | 8644 | 0.67x | 4745 | 0.37x | 13903 | 1.07x | 3.16x | 2.81x |
| trees_d16_x20 | 50121 | 54194 | 1.08x | 35698 | 0.71x | 38792 | 0.77x | 28444 | 0.57x | 31448 | 0.63x | 1.52x | 1.40x |
| collatz_1M | 313496 | 397201 | 1.27x | 189716 | 0.61x | 299815 | 0.96x | 276619 | 0.88x | 371553 | 1.19x | 2.09x | 1.32x |
| map_count_2M | 27480 | 36901 | 1.34x | 26751 | 0.97x | 27310 | 0.99x | 11134 | 0.41x | 15085 | 0.55x | 1.38x | 1.35x |

Manuscript is faster than hand-written Go on sieve and life, and between 1.1x and 1.9x slower on the rest (matmul worst). It is 1.3x to 1.8x slower than Rust with overflow checks on sieve, nbody, trees, collatz and map_count, and 3x to 6.6x slower on matmul and life, where LLVM vectorizes.
