# `List[String].index_of`

`main.ms` and `main.rs` search a list of 2,000 strings (`item-number-0` to `item-number-1999`) for each of 20,000 keys and print the time of the search loop and a checksum (`ms run bench/perf/index-of/main.ms`; Rust: `iter().position`). Both build each key the same way before searching.

## 2026-11-14 (x86-64 Linux sandbox, 4 cores, release `ms`, base 346c70a5)

The string equality decision was a branchless chain of selects evaluated for every element. It is now a branch on the one xor that separates most pairs (other kind, length or inline bytes), then a branch on whether the tagged words are equal, in both backends.

| | before | after | Rust |
| --- | --- | --- | --- |
| instructions (callgrind, whole program) | 1,078M | 793M | 390M |
| search loop (min of 25) | 47.1 ms | 35.2 ms | about 19.5 ms (whole program) |

Same day, second step: two blocks of one kind and length are now compared in place for 8 to 16 bytes (the first and last eight bytes cover every byte), in both backends. Only other lengths call `msrt_string_eq`, which cost about 50 instructions a call.

| | before | after | Rust |
| --- | --- | --- | --- |
| instructions (callgrind, whole program) | 793M | 503M | 390M |
| search loop (min of 25) | 30.3 ms | 16.3 ms | 16.0 ms |
