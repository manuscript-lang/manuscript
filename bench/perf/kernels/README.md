# Whole-program kernels

`programs/` measures one operation per loop and several of its results come from proofs that fit those exact loops. These kernels are ordinary programs written the way a user would write them (no attempt to match a compiler proof), each compared with hand-written Go that uses a slice, struct or map directly. Every sample must report the same checksum. Reproduce with `MS=./target/release/ms GO=go sh bench/perf/kernels/run.sh 5`; compare only runs from the same machine.

Reference run of the Rust `ms` after #941, release build with LLVM (2026-10-21; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1; median of 7, microseconds). "Rust" is the same algorithms hand-written with `Vec`/`HashMap` at `opt-level=3`; "Rust, overflow checks" adds `-C overflow-checks=on`. Ratios are Manuscript over the other language.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 72181 | 42192 | 0.58x | 29156 | 0.40x | 31044 | 0.43x | 28389 | 0.39x | 38134 | 0.53x | 1.45x | 1.36x |
| nbody_200k | 17408 | 14115 | 0.81x | 9449 | 0.54x | 8111 | 0.47x | 12564 | 0.72x | 14403 | 0.83x | 1.49x | 1.74x |
| life_128x128_50 | 167314 | 9965 | 0.06x | 6445 | 0.04x | 7300 | 0.04x | 88970 | 0.53x | 184933 | 1.11x | 1.55x | 1.37x |
| matmul_200 | 19534 | 17944 | 0.92x | 13517 | 0.69x | 13544 | 0.69x | 9149 | 0.47x | 18793 | 0.96x | 1.33x | 1.32x |
| trees_d16_x20 | 67612 | 51982 | 0.77x | 45671 | 0.68x | 47589 | 0.70x | 39578 | 0.59x | 40382 | 0.60x | 1.14x | 1.09x |
| collatz_1M | 276916 | 285834 | 1.03x | 130898 | 0.47x | 416989 | 1.51x | 262096 | 0.95x | 349321 | 1.26x | 2.18x | 0.69x |
| map_count_2M | 28713 | 49727 | 1.73x | 29359 | 1.02x | 31609 | 1.10x | 22306 | 0.78x | 31683 | 1.10x | 1.69x | 1.57x |

Manuscript is faster than hand-written Go on every kernel except collatz (a tie) and map_count (1.7x slower). Against Rust with overflow checks it is 1.1x to 1.7x slower on every kernel except collatz, where Rust with checks is slower than Manuscript; the widest gaps are nbody (1.7x) and map_count (1.6x).
