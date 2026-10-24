# Performance benchmark

How fast Manuscript is, compared with hand-written Go and Rust and across the standard library. This measures the compiler and runtime only; no agents are involved. For how well agents write programs in different languages, see [`bench/agent/`](../agent/README.md). The two never share results.

| Directory | Measures | Run | Results |
| --- | --- | --- | --- |
| [`stdlib/`](stdlib) | ns per operation for each standard-library case (Manuscript only) | `make stdlib-bench` | [`stdlib/results.md`](stdlib/results.md) |
| [`programs/`](programs) | the same pure-Manuscript programs against hand-written Go and Rust, as a ratio | `MS=./target/release/ms GO=go sh bench/perf/programs/run.sh 7` | [`programs/results.md`](programs/results.md) |
| [`llvm-release.md`](llvm-release.md) | LLVM against Cranelift on all 31 benchmarks | see the page | [`llvm-release.md`](llvm-release.md) |
| [`kernels/`](kernels) | whole numeric and data-structure kernels (sieve, n-body, life, matmul, trees, collatz, Int map) against hand-written Go and Rust | `MS=./target/release/ms GO=go sh bench/perf/kernels/run.sh 5` | [`kernels/README.md`](kernels/README.md) |
| [`workloads/`](workloads) | ordinary agent-style programs (parsing, strings, maps, stdin) against Go and Rust on ~3 MB of input, outputs compared | `MS=./target/release/ms sh bench/perf/workloads/run.sh 3` | printed table |
| [`json/`](json) | `@std/json` parse and stringify against Node (V8) on twitter, canada and citm_catalog | `sh bench/perf/json/run.sh` | printed table |
| [`web/`](web) | the same HTTP server on Manuscript's standard library and Go's `net/http`: throughput, latency, memory, system calls, idle connections, file and DNS handlers | `sh bench/perf/web/run.sh 5` | [`web/results.md`](web/results.md) |

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
