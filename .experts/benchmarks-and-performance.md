# Benchmarks and performance lessons

Two unrelated benchmarks exist; never mix their results. Lowering and runtime trade-offs are in [compiler.md](compiler.md) and [runtime.md](runtime.md).

### Performance and agent benchmarks are separate

Decision: `bench/perf/` measures compiler/runtime speed (`stdlib/` ns per operation, `programs/` and `kernels/` whole-program comparisons); `bench/agent/` measures how well agents solve the same challenges in TypeScript, Go, Rust, and Manuscript (hidden tests, tokens, turns, time, cost). Each README points at the other, and their results never share a table. Keep agent-bench transcripts out of git.

Apply when: reporting numbers, adding a benchmark, or moving either directory.
Evidence: [bench/perf](../bench/perf/README.md), [bench/agent](../bench/agent/README.md), [maintenance skill](../skills/repository-maintenance/SKILL.md).
Verify: `make agent-bench-check` (oracle plus unit tests) passes; every path in the Makefile, docs, and skills resolves after a move (`make repo-check`).

### Benchmarks are a profiling guide, not a gate

Verified: results are only comparable on one machine and revision; record the commit and machine with the table, as the result files do. Use best-of-N or median of repeats, alternate before/after order, exclude build and warm-up, and require a deterministic checksum so a wrong program cannot look fast. Do not add a CI threshold.

Apply when: claiming a speedup or regression.
Evidence: [program results](../bench/perf/programs/results.md).
Verify: before/after run on the same host with `make stdlib-bench BENCHREPEATS=5 BENCHFILTER=<case>` or `bench/perf/programs/run.sh 7`.

### A win needs a baseline comparison, not just a smaller number

Verified: keep the raw hand-written baseline (the C controls in `bench/perf/kernels/c`) and distinguish logical work elimination from faster execution of each source operation. Checked arithmetic is language behavior, so a control that omits overflow checks diagnoses cost but does not change the baseline. Reject a candidate that moves a material gap into another workload, and retain its measurements. Prefer removing unobservable work and allocations over placement tuning.

Apply when: optimizing a helper, a lowering path, or a runtime routine.
Evidence: [program results](../bench/perf/programs/results.md), [kernel baselines](../bench/perf/kernels/README.md).
Verify: time and allocation counts before and after on one machine; behavior tests unchanged.

### Consume library checksums and separate allocation phase from local cost

Verified: a returned checksum that the harness discards is not evidence that the work stayed observable. Print each checksum after stopping the clock and reject missing, duplicate, or changed counts/checksums on every trial (`compare_stdlib.py` validates all stdlib cases). Changing an earlier allocating workload can move later allocation costs, so an apparent unrelated regression in a full-suite run may not reproduce when the same cases run repeatedly in separate focused processes. Keep both results and state the distinction; do not silently replace the full run.

Apply when: retaining a benchmark win or diagnosing a nominal unrelated slowdown.
Evidence: [stdlib validator](../bench/perf/compare_stdlib.py), [program measurements](../bench/perf/programs/results.md).
Verify: balanced process order, identical tool flags and inputs, no simultaneous CPU work, raw samples plus source and binary hashes, and focused controls for regressions. Identical instructions can vary when relocated across alignment boundaries; preserve assembly and reject arbitrary padding or lucky-placement tuning.
