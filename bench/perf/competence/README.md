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
| call_fib_36 | 83659 | 110954 | 1.33x | 48091 | 0.57x | 89343 | 1.07x | 2.31x | 1.24x |
| dispatch_100M | 223677 | 214761 | 0.96x | 177804 | 0.79x | 177285 | 0.79x | 1.21x | 1.21x |
| closure_100M | 35876 | 93758 | 2.61x | 0 | folded | 71369 | 1.99x | folded | 1.31x |
| sort_1M | 223095 | 155287 | 0.70x | 36806 | 0.16x | 37415 | 0.17x | 4.22x | 4.15x |
| text_1M | 61555 | 107583 | 1.75x | 32651 | 0.53x | 33257 | 0.54x | 3.29x | 3.23x |
| strmap_10M | 158281 | 262453 | 1.66x | 222492 | 1.41x | 222098 | 1.40x | 1.18x | 1.18x |
| errors_50M | 76082 | 108713 | 1.43x | 29227 | 0.38x | 54053 | 0.71x | 3.72x | 2.01x |
| records_1M_x20 | 149539 | 188054 | 1.26x | 132893 | 0.89x | 136474 | 0.91x | 1.42x | 1.38x |
| grid2d_500x20 | 8195 | 13863 | 1.69x | 14950 | 1.82x | 16003 | 1.95x | 0.93x | 0.87x |
| struct_100M | 35927 | 70781 | 1.97x | 0 | folded | 0 | folded | folded | folded |
| stack_20M | 312078 | 82004 | 0.26x | 53822 | 0.17x | 59153 | 0.19x | 1.52x | 1.39x |
| optional_100M | 141855 | 186891 | 1.32x | 70608 | 0.50x | 103020 | 0.73x | 2.65x | 1.81x |
| set_2M | 88286 | 82373 | 0.93x | 73175 | 0.83x | 73276 | 0.83x | 1.13x | 1.12x |
| chars_1M | 429855 | 539276 | 1.25x | 0 | folded | 28780 | 0.07x | folded | 18.74x |

Manuscript is faster than Go on dispatch, sort, stack and set; within 1.45x on fib, records, errors, optional and chars; and 1.7x to 2.6x slower on closure, text, strmap, grid2d and struct. Against Rust with overflow checks it is slower on all but grid2d, from 1.1x (set) to 4.2x (sort, text) and 19x on chars, where Rust iterates bytes without decoding.
