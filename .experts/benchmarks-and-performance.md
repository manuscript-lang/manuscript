# Benchmarks and performance lessons

Two unrelated benchmarks exist; never mix their results. Measurement pitfalls for small runtime wrappers are also in [runtime.md](runtime.md); lowering trade-offs are in [compiler.md](compiler.md).

### Performance and agent benchmarks are separate

Decision: `bench/perf/` measures compiler/runtime speed (`stdlib/` ns per operation, `programs/` ratio against hand-written Go); `bench/agent/` measures how well agents solve the same challenges in TypeScript, Go, Rust, and Manuscript (hidden tests, tokens, turns, time, cost). Each README points at the other, and their results never share a table. Keep agent-bench out of Go checks and its transcripts out of git.

Apply when: reporting numbers, adding a benchmark, or moving either directory.
Evidence: [bench/perf](../bench/perf/README.md), [bench/agent](../bench/agent/README.md), [maintenance skill](../skills/repository-maintenance/SKILL.md).
Verify: `make agent-bench-check` (oracle plus unit tests) passes; every path in the Makefile, docs, and skills resolves after a move (`make repo-check`).

### Benchmarks are a profiling guide, not a gate

Verified: results are only comparable on one machine and revision; record the commit and machine with the table, as the result files do. Use best-of-N or median of repeats, alternate before/after order, exclude build and warm-up, and require a deterministic checksum so a wrong program cannot look fast. Do not add a CI threshold.

Apply when: claiming a speedup or regression.
Evidence: [stdlib results](../bench/perf/stdlib/results.md), [program results](../bench/perf/programs/results.md), [native workload harness](../bench/language/README.md).
Verify: before/after run on the same host with `make stdlib-bench BENCHREPEATS=5 BENCHFILTER=<case>` or `bench/perf/programs/run.sh 7`.

### A win needs a Go-oracle comparison, not just a smaller number

Verified: runtime changes were judged against hand-written Go (read_line 136 to 95 ns/line vs Go 73; `match` 7.5 to 6.1 ns/op; `string_append` 9.2 to 7.1). The remaining gaps in the program table (`match`, `builtin_length`) are the known targets; `generic_call` already beats the Go control. Prefer removing per-operation work (cancellation polls in O(1) helpers, mutex round trips, avoidable allocations) over micro-tuning, and check allocations with `-benchmem`.

Apply when: optimizing a helper or lowering path.
Evidence: [runtime.md entries on O(1) helpers and ReadLine](runtime.md), [program results](../bench/perf/programs/results.md).
Verify: ns/op and allocs/op before and after on one machine; behavior tests unchanged.

### Tooling performance is measured per protocol request

Verified: editor and CLI changes (lexical token reuse, shared analysis, rename indexes, source-line scans) are justified with request-level measurements recorded in `bench/tooling/`, including known invalidation blockers, not with whole-run timings. A claimed win needs a retained result file or a documented reason it cannot be kept.

Apply when: optimizing LSP, formatter, or checker passes.
Evidence: [tooling benchmarks](../bench/tooling/README.md), [list storage measurements](../bench/lists/typed-storage.md), commit 12ef3b75.
Verify: rerun the harness against the previous revision and compare medians.


### Consume library checksums and separate allocation phase from local cost

Verified: a returned checksum that the harness discards is not evidence that the
work stayed observable. Print each checksum after stopping the clock and reject
missing, duplicate, changed counts/checksums on every trial. The corrected
`compare_stdlib.py` validates all 66 cases. Changing an earlier allocating workload
can move later collection pauses: line payload elision also closed most of the
following map row's gap. Full-suite apparent string/regex/archive regressions did
not reproduce when the same cases ran repeatedly in separate focused processes.
Keep both results and state that distinction; do not silently replace the full run.

Apply when: retaining a benchmark win or diagnosing a nominal unrelated slowdown.
Evidence: [stdlib validator](../bench/perf/compare_stdlib.py),
[program measurements](../bench/perf/programs/results.md).
Verify balanced process order, identical tool flags/inputs, no simultaneous CPU
work, raw samples plus source/binary hashes, and focused controls for regressions.
Identical native instructions can also vary when relocated across loop-alignment
boundaries; preserve assembly and reject arbitrary padding or lucky-placement tuning.

Verified: resolve native workspace paths before using Go build overlays. A mapping
through a symlinked ancestor can miss the compiler's canonical path and silently
leave the original source in use. Assert changed source/binary hashes for controls.
Native replay and ordinary builds can differ only in ELF build-id notes; compare
code/data sections and normalize identical link flags before attributing library
timing variation to generated code. The Result-bound increment produces identical
normalized library binaries despite timing variation in diagnostic CLI builds.

- Safe finite-loop aggregation measurements must retain logical source operation
  counts and explicitly say work was combined. Native observers should inspect
  original locals at actual emitted queries, including signed updates, partial
  tails, cancellation/shield/nil, cleanup and query-raised source frames. Scaling
  must assert accepted aggregates; capturing the carry only measures fallback.
- Canonicalize native-cache paths before Go overlay mapping and assert executable
  hashes change. A symlink mapping can silently miss the actual compiler input.
  Match clone controls improved matching but regressed traversal; the candidate
  was rejected. Lower inline cost alone also did not improve builder append.
