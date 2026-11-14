# General benchmark suite

One suite of whole programs, the kind a general-purpose language gets used for, each written once per language and compared on wall time. It replaces the separate `engineering/` directory and adds programs for the areas that had no coverage.

Each program lives in its own directory with the same program as `main.ms` (Manuscript, written in the one-owner style), `main.rs` (Rust, `std` only), `main.go`, `main.js` (Node) and, for the text tasks, `main.c`. A missing language shows as `-`. Every sample's output is compared byte for byte with the Rust output (Go where Rust has no standard-library equivalent: `regex`, `jsonrt`).

```sh
MS=./target/release/ms sh bench/perf/suite/run.sh 5            # every program, min of 5
MS=./target/release/ms sh bench/perf/suite/run.sh 5 lz graph   # chosen programs
```

Times are the minimum wall time in ms of N samples with process start and output included and compilation excluded. `SCALE=2` doubles the generated input. `BENCH_OUTPUT=<dir>` keeps inputs, binaries and outputs. Compare numbers only from one machine, and add dated sections to [`results.md`](results.md) rather than editing old ones. This suite is not part of pull request CI; it runs by hand, on `main` and on the bench schedule.

| Program | Area | What it stresses |
| --- | --- | --- |
| `interp` | interpreters | enum dispatch in a bytecode VM, a list as the stack |
| `graph` | graphs | adjacency lists, BFS with a deque, Dijkstra with a priority queue, union-find |
| `objgraph` | allocation | boxed binary search tree, short-lived tree churn, a million-node linked list |
| `sim` | numeric | Float stencil on a flat grid, Mandelbrot, `sqrt` loop |
| `dispatch` | abstraction | interface calls over a mixed list, a chain of closures, a generic container |
| `hashing` | crypto | hand-written CRC-32 and SHA-256: shifts, masks, 32-bit wraparound |
| `lz` | compression | LZ77 round trip over byte lists, hash table as a flat list |
| `exprparse` | parsing | tokenizer, recursive-descent parser and evaluator over strings and recursive enums |
| `regex` | text | `@std/regex` against Go `regexp` and JS `RegExp` |
| `jsonrt` | data formats | generic JSON parse, tree walk, stringify against Go and Node |
| `strings` | text | interpolation, case, trim, replace, search, padding, sorting strings |
| `concat` | text | appending to one long string with `+=`, and `join` |
| `workers` | concurrency | promises over CPU work, then 100k small promises, against threads, goroutines and worker threads |
| `logstats`, `csvgroup`, `wordfreq`, `sortrecords`, `grep`, `dedupe`, `report` | text and data | stdin programs on 15 to 40 MB of generated input, against C and Rust |
| `jsonsum` | data formats | typed `parse[List[Rec]]` against a hand-written tree parser |
| `treegrep`, `pargroup` | files | walking a directory tree, reading files on 4 workers |

Not covered here, with their own suites: HTTP server and client ([`../web/`](../web)), parked-task memory ([`../tasks/`](../tasks)), numeric and data-structure kernels ([`../kernels/`](../kernels)), per-operation standard-library cost ([`../stdlib/`](../stdlib)). Older engineering-task results are in [`results/engineering-history.md`](results/engineering-history.md).

`gen.ms` writes the deterministic inputs for the stdin and file programs. `common.h` is the C control's insertion-ordered table.
