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
| call_fib_36 | 83956 | 78521 | 0.94x | 46237 | 0.55x | 80076 | 0.95x | 1.70x | 0.98x |
| dispatch_100M | 271557 | 202832 | 0.75x | 168734 | 0.62x | 162378 | 0.60x | 1.20x | 1.25x |
| closure_100M | 60883 | 30605 | 0.50x | 0 | folded | 94742 | 1.56x | folded | 0.32x |
| sort_1M | 237325 | 90073 | 0.38x | 51799 | 0.22x | 50791 | 0.21x | 1.74x | 1.77x |
| text_1M | 93242 | 41786 | 0.45x | 40867 | 0.44x | 43759 | 0.47x | 1.02x | 0.95x |
| strmap_10M | 234686 | 373563 | 1.59x | 299861 | 1.28x | 314420 | 1.34x | 1.25x | 1.19x |
| errors_50M | 108320 | 60962 | 0.56x | 39332 | 0.36x | 68522 | 0.63x | 1.55x | 0.89x |
| records_1M_x20 | 343329 | 265822 | 0.77x | 209559 | 0.61x | 232072 | 0.68x | 1.27x | 1.15x |
| grid2d_500x20 | 10260 | 15131 | 1.47x | 20275 | 1.98x | 22813 | 2.22x | 0.75x | 0.66x |
| struct_100M | 30535 | 0 | folded | 0 | folded | 0 | folded | folded | folded |
| stack_20M | 645869 | 90412 | 0.14x | 74206 | 0.11x | 70301 | 0.11x | 1.22x | 1.29x |
| optional_100M | 238762 | 122062 | 0.51x | 91899 | 0.38x | 128692 | 0.54x | 1.33x | 0.95x |
| set_2M | 143916 | 125116 | 0.87x | 109548 | 0.76x | 110699 | 0.77x | 1.14x | 1.13x |
| chars_1M | 732956 | 218194 | 0.30x | 0 | folded | 28645 | 0.04x | folded | 7.62x |

Release build with LLVM. Manuscript is faster than Go on 12 of 14 rows (struct folds to a constant) and 1.5x to 1.6x slower on strmap and grid2d. Against Rust with overflow checks it is within 1.3x on all rows except sort (1.8x), strmap (1.2x) and chars (7.6x, where Rust iterates bytes without decoding); text_1M is level since split loops no longer build a list.
