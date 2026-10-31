[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Performance and agent benchmarks are separate

Decision: `bench/perf/` measures compiler/runtime speed (`stdlib/` ns per operation, `programs/` and `kernels/` whole-program comparisons); `bench/agent/` measures how well agents solve the same challenges in TypeScript, Go, Rust, and Manuscript (hidden tests, tokens, turns, time, cost). Each README points at the other, and their results never share a table. Keep agent-bench transcripts out of git.

Apply when: reporting numbers, adding a benchmark, or moving either directory.
Evidence: [bench/perf](../../bench/perf/README.md), [bench/agent](../../bench/agent/README.md), [maintenance skill](../../skills/repository-maintenance/SKILL.md).
Verify: `make agent-bench-check` (oracle plus unit tests) passes; every path in the Makefile, docs, and skills resolves after a move (`make repo-check`).

---
Topics: [Performance](../topics/performance.md)
