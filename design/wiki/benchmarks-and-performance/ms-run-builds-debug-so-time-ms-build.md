[Wiki](../index.md) › [Benchmarks and performance](index.md)

# `ms run` builds Debug: time `ms build` binaries

Verified: `ms run` defaults to a Cranelift Debug build, `ms build` to Release (LLVM). A parse of 2.8 MB of HTML measured 2,000 ms through `ms run` and 150 ms built, so a probe timed under `ms run` shows a gap that is not there. Build the probe with `ms build` (or `ms run --build-type Release`) before calling anything slow.

Apply when: timing a probe or program to look for a perf gap.
