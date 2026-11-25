# Incremental rebuild results

Script: `ms run bench/perf/tools/compile_time_incremental.ms` (generated project: 1,001 files, 122,957 lines, about 12,000 functions; each scenario edits one file, builds, restores it). 4 cores, Linux, one run per cell, so treat differences under 0.5 s as noise.

## 2026-11-16, `9f09fd55` (no incremental backend work; the whole-build mtime cache was still present)

| Scenario | Debug | Release |
| --- | --- | --- |
| Cold | 5.94 s | 41.07 s |
| No change (hit in the whole-build mtime cache, removed by #4200) | 0.02 s | 0.04 s |
| Change a constant | 6.13 s | 40.79 s |
| Add a statement | 6.19 s | 40.62 s |
| Add a function | 6.42 s | 41.83 s |
| Edit a shared module | 5.88 s | 39.76 s |

Every edit costs a cold build. Per phase (`MS_TIMINGS=1`, second run): Debug 2.3 s check and lower, 0.2 s MIR, 2.9 s Cranelift (6.5 s CPU), 0.1 s link; Release 2.4 s, 0.8 s, 33.8 s (about 100 s CPU), 0.1 s. Release IR diffs after one edit: a constant changed 1 of 4 units (2 lines); a statement plus a function changed all four.

## 2026-11-16, checker speedups (`claude/checker-speed`)

`ms check` on the same generated project, 4 cores, callgrind instructions (one run) and median of seven wall runs: 11.7 B and 2.05 s on `3d8676894`; 5.1 B and 1.55 s after. Causes: borrow arrays indexed by the program-wide binding uid, a scan over every method per structural-property question, `Info` clones in the effect scan, two copies of every declaration in inherent-impl desugaring, and `closeable` per binding.
