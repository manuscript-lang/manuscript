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

Run `MS=./ms sh bench/perf/competence/run.sh 7` (median of N, microseconds). Compare only runs from the same machine.

## Latest (2026-10-21)

linux/amd64, four cores, Go 1.24.7, rustc 1.99.1; median of 7, microseconds. `rust` is idiomatic Rust at `opt-level=3`; `rust-checked` is the same source with overflow checks on, matching Manuscript's semantics. "folded" means LLVM folded the loop to a constant, so no time is reported.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| call_fib_36 | 86285 | 115973 | 1.34x | 48820 | 0.57x | 92794 | 1.08x | 2.38x | 1.25x |
| dispatch_100M | 212249 | 265780 | 1.25x | 183479 | 0.86x | 186955 | 0.88x | 1.45x | 1.42x |
| closure_100M | 35554 | 90729 | 2.55x | 0 | folded | 72345 | 2.03x | folded | 1.25x |
| sort_1M | 215629 | 75530 | 0.35x | 40252 | 0.19x | 40223 | 0.19x | 1.88x | 1.88x |
| text_1M | 76588 | 83004 | 1.08x | 34861 | 0.46x | 33849 | 0.44x | 2.38x | 2.45x |
| strmap_10M | 159981 | 282057 | 1.76x | 238083 | 1.49x | 233666 | 1.46x | 1.18x | 1.21x |
| errors_50M | 78319 | 106615 | 1.36x | 31706 | 0.40x | 54708 | 0.70x | 3.36x | 1.95x |
| records_1M_x20 | 162676 | 260287 | 1.60x | 158435 | 0.97x | 148827 | 0.91x | 1.64x | 1.75x |
| grid2d_500x20 | 8274 | 17602 | 2.13x | 17257 | 2.09x | 16484 | 1.99x | 1.02x | 1.07x |
| struct_100M | 37095 | 73950 | 1.99x | 0 | folded | 0 | folded | folded | folded |
| stack_20M | 573130 | 81060 | 0.14x | 61806 | 0.11x | 64556 | 0.11x | 1.31x | 1.26x |
| optional_100M | 146312 | 153939 | 1.05x | 72776 | 0.50x | 103337 | 0.71x | 2.12x | 1.49x |
| set_2M | 89968 | 84528 | 0.94x | 73818 | 0.82x | 79778 | 0.89x | 1.15x | 1.06x |
| chars_1M | 514997 | 263121 | 0.51x | 0 | folded | 29417 | 0.06x | folded | 8.94x |

Manuscript is faster than Go on sort, stack, set and chars; within 1.25x on fib, dispatch, text and optional; and 1.4x to 2.6x slower on closure, strmap, errors, records, grid2d and struct. Against Rust with overflow checks it is slower on all but a tie on grid2d, from 1.1x (set) to 2.5x (text) and 8.9x on chars, where Rust iterates bytes without decoding.
