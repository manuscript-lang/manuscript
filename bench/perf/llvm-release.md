# Release builds: LLVM against Cranelift

Release and MinSizeRel builds on Linux optimize with LLVM (`clang -O3`) when `clang` is installed; Debug builds and every other host use Cranelift. This page records both backends on the same 31 benchmarks, run back to back with the same `ms` binary: `MS_BACKEND=cranelift` selects Cranelift.

Method: `MS=ms sh bench/perf/<suite>/run.sh 5` for `kernels`, `competence` and `programs`; linux/amd64, four vCPUs, go1.24.7, rustc 1.99.1, one machine, minimum (kernels, competence) or median (programs) of 5 runs. Single runs on a shared machine move by several percent, so treat differences under about 10% as noise. Units are microseconds for kernels and competence, ns per operation for programs. Ratios of the other languages are Manuscript over them; below 1.00x is faster than they are.

## Speedup of LLVM over Cranelift (Manuscript only)

Speedup is Cranelift time over LLVM time; `folded` means LLVM removed the loop entirely, so the time is not a speed.

| suite | benchmark | Cranelift | LLVM | speedup |
|---|---|---:|---:|---:|
| kernels | sieve_5M | 34987 | 31160 | 1.12x |
| kernels | nbody_200k | 12263 | 7870 | 1.56x |
| kernels | life_128x128_50 | 21688 | 4249 | 5.10x |
| kernels | matmul_200 | 21012 | 7555 | 2.78x |
| kernels | trees_d16_x20 | 73075 | 60419 | 1.21x |
| kernels | collatz_1M | 358213 | 370980 | 0.97x |
| kernels | map_count_2M | 43716 | 29912 | 1.46x |
| competence | call_fib_36 | 87399 | 73154 | 1.19x |
| competence | dispatch_100M | 173929 | 134471 | 1.29x |
| competence | closure_100M | 80746 | 28027 | 2.88x |
| competence | sort_1M | 129418 | 110437 | 1.17x |
| competence | text_1M | 103902 | 86017 | 1.21x |
| competence | strmap_10M | 247785 | 202966 | 1.22x |
| competence | errors_50M | 64247 | 29506 | 2.18x |
| competence | records_1M_x20 | 219943 | 198590 | 1.11x |
| competence | grid2d_500x20 | 11347 | 7118 | 1.59x |
| competence | struct_100M | 41489 | 0 | folded |
| competence | stack_20M | 75950 | 51479 | 1.48x |
| competence | optional_100M | 135705 | 58656 | 2.31x |
| competence | set_2M | 88060 | 87615 | 1.01x |
| competence | chars_1M | 369564 | 377365 | 0.98x |
| programs | string_append_50k | 5.9 | 4.87 | 1.21x |
| programs | read_line | 107.48 | 117.65 | 0.91x |
| programs | map_put_get_8k | 32.06 | 31.75 | 1.01x |
| programs | int_eq | 1.42 | 1.1 | 1.29x |
| programs | generic_call | 0.52 | 0.33 | 1.58x |
| programs | method_call | 0.58 | 0 | folded |
| programs | try | 0.45 | 0.31 | 1.45x |
| programs | match | 2.9 | 1.67 | 1.74x |
| programs | builtin_length | 0.67 | 0 | folded |
| programs | for_list | 0.89 | 0.64 | 1.39x |

## Results with LLVM

### Kernels

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | c us | c / go | c-ms us | c-ms / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 70146 | 31160 | 0.44x | 29460 | 0.42x | 30086 | 0.43x | 28481 | 0.41x | 33641 | 0.48x | 1.06x | 1.04x |
| nbody_200k | 9691 | 7870 | 0.81x | 5724 | 0.59x | 5563 | 0.57x | 7799 | 0.80x | 6895 | 0.71x | 1.37x | 1.41x |
| life_128x128_50 | 51184 | 4249 | 0.08x | 3033 | 0.06x | 2748 | 0.05x | 28401 | 0.55x | 36812 | 0.72x | 1.40x | 1.55x |
| matmul_200 | 11754 | 7555 | 0.64x | 6200 | 0.53x | 6095 | 0.52x | 3479 | 0.30x | 9622 | 0.82x | 1.22x | 1.24x |
| trees_d16_x20 | 43567 | 60419 | 1.39x | 28500 | 0.65x | 32178 | 0.74x | 27242 | 0.63x | 24632 | 0.57x | 2.12x | 1.88x |
| collatz_1M | 236869 | 370980 | 1.57x | 160134 | 0.68x | 251559 | 1.06x | 177477 | 0.75x | 244965 | 1.03x | 2.32x | 1.47x |
| map_count_2M | 18486 | 29912 | 1.62x | 20874 | 1.13x | 23181 | 1.25x | 10360 | 0.56x | 14437 | 0.78x | 1.43x | 1.29x |

