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
