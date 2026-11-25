# Whole-program kernels

`programs/` measures one operation per loop and several of its results come from proofs that fit those exact loops. These kernels are ordinary programs written the way a user would write them (no attempt to match a compiler proof), each compared with hand-written Go that uses a slice, struct or map directly. Every sample must report the same checksum. Reproduce with `MS=./target/release/ms GO=go ms run bench/perf/tools/kernels.ms -- kernels 5`; compare only runs from the same machine.

The current runner reports the minimum of N rotating runs. It checks each producer's exit status and requires every kernel a version implements exactly once per successful trial (plain C has no map_count: a hand-rolled int64 table is not comparable with the general `Map`, so its cell is `n/a`), all requested versions, exactly N trials, nonnegative integer microseconds, and matching checksums before printing any comparison. `ABLATE=1` requires the four additional C variants too. A sub-two-microsecond time is displayed as `folded`, including zero from clock resolution. Build time and process startup are outside the kernels' internal timers. The shared reporter applies the same checks to `competence/` with its fourteen kernels. Run its regression tests without native toolchains with `python3 -m unittest discover -s bench/perf -p test_kernel_trials.py`.

Record the source revision, machine, tool versions, build type and effective backend when publishing timings. `ms build` defaults to Release; a release-built compiler binary alone does not establish LLVM use. `MS_BACKEND=cranelift` opts out of LLVM, and unavailable LLVM tools can also cause a fallback. This validation change does not rerun or change the historical results below.

## main at de7f94d1 after the list, string, probe and repeated fixes (2026-11-23)

