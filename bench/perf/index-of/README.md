# `List[String].index_of`

`main.ms` and `main.rs` search a list of 2,000 strings (`item-number-0` to `item-number-1999`) for each of 20,000 keys and print the time of the search loop and a checksum (`ms run bench/perf/index-of/main.ms`; Rust: `iter().position`). Both build each key the same way before searching.

## 2026-11-14 (x86-64 Linux sandbox, 4 cores, release `ms`, base 346c70a5)

The string equality decision was a branchless chain of selects evaluated for every element. It is now a branch on the one xor that separates most pairs (other kind, length or inline bytes), then a branch on whether the tagged words are equal, in both backends.

| | before | after | Rust |
| --- | --- | --- | --- |
| instructions (callgrind, whole program) | 1,078M | 793M | 390M |
| search loop (min of 25) | 47.1 ms | 35.2 ms | about 19.5 ms (whole program) |

The remaining gap is the call to `msrt_string_eq` for each pair of one length with different blocks, about half of the pairs here.
