# Whole-program kernels

`programs/` measures one operation per loop and several of its results come from proofs that fit those exact loops. These kernels are ordinary programs written the way a user would write them (no attempt to match a compiler proof), each compared with hand-written Go that uses a slice, struct or map directly. Every sample must report the same checksum. Reproduce with `MS=./target/release/ms GO=go sh bench/perf/kernels/run.sh 5`; compare only runs from the same machine.

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
