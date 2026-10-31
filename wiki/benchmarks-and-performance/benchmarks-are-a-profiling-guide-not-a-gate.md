[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Benchmarks are a profiling guide, not a gate

Verified: results are only comparable on one machine and revision; record the commit and machine with the table, as the result files do. Use best-of-N or median of repeats, alternate before/after order, exclude build and warm-up, and require a deterministic checksum so a wrong program cannot look fast. Do not add a CI threshold.

Verified: validate parser benchmark inputs before timing. Ignoring a parse error measures an early exit while counting the entire file as parsed bytes. [`ms-syntax bench` regressions](../../crates/ms-syntax/tests/bench_inputs.rs) require a diagnostic and nonzero exit instead of throughput for malformed inputs.

Apply when: claiming a speedup or regression.
Evidence: [program results](../../bench/perf/programs/results.md).
Verify: before/after run on the same host with `make stdlib-bench BENCHREPEATS=5 BENCHFILTER=<case>` or `bench/perf/programs/run.sh 7`.
