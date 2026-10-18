# Performance benchmark

How fast Manuscript is, compared with hand-written Go and across the standard library. This measures the compiler and runtime only; no agents are involved. For how well agents write programs in different languages, see [`agent-bench/`](../agent-bench/README.md). The two never share results.

| Directory | Measures | Run | Results |
| --- | --- | --- | --- |
| [`stdlib/`](stdlib) | ns per operation for each standard-library case (Manuscript only) | `make stdlib-bench` | [`stdlib/results.md`](stdlib/results.md) |
| [`programs/`](programs) | the same pure-Manuscript programs against hand-written Go, as a ratio | `MS=./ms sh perf-bench/programs/run.sh 7` | [`programs/results.md`](programs/results.md) |

Compare numbers only from the same machine; treat them as a profiling guide, not a pass/fail gate.
