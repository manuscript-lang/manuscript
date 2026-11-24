---
name: perf-bash
description: Find, measure, and fix performance gaps in Manuscript with before/after evidence, or close them as not planned with numbers. Use for "perf bash" and perf-issue requests.
---

# Perf bash

Read [benchmarks and performance](../../design/wiki/benchmarks-and-performance/index.md) and `bench/perf/README.md` first. Benchmarks are a profiling guide, not a gate.

1. **Pick the gap.** Start from the latest `bench/perf/baseline-*.md` or an open perf issue. Reproduce it with the matching suite's run script on a Release build (`make build`).
2. **Measure before changing.** Compare instruction counts and page faults before tuning ([wiki](../../design/wiki/benchmarks-and-performance/index.md)). Rerun a flagged case alone with many samples; single cases in full runs vary about 40%.
3. **Fix in the right layer.** Prefer a general language or stdlib change in `.ms` over a Rust special case. Add a control benchmark for the neighboring case the fast path must not slow (invalid input, small sizes, unions).
4. **Show before/after.** Same machine, same suite, medians. A change that slows another suite is revised or closed.
5. **Record.** Add a dated section to the suite's results rather than editing old numbers. A fix not worth its code is closed not-planned on the issue with the numbers and what was tried.
6. **Land** with [create-pr](../create-pr/SKILL.md); cite the benchmark page and revision.

Do not over-index on a few kernels: a fix must help programs in general, with no special case for one benchmark. Perf work covers stdlib and release builds for ordinary engineering tasks.
Do not fall back to Rust to make a program fast: make Manuscript fast enough, with a general compiler or stdlib change, and take general wins before one-off ones. Everyday data structures (types, enums, generics, collections) must be fast in the general case. Be skeptical of a result that looks too good (a Manuscript win of 2x or more over Rust usually means an unfair baseline). Deleting or replacing code must not regress perf; fast paths are shared MIR operations both backends inline. Run an experiment or spike before a big rewrite. Release builds keep cross-file optimization and the vectorizer.

## Working practices

- **Count instructions before blaming an algorithm.** A large wall-time ratio can be cache and memory effects. See `make scaling-check`.
- **Measure compile cost as well as run time**, before and after.
- **Record rejected experiments** in the wiki with the result and the decision.
- **Existing primitives first.** A micro-optimization that needs a new primitive is not worth it; try what exists (for example `set` and `swap` on a list) first. Moving data should be almost free with a single heap: when it is not, find out why.
- **No shortcuts.** Use legitimate algorithms. Do not over-index on one benchmark: scheduling and other shared paths must be fast in general.
- **Portable.** A fast path on Linux epoll needs an equivalent on macOS (kqueue) and Windows (IOCP). Measuring on Linux alone is fine.
- **Unsafe speedups lose.** Prefer the change that cannot silently change behavior; a perf fix that adds a bug is reverted.

## Standing rules

Fix root causes with general algorithms and no benchmark hacks. Design data-oriented (flat arrays, indices) and compare against checked C (overflow and bounds checks on) on both Cranelift and LLVM, reading the generated machine code. Never gate or drop a test without the owner's okay. Stack PRs with auto-merge and do not idle on CI. Keep platform parity, add no CI shards, add no dependencies without asking, and keep stdlib work in Manuscript. Say "borrow", never "lend". Add the `in progress` label before fixing an issue and verify every fixed issue closes. Keep going until nothing new is found.

## Areas

Pick an area and measure it; this is a list of areas, not a status.

- Memory and binary size; compile speed; workloads and stdlib hot paths; text and parsing; collections, iterators and generics; concurrency and I/O; MIR passes; generated code vs C.
- Startup time; the FFI and extern boundary; long-running servers (thread churn, parked-task unwind); LLVM on huge functions (#3928); incremental builds; package resolution at scale.
