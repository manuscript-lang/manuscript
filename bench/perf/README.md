# Performance benchmark

How fast Manuscript is, compared with hand-written Go and across the standard library. This measures the compiler and runtime only; no agents are involved. For how well agents write programs in different languages, see [`bench/agent/`](../agent/README.md). The two never share results.

| Directory | Measures | Run | Results |
| --- | --- | --- | --- |
| [`stdlib/`](stdlib) | ns per operation for each standard-library case (Manuscript only) | `make stdlib-bench` | [`stdlib/results.md`](stdlib/results.md) |
| [`programs/`](programs) | the same pure-Manuscript programs against hand-written Go, as a ratio | `MS=./ms sh bench/perf/programs/run.sh 7` | [`programs/results.md`](programs/results.md) |
| [`kernels/`](kernels) | whole numeric and data-structure kernels (sieve, n-body, life, matmul, trees, collatz, Int map) against hand-written Go | `MS=./ms sh bench/perf/kernels/run.sh 5` | [`kernels/README.md`](kernels/README.md) |

Compare numbers only from the same machine; treat them as a profiling guide, not a pass/fail gate.

The program comparison uses the pinned Go SDK for both languages, allows normal
inlining, and reports medians with alternating execution order. Every sample must
produce the expected operation counts and checksum. To retain the input, binaries,
environment, and raw samples for inspection:

```sh
BENCH_OUTPUT=.artifacts/perf-programs sh bench/perf/programs/run.sh 11
python3 -m unittest discover -s bench/perf/programs -p 'test_*.py'
```
