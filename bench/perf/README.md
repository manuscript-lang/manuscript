# Performance benchmark

How fast Manuscript is, compared with hand-written Go and Rust, Node's JSON, and across the standard library. This measures the compiler and runtime only; no agents are involved. For how well agents write programs in different languages, see [`bench/agent/`](../agent/README.md). The two never share results.

| Directory | Measures | Run | Results |
| --- | --- | --- | --- |
| [`stdlib/`](stdlib) | ns per operation for each standard-library case (Manuscript only) | `make stdlib-bench` | [`stdlib/results.md`](stdlib/results.md) |
| [`programs/`](programs) | the same pure-Manuscript programs against hand-written Go and Rust, as a ratio | `MS=./target/release/ms GO=go sh bench/perf/programs/run.sh 7` | [`programs/results.md`](programs/results.md) |
| [`llvm-release.md`](llvm-release.md) | LLVM against Cranelift on all 31 benchmarks | see the page | [`llvm-release.md`](llvm-release.md) |
| [`kernels/`](kernels) | whole numeric and data-structure kernels (sieve, n-body, life, matmul, trees, collatz, Int map) against hand-written Go and Rust | `MS=./target/release/ms GO=go sh bench/perf/kernels/run.sh 5` | [`kernels/README.md`](kernels/README.md) |
| [`workloads/`](workloads) | ordinary agent-style programs (parsing, strings, maps, stdin) against Go and Rust on ~3 MB of input, outputs compared | `MS=./target/release/ms sh bench/perf/workloads/run.sh 3` | [`workloads/results.md`](workloads/results.md) |
| [`datastructures/`](datastructures) | core List, Map, Set, String, Bytes, PriorityQueue and SortedMap operations against Go and Rust, ns per operation | `MS=./target/release/ms sh bench/perf/datastructures/run.sh 5` | [`results.md`](datastructures/results.md) |
| [`codecs/`](codecs) | paired typed JSON Base64 decode loops with byte-for-byte validation | see the [protocol](codecs/README.md) | [2026-10-29](codecs/results-2026-10-29.md) |
| [`csv/`](csv) | `@std/csv` parse against the Rust `csv` crate on 5000 generated rows | `MS=./target/release/ms sh bench/perf/csv/run.sh` | [`csv/README.md`](csv/README.md) |
| [`json/`](json) | `@std/json` parse and stringify against Node (V8) on twitter, canada and citm_catalog | `sh bench/perf/json/run.sh` | [`json/results.md`](json/results.md) |
| [`workers/`](workers) | eight CPU-bound jobs over 1, 2 and 4 `WorkerGroup` workers | `MS=./target/release/ms sh bench/perf/workers/run.sh 3` | [`workers/README.md`](workers/README.md) |
| [`web/`](web) | the same HTTP server on Manuscript's standard library and Go's `net/http`: throughput, latency, memory, system calls, idle connections, file and DNS handlers | `sh bench/perf/web/run.sh 5` | [`web/results.md`](web/results.md) |

Latest Manuscript-only baseline for every suite: [`baseline-2026-10-28.md`](baseline-2026-10-28.md) (previous: [`baseline-2026-10-27.md`](baseline-2026-10-27.md)).

Compare numbers only from the same machine; treat them as a profiling guide, not a pass/fail gate.

The Manuscript programs use the native Rust/Cranelift `ms`. The Go and Rust
baselines require separate `go` and `rustc` installations; kernels also need a C
compiler. Set `MS` and `GO` explicitly because the scripts retain legacy default
paths. The program comparison allows normal inlining and reports medians with
alternating execution order. Every sample must
produce the expected operation counts and checksum. To retain the input, binaries,
environment, and raw samples for inspection:

```sh
MS=./target/release/ms GO=go BENCH_OUTPUT=.artifacts/perf-programs sh bench/perf/programs/run.sh 11
python3 -m unittest discover -s bench/perf/programs -p 'test_*.py'
```
