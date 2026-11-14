# Performance benchmark

How fast Manuscript is, compared with hand-written Go and Rust, Node's JSON, and across the standard library. This measures the compiler and runtime only; no agents are involved. For how well agents write programs in different languages, see [`bench/agent/`](../agent/README.md). The two never share results.

| Directory | Measures | Run | Results |
| --- | --- | --- | --- |
| [`stdlib/`](stdlib) | ns per operation for each standard-library case (Manuscript only) | `make stdlib-bench` | [`stdlib/results.md`](stdlib/results.md) |
| [`programs/`](programs) | the same pure-Manuscript programs against hand-written Go and Rust, as a ratio | `MS=./target/release/ms GO=go ms run bench/tools/programs.ms -- 7` | [`programs/results.md`](programs/results.md) |
| [`llvm-release.md`](llvm-release.md) | LLVM against Cranelift on all 31 benchmarks | see the page | [`llvm-release.md`](llvm-release.md) |
| [`kernels/`](kernels) | whole numeric and data-structure kernels (sieve, n-body, life, matmul, trees, collatz, Int map) against hand-written Go and Rust | `MS=./target/release/ms GO=go ms run bench/tools/kernels.ms -- kernels 5` | [`kernels/README.md`](kernels/README.md) |
| [`workloads/`](workloads) | ordinary agent-style programs (parsing, strings, maps, stdin) against Go and Rust on ~3 MB of input, outputs compared | `MS=./target/release/ms ms run bench/tools/workloads.ms -- 3` | [`workloads/results.md`](workloads/results.md) |
| [`suite/`](suite) | 23 whole programs by area (interpreters, graphs, allocation, numeric, abstraction, crypto, compression, parsing, regex, JSON, strings, concurrency, files, text and data) against Rust, Go, Node and C, outputs compared | `MS=./target/release/ms sh bench/perf/suite/run.sh 5` | [`suite/results.md`](suite/results.md) |
| [`datastructures/`](datastructures) | core List, Map, Set, String, Bytes, PriorityQueue and SortedMap operations against Go and Rust, ns per operation | `MS=./target/release/ms ms run bench/tools/datastructures.ms -- 5` | [`results.md`](datastructures/results.md) |
| [`element-types/`](element-types) | List, Map, Set, Deque, PriorityQueue, sort, Optional and Result over records, payload enums and generics against Rust | `MS=./target/release/ms sh bench/perf/element-types/run.sh 5` | [`README.md`](element-types/README.md) |
| [`sort-shapes/`](sort-shapes) | `sorted` and `sort` by a comparator over 1M plain and owning records with many and few distinct keys and nearly sorted input, against Rust | `MS=./target/release/ms sh bench/perf/sort-shapes/run.sh 7` | [`README.md`](sort-shapes/README.md) |
| [`codecs/`](codecs) | paired typed JSON Base64 and syntax-error loops with exact output validation | see the [protocol](codecs/README.md) | [2026-10-29](codecs/results-2026-10-29.md) |
| [`csv/`](csv) | `@std/csv` parse against the Rust `csv` crate on 5000 generated rows | `MS=./target/release/ms ms run bench/tools/cargo_vs_ms.ms -- csv` | [`csv/README.md`](csv/README.md) |
| [`csv-streams/`](csv-streams) | fragmented CSV record scaling, whole-chunk and malformed-input controls | see the [protocol](csv-streams/README.md) | [2026-11-10](csv-streams/README.md) |
| [`json/`](json) | `@std/json` parse and stringify against Node (V8) on twitter, canada and citm_catalog | `ms run bench/tools/json_bench.ms` | [`json/results.md`](json/results.md) |
| [`streams/`](streams) | stream pipelines (`map`, `lines`, `collect`) against the loops they replace, ns per item | see the [page](streams/README.md) | [`streams/README.md`](streams/README.md) |
| [`iface/`](iface) | ns per interface call: local, returned and passed values against a direct loop | see the [page](iface/README.md) | [`iface/README.md`](iface/README.md) |
| [`web/`](web) | the same HTTP server on Manuscript's standard library and Go's `net/http`: throughput, latency, memory, system calls, idle connections, file and DNS handlers | `sh bench/perf/web/run.sh 5` | [`web/results.md`](web/results.md) |
| [`tasks/`](tasks) | resident memory and page tables per parked promise task at 100k and 1M, spawn and cancel time | `ms run bench/perf/tasks/main.ms -- 1000000 sleep` | [`tasks/README.md`](tasks/README.md) |
| [`mailbox/`](mailbox) | ns per promise through the scheduler mailboxes (cross-thread start and event traffic) | `ms run bench/perf/mailbox/main.ms -- 100000 5` | [`mailbox/README.md`](mailbox/README.md) |
| [`promise-tree/`](promise-tree) | promise fan-out and one-promise-per-call fork trees at 1 and 4 threads | `MS_THREADS=4 ms run bench/perf/promise-tree/main.ms -- tree 36 5` | [`promise-tree/README.md`](promise-tree/README.md) |
| [`wait-all/`](wait-all) | large pending promise fan-in, jitter and immediate-work controls | see the [protocol](wait-all/README.md) | [2026-11-07](wait-all/README.md#2026-11-07) |

Latest refresh with Go and Rust comparisons for the docs: [`results-2026-11-05.md`](results-2026-11-05.md).

Latest generated-code gaps against Rust: [`codegen-2026-11-12.md`](codegen-2026-11-12.md).

Latest kernels against C with bounds checks: [`results-2026-11-09.md`](results-2026-11-09.md).

Latest `for_each` check: [`for-each-var-2026-11-06.md`](for-each-var-2026-11-06.md).

Latest perf bash: [`perf-bash-2026-11-09.md`](perf-bash-2026-11-09.md) (previous: [`perf-bash-2026-11-03.md`](perf-bash-2026-11-03.md)).

Latest Manuscript-only baseline for every suite: [`baseline-2026-10-28.md`](baseline-2026-10-28.md) (previous: [`baseline-2026-10-27.md`](baseline-2026-10-27.md)). Latest same-machine before/after: [`refcount-removal-2026-11-03.md`](refcount-removal-2026-11-03.md) (the refcount removal, three binaries, every suite).

Compare numbers only from the same machine; treat them as a profiling guide, not a pass/fail gate.

The Manuscript programs use the native Rust/Cranelift `ms`. The Go and Rust
baselines require separate `go` and `rustc` installations; kernels also need a C
compiler. Set `MS` and `GO` explicitly because the scripts retain legacy default
paths. The program comparison allows normal inlining and reports medians with
alternating execution order. Every sample must
produce the expected operation counts and checksum. To retain the input, binaries,
environment, and raw samples for inspection:

```sh
MS=./target/release/ms GO=go BENCH_OUTPUT=.artifacts/perf-programs ms run bench/tools/programs.ms -- 11
python3 -m unittest discover -s bench/perf/programs -p 'test_*.py'
```
