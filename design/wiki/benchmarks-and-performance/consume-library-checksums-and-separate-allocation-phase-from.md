[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Consume library checksums and separate allocation phase from local cost

Verified: a returned checksum that the harness discards is not evidence that the work stayed observable. End each bench body with the result as its last statement (the harness keeps it) so the work stays observable, and reject missing, duplicate, failed, or changed cases and operation counts on every trial (`compare_stdlib.py` validates all stdlib cases from `ms bench --json`).

Apply when: retaining a benchmark win or diagnosing a nominal unrelated slowdown.
Evidence: [stdlib validator](../../../bench/perf/tools/compare_stdlib.ms), [program measurements](../../../bench/perf/results.md#programs), [normalization attribution and rollback](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/string-normalization-rollback/README.md).
Evidence: [kernel reporter](../../../bench/perf/tools/kernels_table.ms), [producer and evidence regressions](../../../bench/perf/tools/kernels_table_test.ms).
Evidence: [isolated RSS helper](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/representative/rss.c), [measurement protocol](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/representative/README.md).
Verify: balanced process order, identical tool flags and inputs, no simultaneous CPU work, raw samples plus source and binary hashes, and focused controls for regressions. Identical instructions can vary when relocated across alignment boundaries; preserve assembly and reject arbitrary padding or lucky-placement tuning.
Verify: `python3 -m unittest discover -s bench/perf -p test_kernel_trials.py` exercises both actual shell runners with controlled producers and requires zero report output on failure.
Verify: a trivial native program's reported RSS must not merely equal the Python launcher's RSS; retain the original raw measurements when correcting the measurement method.

Codec comparisons distinguish exact-capacity C from growing-buffer C, retain complete output checks, and include empty/tail inputs; faster byte-list construction is not evidence of lower peak memory. See [encoding capacity controls](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/codec-encoding/README.md).
