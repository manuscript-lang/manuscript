---
name: perf-bash
description: Find, measure, and fix performance gaps in Manuscript with before/after evidence, or close them as not planned with numbers. Use for "perf bash" and perf-issue requests.
---

# Perf bash

Read [benchmarks and performance](../../wiki/benchmarks-and-performance/index.md) and `bench/perf/README.md` first. Benchmarks are a profiling guide, not a gate.

1. **Pick the gap.** Start from the latest `bench/perf/baseline-*.md` or an open perf issue. Reproduce it with the matching suite's run script on a Release build (`make build`).
2. **Measure before changing.** Compare instruction counts and page faults before tuning ([wiki](../../wiki/benchmarks-and-performance/index.md)). Rerun a flagged case alone with many samples; single cases in full runs vary about 40%.
3. **Fix in the right layer.** Prefer a general language or stdlib change in `.ms` over a Rust special case. Add a control benchmark for the neighboring case the fast path must not slow (invalid input, small sizes, unions).
4. **Show before/after.** Same machine, same suite, medians. A change that slows another suite is revised or closed.
5. **Record.** Add a dated section to the suite's results rather than editing old numbers. A fix not worth its code is closed not-planned on the issue with the numbers and what was tried.
6. **Land** with [create-pr](../create-pr/SKILL.md); cite the benchmark page and revision.

Do not over-index on a few kernels: a fix must help programs in general, with no special case for one benchmark. Perf work covers stdlib and release builds for ordinary engineering tasks.
Do not fall back to Rust to make a program fast: make Manuscript fast enough, with a general compiler or stdlib change, and take general wins before one-off ones. Everyday data structures (types, enums, generics, collections) must be fast in the general case. Be skeptical of a result that looks too good (a Manuscript win of 2x or more over Rust usually means an unfair baseline). Deleting or replacing code must not regress perf; fast paths are shared MIR operations both backends inline. Run an experiment or spike before a big rewrite. Release builds keep cross-file optimization and the vectorizer.
