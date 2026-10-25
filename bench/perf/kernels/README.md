# Whole-program kernels

`programs/` measures one operation per loop and several of its results come from proofs that fit those exact loops. These kernels are ordinary programs written the way a user would write them (no attempt to match a compiler proof), each compared with hand-written Go that uses a slice, struct or map directly. Every sample must report the same checksum. Reproduce with `MS=./target/release/ms GO=go sh bench/perf/kernels/run.sh 5`; compare only runs from the same machine.

## main at c1b81215 (2026-10-25)

linux/amd64, four cores, Go 1.24.7, rustc 1.99.1, `ms` Release build with LLVM; median of 5, microseconds. "c" is the same algorithm in C at `-O3`; "c-ms" is the C a no-GC Manuscript backend would emit, with bounds, overflow and poll checks.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | c us | c / go | c-ms us | c-ms / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 63413 | 29703 | 0.47x | 26714 | 0.42x | 28160 | 0.44x | 24044 | 0.38x | 29069 | 0.46x | 1.11x | 1.05x |
| nbody_200k | 9836 | 8216 | 0.84x | 6716 | 0.68x | 6686 | 0.68x | 8225 | 0.84x | 8827 | 0.90x | 1.22x | 1.23x |
| life_128x128_50 | 55290 | 4306 | 0.08x | 3401 | 0.06x | 3581 | 0.06x | 32577 | 0.59x | 48791 | 0.88x | 1.27x | 1.20x |
| matmul_200 | 11670 | 8040 | 0.69x | 6990 | 0.60x | 7707 | 0.66x | 4372 | 0.37x | 12827 | 1.10x | 1.15x | 1.04x |
| trees_d16_x20 | 42206 | 26065 | 0.62x | 29972 | 0.71x | 33569 | 0.80x | 24227 | 0.57x | 23689 | 0.56x | 0.87x | 0.78x |
| collatz_1M | 285058 | 242730 | 0.85x | 178638 | 0.63x | 274975 | 0.96x | 257367 | 0.90x | 346164 | 1.21x | 1.36x | 0.88x |
| map_count_2M | 25054 | 14428 | 0.58x | 23757 | 0.95x | 24993 | 1.00x | 11288 | 0.45x | 14336 | 0.57x | 0.61x | 0.58x |

Manuscript is faster than hand-written Go on every kernel. Against Rust with overflow checks it is level or ahead on sieve, matmul, trees, collatz and map_count, and 1.2x on life and nbody.

## 2026-10-22

Reference run of the Rust `ms`, release build with LLVM (2026-10-22; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1; median of 7, microseconds). "Rust" is the same algorithms hand-written with `Vec`/`HashMap` at `opt-level=3`; "Rust, overflow checks" adds `-C overflow-checks=on`. Ratios are Manuscript over the other language.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 94247 | 31627 | 0.34x | 26235 | 0.28x | 35252 | 0.37x | 26459 | 0.28x | 29682 | 0.31x | 1.21x | 0.90x |
| nbody_200k | 13777 | 10195 | 0.74x | 7380 | 0.54x | 7847 | 0.57x | 10818 | 0.79x | 11268 | 0.82x | 1.38x | 1.30x |
| life_128x128_50 | 55964 | 5053 | 0.09x | 4109 | 0.07x | 4401 | 0.08x | 30363 | 0.54x | 46818 | 0.84x | 1.23x | 1.15x |
| matmul_200 | 13718 | 10127 | 0.74x | 10015 | 0.73x | 10264 | 0.75x | 8352 | 0.61x | 16031 | 1.17x | 1.01x | 0.99x |
| trees_d16_x20 | 50941 | 26297 | 0.52x | 34857 | 0.68x | 39992 | 0.79x | 29621 | 0.58x | 29564 | 0.58x | 0.75x | 0.66x |
| collatz_1M | 270537 | 233764 | 0.86x | 142722 | 0.53x | 278383 | 1.03x | 239953 | 0.89x | 330889 | 1.22x | 1.64x | 0.84x |
| map_count_2M | 24282 | 17309 | 0.71x | 26482 | 1.09x | 27368 | 1.13x | 12532 | 0.52x | 16424 | 0.68x | 0.65x | 0.63x |

Manuscript is faster than hand-written Go on every kernel. Against Rust with overflow checks it is level or ahead on sieve, matmul, trees, collatz and map_count, 1.15x on life and 1.3x on nbody, the widest gap left.