### Competence

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| call_fib_36 | 61962 | 73154 | 1.18x | 33842 | 0.55x | 55961 | 0.90x | 2.16x | 1.31x |
| dispatch_100M | 237328 | 134471 | 0.57x | 136017 | 0.57x | 114631 | 0.48x | 0.99x | 1.17x |
| closure_100M | 29870 | 28027 | 0.94x | 0 | folded | 37457 | 1.25x | folded | 0.75x |
| sort_1M | 181839 | 110437 | 0.61x | 35655 | 0.20x | 34226 | 0.19x | 3.10x | 3.23x |
| text_1M | 54747 | 86017 | 1.57x | 24505 | 0.45x | 21904 | 0.40x | 3.51x | 3.93x |
| strmap_10M | 132082 | 202966 | 1.54x | 187712 | 1.42x | 168304 | 1.27x | 1.08x | 1.21x |
| errors_50M | 65991 | 29506 | 0.45x | 22993 | 0.35x | 48878 | 0.74x | 1.28x | 0.60x |
| records_1M_x20 | 166371 | 198590 | 1.19x | 123998 | 0.75x | 132980 | 0.80x | 1.60x | 1.49x |
| grid2d_500x20 | 8038 | 7118 | 0.89x | 16339 | 2.03x | 15931 | 1.98x | 0.44x | 0.45x |
| struct_100M | 18956 | 0 | folded | 0 | folded | 0 | folded | folded | folded |
| stack_20M | 329454 | 51479 | 0.16x | 51027 | 0.15x | 51643 | 0.16x | 1.01x | 1.00x |
| optional_100M | 113895 | 58656 | 0.52x | 59295 | 0.52x | 59663 | 0.52x | 0.99x | 0.98x |
| set_2M | 102400 | 87615 | 0.86x | 66402 | 0.65x | 66341 | 0.65x | 1.32x | 1.32x |
| chars_1M | 457807 | 377365 | 0.82x | 0 | folded | 21630 | 0.05x | folded | 17.45x |

### Programs

| operation | ops | Manuscript | Go | Rust | Rust, overflow checks | ms / Go | ms / Rust | ms / Rust, overflow checks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.87 | 4.37 | 1.20 | 1.31 | 1.11x | 4.07x | 3.72x |
| read_line | 200000 | 117.65 | 100.16 | 62.69 | 68.97 | 1.17x | 1.88x | 1.71x |
| map_put_get_8k | 16000 | 31.75 | 34.54 | 42.84 | 54.46 | 0.92x | 0.74x | 0.58x |
| int_eq | 10000000 | 1.10 | 0.82 | 0.47 | 0.43 | 1.35x | 2.37x | 2.59x |
| generic_call | 100000000 | 0.33 | 0.34 | 0.35 | 0.35 | 0.97x | 0.94x | 0.93x |
| method_call | 100000000 | 0.00 | 0.39 | 1.69 | 1.48 | 0.00x | 0.00x | 0.00x |
| try | 100000000 | 0.31 | 0.35 | 0.96 | 0.68 | 0.90x | 0.33x | 0.46x |
| match | 100000000 | 1.67 | 2.01 | 1.19 | 1.27 | 0.83x | 1.40x | 1.31x |
| builtin_length | 100000000 | 0.00 | 0.34 | 0.35 | 0.35 | 0.00x | 0.00x | 0.00x |
| for_list | 100000000 | 0.64 | 0.66 | 0.38 | 0.67 | 0.97x | 1.72x | 0.96x |

## Reading the numbers honestly

- LLVM is faster on most rows and the largest gains are in loops it can vectorize or simplify (life, matmul, nbody, closure, dispatch, stack, optional).
- Rows marked folded (`method_call`, `builtin_length`, `struct_100M`) are loops LLVM proves constant; LLVM compiled the Manuscript loop away, so the time says the benchmark stopped measuring the operation, not that the operation is free. Rust already folds some of these rows.
- Manuscript still trails Rust on trees (2.1x), collatz (2.3x; 1.5x against Rust with overflow checks), sort, text, string_append and several runtime-bound rows. Those gaps are runtime and data-representation costs, not code generation, and LLVM does not close them.
- Collatz is no faster under LLVM: its inner loop is dominated by unpredictable branches, and the optimized code adds a branch for the multiply overflow check.
- Manuscript checks Int overflow and list bounds; Go and Rust (release) check only bounds. Compare with the overflow-checked Rust column where it exists.
