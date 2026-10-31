[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Consume library checksums and separate allocation phase from local cost

Verified: a returned checksum that the harness discards is not evidence that the work stayed observable. Consume each result with `keep` from `@std/bench.ms` so the work stays observable, and reject missing, duplicate, failed, or changed cases and operation counts on every trial (`compare_stdlib.py` validates all stdlib cases from `ms bench --json`). Changing an earlier allocating workload can move later allocation costs, so an apparent unrelated regression in a full-suite run may not reproduce when the same cases run repeatedly in separate focused processes. Keep both results and state the distinction; do not silently replace the full run.

Verified: an isolated improvement does not validate the composition with current main. Before accepting related runtime changes, compare the composed state against a matched current baseline with the same compiler, source, flags and output guards. When a composition regresses, preserve that run and compare baseline, each change alone and the combination; do not substitute the earlier isolated pass for integration evidence. The normalization rollback restores prior behavior after a material regression; its lost ASCII and early-limit gains remain documented.

Apply when: retaining a benchmark win or diagnosing a nominal unrelated slowdown.
Evidence: [stdlib validator](../../bench/perf/compare_stdlib.py), [program measurements](../../bench/perf/programs/results.md), [normalization attribution and rollback](../../bench/perf/string-normalization-rollback/README.md).
Verify: balanced process order, identical tool flags and inputs, no simultaneous CPU work, raw samples plus source and binary hashes, and focused controls for regressions. Identical instructions can vary when relocated across alignment boundaries; preserve assembly and reject arbitrary padding or lucky-placement tuning.

Verified: matching checksums among the rows that happen to be present cannot establish complete work. The kernel and competence wrappers check the producer before filtering its output, append a trial boundary only after success, and the shared reporter requires the suite's full kernel and version identities exactly once per trial and the requested trial count before printing any rows. A missing kernel in every version, duplicate row, failed producer with plausible output, or late checksum mismatch must fail without a partial comparison.
Evidence: [kernel reporter](../../bench/perf/table.py), [producer and evidence regressions](../../bench/perf/test_kernel_trials.py).
Verify: `python3 -m unittest discover -s bench/perf -p test_kernel_trials.py` exercises both actual shell runners with controlled producers and requires zero report output on failure.

Verified: a Python launcher's inherited high-water mark can dominate Linux `wait4` RSS for small child executables. Use a small native launcher that forks after its own exec for separate RSS trials; distinguish maximum single-process RSS in a waited process tree from simultaneous aggregate memory. Keep timing trials separate and label empty extraction caches separately from cold OS page caches.
Evidence: [isolated RSS helper](../../bench/perf/representative/rss.c), [measurement protocol](../../bench/perf/representative/README.md).
Verify: a trivial native program's reported RSS must not merely equal the Python launcher's RSS; retain the original raw measurements when correcting the measurement method.

---
Topics: [Performance](../topics/performance.md)
