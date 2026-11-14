---
name: add-benchmark
description: Add a performance benchmark with matching Rust, Go and C ports, outputs compared, and a dated result. Use when adding or revising a benchmark program or suite.
---

# Add a benchmark

Read [benchmarks and performance](../../wiki/benchmarks-and-performance/index.md), `bench/perf/README.md` and the perf rule in [AGENTS.md](../../AGENTS.md#shared-guidance-and-checks) first.

1. **Pick a realistic workload.** An ordinary program (parser, interpreter, codec, server, data tool), not a stress test of one primitive. A stress test is a probe and is not listed as a headline result.
2. **Write the Manuscript version first**, in idiomatic Manuscript with the driver in `bench/tools/` ([drivers](../../wiki/benchmarks-and-performance/benchmark-drivers-are-ms-programs-in-one-flat-directory.md)).
3. **Port it to Rust, Go and C** (the languages speed is compared with) with the same algorithm, data layout, allocation pattern and concurrency shape. Do not give a port a smarter design or a worse one; a gap must be the language, not the program. Use a library only where Manuscript's standard library does the same job.
4. **Compare outputs.** Every version prints the same checksum or output; the driver fails on a mismatch. Python or Node may supply correct answers, never timings.
5. **Measure for noise.** Shared VMs move 2x between runs: use many runs and report the median, and compare instruction counts (`valgrind --tool=callgrind`) before reading a gap from wall time.
6. **Record** a dated section in the suite's results page with the revision and machine; never edit old numbers. Add the suite to the `bench/perf/README.md` table.
7. **Check**: `make bench-check`, then land with [create-pr](../create-pr/SKILL.md).