linux/amd64, four shared vCPUs, Go 1.24.7, rustc 1.99.1, gcc `-O2`, `ms` Release build with LLVM built from the C compiler (`cmake --preset ci`); minimum of 9 rotating runs, microseconds. Changes since the previous section: `String.slice` and `String.view` inline (#6628), `Int`- and `String`-key map and set probes read inline (#6624, #6634), `List.repeated` as the bulk native (#6640, `stencil_1000_20` 1169M to 941M instructions). A first run on this machine right after boot was 30% noisier; the table is the second run.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | c us | c / go | c-ms us | c-ms / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 45648 | 25794 | 0.57x | 24765 | 0.54x | 23789 | 0.52x | 20379 | 0.45x | 24254 | 0.53x | 1.04x | 1.08x |
| nbody_200k | 7907 | 6774 | 0.86x | 5202 | 0.66x | 5226 | 0.66x | 6413 | 0.81x | 6694 | 0.85x | 1.30x | 1.30x |
| life_128x128_50 | 44249 | 3099 | 0.07x | 2658 | 0.06x | 2819 | 0.06x | 25675 | 0.58x | 38133 | 0.86x | 1.17x | 1.10x |
| matmul_200 | 9016 | 5892 | 0.65x | 5525 | 0.61x | 5811 | 0.64x | 3466 | 0.38x | 10055 | 1.12x | 1.07x | 1.01x |
| trees_d16_x20 | 32143 | 27874 | 0.87x | 26373 | 0.82x | 24838 | 0.77x | 20676 | 0.64x | 20699 | 0.64x | 1.06x | 1.12x |
| collatz_1M | 220331 | 189534 | 0.86x | 139910 | 0.63x | 220662 | 1.00x | 180208 | 0.82x | 254319 | 1.15x | 1.35x | 0.86x |
| map_count_2M | 18908 | 40316 | 2.13x | 18171 | 0.96x | 19281 | 1.02x | n/a | n/a | 12747 | 0.67x | 2.22x | 2.09x |
| mandel_400 | 11564 | 11041 | 0.95x | 10854 | 0.94x | 11202 | 0.97x | 11399 | 0.99x | 11563 | 1.00x | 1.02x | 0.99x |
| particles_1k_5k | 5294 | 2944 | 0.56x | 3049 | 0.58x | 3048 | 0.58x | 3729 | 0.70x | 4032 | 0.76x | 0.97x | 0.97x |
| vm_5M | 50663 | 50685 | 1.00x | 40185 | 0.79x | 36510 | 0.72x | 45965 | 0.91x | 65940 | 1.30x | 1.26x | 1.39x |
| expr_d20_x20 | 399569 | 320376 | 0.80x | 83560 | 0.21x | 316473 | 0.79x | 279681 | 0.70x | 640878 | 1.60x | 3.83x | 1.01x |
| closures_20M | 38065 | 47053 | 1.24x | 31196 | 0.82x | 34548 | 0.91x | 72177 | 1.90x | 133951 | 3.52x | 1.51x | 1.36x |
| stencil_1000_20 | 46390 | 44936 | 0.97x | 35434 | 0.76x | 38572 | 0.83x | 26912 | 0.58x | 65290 | 1.41x | 1.27x | 1.16x |

Gaps against checked Rust, widest first: `map_count_2M` 2.1x (the `Map.update` read-then-insert is two probes where Rust's entry API is one; `ms_map_probe` is 60% of its 815M instructions), `closures_20M` 1.36x, `vm_5M` 1.39x, `nbody_200k` 1.30x, `trees_d16_x20` 1.12x, `stencil_1000_20` 1.16x. `expr_d20_x20` is 1.01x against checked Rust; the unchecked column folds a loop-invariant `eval`. Against Go `map_count_2M` (2.13x) and `closures_20M` (1.24x) are the two kernels where Manuscript is slower.

## main at 48f9cccf after the C-compiler fixes (2026-11-23)

linux/amd64, four shared vCPUs, Go, rustc and gcc `-O2` as on 2026-11-18, `ms` Release build with LLVM built from the C compiler (`cmake --preset ci`); minimum of 5 rotating runs, microseconds. The first C-compiler run of this suite had `closures_20M` at 194 ms, `map_count_2M` at 53 ms, `stencil_1000_20` at 159 ms and `vm_5M` at 108 ms. Fixes since: cleanup entries kept across a take and refill (#6584), `Map.update` with one read probe (#6590), `StringBuilder.append` in MIR and a one-pass shrinking replace (#6595), a TBAA class for list headers in slots (#6600), `List.pop` in line (#6605). `sieve_5M` varied between 27 and 62 ms in the rotating run on this shared machine; alone it takes 27 to 32 ms.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | c us | c / go | c-ms us | c-ms / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 52693 | 62478 | 1.19x | 25977 | 0.49x | 24810 | 0.47x | 24522 | 0.47x | 24668 | 0.47x | 2.41x | 2.52x |
| nbody_200k | 7989 | 6757 | 0.85x | 5232 | 0.65x | 5240 | 0.66x | 6432 | 0.81x | 6897 | 0.86x | 1.29x | 1.29x |
| life_128x128_50 | 45689 | 3121 | 0.07x | 2717 | 0.06x | 2890 | 0.06x | 26091 | 0.57x | 38700 | 0.85x | 1.15x | 1.08x |
| matmul_200 | 9579 | 6485 | 0.68x | 5664 | 0.59x | 5797 | 0.61x | 3602 | 0.38x | 10288 | 1.07x | 1.14x | 1.12x |
| trees_d16_x20 | 34903 | 30634 | 0.88x | 27298 | 0.78x | 25642 | 0.73x | 24640 | 0.71x | 20365 | 0.58x | 1.12x | 1.19x |
| collatz_1M | 221238 | 190435 | 0.86x | 143845 | 0.65x | 220579 | 1.00x | 183055 | 0.83x | 253517 | 1.15x | 1.32x | 0.86x |
| map_count_2M | 18917 | 45559 | 2.41x | 18486 | 0.98x | 19492 | 1.03x | n/a | n/a | 13111 | 0.69x | 2.46x | 2.34x |
| mandel_400 | 11580 | 11105 | 0.96x | 11111 | 0.96x | 11547 | 1.00x | 11380 | 0.98x | 11072 | 0.96x | 1.00x | 0.96x |
| particles_1k_5k | 5295 | 3102 | 0.59x | 3089 | 0.58x | 3101 | 0.59x | 3902 | 0.74x | 3886 | 0.73x | 1.00x | 1.00x |
| vm_5M | 51207 | 51083 | 1.00x | 40449 | 0.79x | 36854 | 0.72x | 46968 | 0.92x | 64922 | 1.27x | 1.26x | 1.39x |
| expr_d20_x20 | 480973 | 402346 | 0.84x | 91997 | 0.19x | 383930 | 0.80x | 375077 | 0.78x | 690627 | 1.44x | 4.37x | 1.05x |
| closures_20M | 38329 | 47585 | 1.24x | 33332 | 0.87x | 36111 | 0.94x | 70136 | 1.83x | 142564 | 3.72x | 1.43x | 1.32x |
| stencil_1000_20 | 46599 | 84589 | 1.82x | 37640 | 0.81x | 42365 | 0.91x | 27353 | 0.59x | 65864 | 1.41x | 2.25x | 2.00x |

## main at 113a7fa5 plus the new kernels (2026-11-18)

linux/amd64, four shared vCPUs, Go 1.24.7, rustc 1.99.1, gcc `-O2`, `ms` Release build with LLVM; minimum of 3 rotating runs, microseconds. Six kernels added for generated-code quality: `mandel_400` (small records returned by value), `particles_1k_5k` (list of records updated in place), `vm_5M` (enum `match` bytecode loop over a list used as a stack), `expr_d20_x20` (boxed enum tree, 2^20 nodes), `closures_20M` (a captured closure and a map/filter/sum chain) and `stencil_1000_20` (four-neighbour 2D stencil on a flat list). Every version prints the same checksum. `c-ms` is the checked C (overflow, bounds, poll). Rust unchecked folds the loop-invariant `eval` in `expr`, so compare that kernel against `rust-checked`.

| kernel | go us | ms us | rust-checked us | c us | c-ms us | ms / rust-checked | ms / c-ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| mandel_400 | 11294 | 10671 | 10969 | 10871 | 11005 | 0.97x | 0.97x |
| particles_1k_5k | 5293 | 2917 | 2923 | 4051 | 3844 | 1.00x | 0.76x |
| vm_5M | 50016 | 48861 | 34953 | 45030 | 63824 | 1.40x | 0.77x |
| expr_d20_x20 | 353560 | 392662 | 313456 | 268429 | 622836 | 1.25x | 0.63x |
| closures_20M | 36112 | 21011 | 31772 | 70003 | 131918 | 0.66x | 0.16x |
| stencil_1000_20 | 44503 | 41876 | 38621 | 27345 | 63463 | 1.08x | 0.66x |

The `c-ms` column pays a poll on every loop back edge, which the Manuscript backends do not, so it is slower than plain C by design. Gaps against checked Rust: the bytecode loop (1.40x) and the expression tree (1.25x). `ms build` with `MS_BACKEND=cranelift` runs these kernels 1.1x to 3x slower than LLVM (stencil 1.9x, vm 1.9x, by instruction count); Cranelift is not held to C parity.

## main at b4b25a2b (2026-11-18)

linux/amd64, four shared vCPUs, Go 1.24.7, rustc 1.99.1, gcc `-O2`, `ms` Release build with LLVM; minimum of 5 rotating runs, microseconds. `MS=./target/release/ms GO=go ms run bench/perf/tools/kernels.ms -- kernels 5`.

| kernel | go us | ms us | ms / go | rust us | rust-checked us | c us | c-ms us | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 63083 | 27080 | 0.43x | 28608 | 30827 | 24860 | 31291 | 0.95x | 0.88x |
| nbody_200k | 7506 | 6813 | 0.91x | 6257 | 6270 | 7657 | 8294 | 1.09x | 1.09x |
| life_128x128_50 | 45965 | 3319 | 0.07x | 3271 | 3436 | 30771 | 46117 | 1.01x | 0.97x |
| matmul_200 | 11512 | 6966 | 0.61x | 6770 | 6795 | 4177 | 12138 | 1.03x | 1.03x |
| trees_d16_x20 | 42122 | 29394 | 0.70x | 31652 | 34426 | 26609 | 26433 | 0.93x | 0.85x |
| collatz_1M | 249759 | 241366 | 0.97x | 171885 | 260346 | 224808 | 297024 | 1.40x | 0.93x |
| map_count_2M | 22496 | 7311 | 0.32x | 22081 | 23036 | n/a | 15951 | 0.33x | 0.32x |

Against Rust with overflow checks, Manuscript is level or ahead on every kernel; the 1.2x to 1.3x gaps of 2026-10-25 on nbody and life are gone. The widest gap is nbody at 1.09x. collatz is 1.40x against unchecked Rust and 0.93x against checked Rust.

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
