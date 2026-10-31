# Competence kernels

Ordinary programs grouped by what a general-purpose language must do well, each compared with idiomatic Go and checked for an identical checksum. Optimize for these competences, not for one program.

| Kernel | Competence |
| --- | --- |
| `call_fib_36` | recursive calls |
| `dispatch_100M` | interface method dispatch |
| `closure_100M` | calling a captured closure |
| `sort_1M` | sorting with a comparator |
| `text_1M` | string building, splitting, integer parsing |
| `strmap_10M` | string-keyed map updates |
| `errors_50M` | `Result` propagation with `try` |
| `records_1M_x20` | iterating a list of records |
| `grid2d_500x20` | nested list indexing |
| `struct_100M` | small record update in a loop |
| `stack_20M` | list used as a stack (`append`, `pop`) |
| `optional_100M` | `Optional` construction and `if let` |
| `set_2M` | `Set[Int]` insert and lookup |
| `chars_1M` | iterating the characters of a string |

Run `MS=./ms ms run bench/tools/kernels.ms -- competence 7` (median of N, microseconds). Compare only runs from the same machine.

## Latest (2026-10-25)

`main` at c1b81215; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1; median of 5, microseconds. `rust` is idiomatic Rust at `opt-level=3`; `rust-checked` is the same source with overflow checks on, matching Manuscript's semantics. "folded" means LLVM folded the loop to a constant, so no time is reported. The Manuscript source constructs interface values directly (`[Sq(3), Rect(2, 5)]` typed as `List[Shape]`), as the language now requires.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| call_fib_36 | 77803 | 88524 | 1.14x | 43971 | 0.57x | 83680 | 1.08x | 2.01x | 1.06x |
| dispatch_100M | 197841 | 163173 | 0.82x | 163741 | 0.83x | 164419 | 0.83x | 1.00x | 0.99x |
| closure_100M | 32945 | 65674 | 1.99x | 0 | folded | 66027 | 2.00x | folded | 0.99x |
| sort_1M | 211240 | 23504 | 0.11x | 33097 | 0.16x | 34092 | 0.16x | 0.71x | 0.69x |
| text_1M | 57752 | 40082 | 0.69x | 30112 | 0.52x | 31075 | 0.54x | 1.33x | 1.29x |
| strmap_10M | 140826 | 103204 | 0.73x | 206531 | 1.47x | 207794 | 1.48x | 0.50x | 0.50x |
| errors_50M | 69882 | 36490 | 0.52x | 26939 | 0.39x | 50084 | 0.72x | 1.35x | 0.73x |
| records_1M_x20 | 162656 | 83228 | 0.51x | 117987 | 0.73x | 123193 | 0.76x | 0.71x | 0.68x |
| grid2d_500x20 | 7615 | 6922 | 0.91x | 13737 | 1.80x | 14796 | 1.94x | 0.50x | 0.47x |
| struct_100M | 32710 | 0 | folded | 0 | folded | 0 | folded | folded | folded |
| stack_20M | 484333 | 50431 | 0.10x | 46185 | 0.10x | 52687 | 0.11x | 1.09x | 0.96x |
| optional_100M | 128553 | 66126 | 0.51x | 64871 | 0.50x | 94718 | 0.74x | 1.02x | 0.70x |
| set_2M | 78654 | 67831 | 0.86x | 67511 | 0.86x | 68701 | 0.87x | 1.00x | 0.99x |
| chars_1M | 395822 | 30724 | 0.08x | 0 | folded | 26803 | 0.07x | folded | 1.15x |

Manuscript is faster than Go on 11 of 14 rows (struct folds to a constant) and slower on call_fib (1.14x) and closure (2.0x, where Go's time halved against the previous run while Manuscript's did not move; read it as a Go gain, not a regression). Against Rust with overflow checks it is level or ahead on 9 rows, within 1.35x on text, errors and chars, and 1.06x on call_fib.

## 2026-10-22

linux/amd64, four cores, Go 1.24.7, rustc 1.99.1; median of 7, microseconds. `rust` is idiomatic Rust at `opt-level=3`; `rust-checked` is the same source with overflow checks on, matching Manuscript's semantics. "folded" means LLVM folded the loop to a constant, so no time is reported.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| call_fib_36 | 84551 | 92670 | 1.10x | 44511 | 0.53x | 68586 | 0.81x | 2.08x | 1.35x |
| dispatch_100M | 232042 | 170753 | 0.74x | 174107 | 0.75x | 182810 | 0.79x | 0.98x | 0.93x |
| closure_100M | 61970 | 65731 | 1.06x | 0 | folded | 52508 | 0.85x | folded | 1.25x |
| sort_1M | 225363 | 30961 | 0.14x | 39365 | 0.17x | 41848 | 0.19x | 0.79x | 0.74x |
| text_1M | 69373 | 30979 | 0.45x | 31092 | 0.45x | 30317 | 0.44x | 1.00x | 1.02x |
| strmap_10M | 197831 | 141475 | 0.72x | 267240 | 1.35x | 242933 | 1.23x | 0.53x | 0.58x |
| errors_50M | 92269 | 52926 | 0.57x | 35257 | 0.38x | 70428 | 0.76x | 1.50x | 0.75x |
| records_1M_x20 | 226614 | 204909 | 0.90x | 164823 | 0.73x | 170816 | 0.75x | 1.24x | 1.20x |
| grid2d_500x20 | 10383 | 7822 | 0.75x | 15808 | 1.52x | 15795 | 1.52x | 0.49x | 0.50x |
| struct_100M | 30787 | 0 | folded | 0 | folded | 0 | folded | folded | folded |
| stack_20M | 497900 | 55250 | 0.11x | 53757 | 0.11x | 55819 | 0.11x | 1.03x | 0.99x |
| optional_100M | 129321 | 85893 | 0.66x | 84835 | 0.66x | 91269 | 0.71x | 1.01x | 0.94x |
| set_2M | 103182 | 82620 | 0.80x | 86044 | 0.83x | 85464 | 0.83x | 0.96x | 0.97x |
| chars_1M | 509571 | 52816 | 0.10x | 0 | folded | 20826 | 0.04x | folded | 2.54x |

Release build with LLVM, after the libc-replacement memory routines, the arena allocator for the standard library, in-place `String.chars` scanning, and the integer sort for plain `Int` comparators. Manuscript is faster than Go on 12 of 14 rows (struct folds to a constant) and slower on call_fib (1.1x) and closure (1.1x). Against Rust with overflow checks it is within 1.25x on every row except call_fib (1.35x) and chars (2.5x, where Rust iterates bytes without decoding), and ahead on dispatch, sort, errors, strmap, grid2d, optional and set. Sort and strmap lead because a plain `Int` comparator calls the runtime's integer sort and the standard-library allocator is the arena. Wall-clock on this shared machine moves by 10% or more between runs, so read ratios within about 10% as ties.
