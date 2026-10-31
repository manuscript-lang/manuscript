[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Consume library checksums and separate allocation phase from local cost

Verified: a returned checksum that the harness discards is not evidence that the work stayed observable. Consume each result with `keep` from `@std/bench.ms` so the work stays observable, and reject missing, duplicate, failed, or changed cases and operation counts on every trial (`compare_stdlib.py` validates all stdlib cases from `ms bench --json`).

Apply when: retaining a benchmark win or diagnosing a nominal unrelated slowdown.
Evidence: [stdlib validator](../../bench/tools/compare_stdlib.ms), [program measurements](../../bench/perf/programs/results.md), [normalization attribution and rollback](../../bench/perf/string-normalization-rollback/README.md).
Evidence: [kernel reporter](../../bench/tools/kernels_table.ms), [producer and evidence regressions](../../bench/tools/kernels_table_test.ms).
Evidence: [isolated RSS helper](../../bench/perf/representative/rss.c), [measurement protocol](../../bench/perf/representative/README.md).
Verify: balanced process order, identical tool flags and inputs, no simultaneous CPU work, raw samples plus source and binary hashes, and focused controls for regressions. Identical instructions can vary when relocated across alignment boundaries; preserve assembly and reject arbitrary padding or lucky-placement tuning.
Verify: `python3 -m unittest discover -s bench/perf -p test_kernel_trials.py` exercises both actual shell runners with controlled producers and requires zero report output on failure.
Verify: a trivial native program's reported RSS must not merely equal the Python launcher's RSS; retain the original raw measurements when correcting the measurement method.
