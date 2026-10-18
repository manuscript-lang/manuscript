# Benchmarks and performance lessons

Two unrelated benchmarks exist; never mix their results. Measurement pitfalls for small runtime wrappers are also in [runtime.md](runtime.md); lowering trade-offs are in [compiler.md](compiler.md).

Open: the task that requested this file said the benchmarks moved under `bench/`. This checkout has `perf-bench/` and `agent-bench/` at the root and no `bench/`; paths below follow the checkout. Re-verify and update the paths when the move lands.

### Performance and agent benchmarks are separate

Decision: `perf-bench/` measures compiler/runtime speed (`stdlib/` ns per operation, `programs/` ratio against hand-written Go); `agent-bench/` measures how well agents solve the same challenges in TypeScript, Go, Rust, and Manuscript (hidden tests, tokens, turns, time, cost). Each README points at the other, and their results never share a table. Keep agent-bench out of Go checks and its transcripts out of git.

Apply when: reporting numbers, adding a benchmark, or moving either directory.
Evidence: [perf-bench](../perf-bench/README.md), [agent-bench](../agent-bench/README.md), [maintenance skill](../skills/repository-maintenance/SKILL.md).
Verify: `make agent-bench-check` (oracle plus unit tests) passes; every path in the Makefile, docs, and skills resolves after a move (`make repo-check`).

### Benchmarks are a profiling guide, not a gate

Verified: results are only comparable on one machine and revision; record the commit and machine with the table, as the result files do. Use best-of-N or median of repeats, alternate before/after order, exclude build and warm-up, and require a deterministic checksum so a wrong program cannot look fast. Do not add a CI threshold.

Apply when: claiming a speedup or regression.
Evidence: [stdlib results](../perf-bench/stdlib/results.md), [program results](../perf-bench/programs/results.md), [native workload harness](../scripts/benchmarks/README.md).
Verify: before/after run on the same host with `make stdlib-bench BENCHREPEATS=5 BENCHFILTER=<case>` or `perf-bench/programs/run.sh 7`.

### A win needs a Go-oracle comparison, not just a smaller number

Verified: runtime changes were judged against hand-written Go (read_line 136 to 95 ns/line vs Go 73; `match` 7.5 to 6.1 ns/op; `string_append` 9.2 to 7.1). The remaining gaps in the program table (`match`, `builtin_length`) are the known targets; `generic_call` already beats the Go control. Prefer removing per-operation work (cancellation polls in O(1) helpers, mutex round trips, avoidable allocations) over micro-tuning, and check allocations with `-benchmem`.

Apply when: optimizing a helper or lowering path.
Evidence: [runtime.md entries on O(1) helpers and ReadLine](runtime.md), [program results](../perf-bench/programs/results.md).
Verify: ns/op and allocs/op before and after on one machine; behavior tests unchanged.

### Tooling performance is measured per protocol request

Verified: editor and CLI changes (lexical token reuse, shared analysis, rename indexes, source-line scans) are justified with request-level measurements recorded in `scripts/bench-tooling/`, including known invalidation blockers, not with whole-run timings. A claimed win needs a retained result file or a documented reason it cannot be kept.

Apply when: optimizing LSP, formatter, or checker passes.
Evidence: [tooling benchmarks](../scripts/bench-tooling/README.md), [list storage measurements](../scripts/bench-lists/typed-storage.md), commit 12ef3b75.
Verify: rerun the harness against the previous revision and compare medians.
