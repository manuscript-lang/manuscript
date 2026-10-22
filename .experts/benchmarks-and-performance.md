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

### Source-size gap versus TypeScript is lines and I/O ceremony, not syntax noise

Verified (2026-10-22, o200k_base): `bench/agent/tokens.py` puts the hand-written reference solutions at ms 12.2k, rust 10.1k, go 10.1k, ts 8.3k tokens, so Manuscript is not below Rust (1.21x) or TypeScript (1.48x); the old ms references predate `xs[i]`, `+=`, and inline suites, so they overstate it. Agent-written ms was 1.30x TypeScript. Newlines and indentation account for about 40% of the gap (ms programs run about 1.75x the lines), and agents ignore forms the cheat sheet never showed: `xs[i]`, one-line `if c: return x`, no `flush()`. Reading stdin and the `run()`/`main()` match ceremony cost about 100 tokens per program. Blank lines are free (`\n\n` replaces `\n`). Open options, not decisions: `main` returning `Result`, `try` on `Optional`, a less vertical formatter for call arguments.

Apply when: judging a syntax or stdlib change by its token effect; measure with `tokens.py` and a rerun, not intuition.
Evidence: [tokens.py](../bench/agent/tokens.py), [cheat sheet](../crates/ms-guide/data/cheatsheet.md), [streams.read_lines](../stdlib/streams.ms).
Verify: `python3 bench/agent/tokens.py` prints the per-language totals; rerun the small challenges and compare `llm_tokens` of passing ms and ts runs.
