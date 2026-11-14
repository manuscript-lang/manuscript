# MIR and translation survey, 2026-11-14

Revision `main` after #3870, direct LLVM emitter, `ms` built from this tree, shared 4 vCPU Linux VM, rustc 1.99.1 `-O` (overflow checks on for the kernels). Min of 5. Programs: `bench/perf/competence`, `bench/perf/kernels`, `bench/perf/engineering` and the agent-challenge workloads (`MS=./target/debug/ms ms run bench/tools/workloads.ms -- 3`, 3 MB of the largest hidden stdin).

## Where Manuscript still trails Rust

| program | ms / rust | what costs |
|---|---:|---|
| c16-maze-bfs | 2.20x | 16 bytes per `String` cell, page faults |
| c03-csv-group-sum | 1.89x | `split`, `slice`, `scalar_values` runtime calls |
| c13-inventory-orders | 1.67x | `Map.values()` deep copies, `String` compares |
| c14-dp-suite | 1.31x | lists grown by doubling (fixed below) |
| c09-ciphers | 1.30x | string runtime calls |
| nbody_200k | 1.30x | 7-float records through `get().clone()` and `set` |
| life_128x128_50 | 1.27x | already about 11 instructions per neighbor |
| matmul_200 | 1.12x | |

Every other competence and kernel program is at or ahead of Rust with overflow checks (0.3x to 1.0x).

Callgrind note: under valgrind the allocator reservation cannot be mapped and every block goes to glibc, which made `malloc` look like 40% of c13; lower `PAGES_SIZE` and `GROW_CHUNKS` locally first ([wiki](../../wiki/benchmarks-and-performance/callgrind-needs-a-smaller-allocator-reservation.md)).

## Change: a list literal with elements is sized by the loop that fills it

The `reserve` pass sized only an empty literal. `var cur = [0]` followed by `for j in ...: cur.append(...)` (the usual dynamic-programming row) still grew by doubling and reallocated about log2(n) times per row. The pass now also takes a literal with elements: it becomes the sized `list.new` plus one push per element.

c14-dp-suite (3 MB of input, 6 runs, ms): 697 to 985 ms before, 528 to 605 ms after; Rust 497 to 671 ms. Competence and kernels are unchanged within noise.
