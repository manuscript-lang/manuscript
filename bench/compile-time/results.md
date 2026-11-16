# Incremental rebuild results

Script: `ms run bench/tools/compile_time_incremental.ms` (generated project: 1,001 files, 122,957 lines, about 12,000 functions; each scenario edits one file, builds, restores it). 4 cores, Linux, one run per cell, so treat differences under 0.5 s as noise.

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

## 2026-11-16, Cranelift function cache (Debug)

Same project and machine; one run per cell. The whole-build mtime cache was still present (the "no change" row), so the edit rows are the measure.

| Scenario | Before (above) | With the function cache |
| --- | --- | --- |
| Cold | 5.94 s | 6.33 s |
| Change a constant | 6.13 s | 4.64 s |
| Add a statement | 6.19 s | 5.21 s |
| Add a function | 6.42 s | 4.58 s |
| Edit a shared module | 5.88 s | 5.09 s |

`MS_TIMINGS=1` reports `code cache N hits, M compiled`: a statement added to one function compiled 11 of 12,011 functions (the edited one and the rest of its file, whose line numbers moved); with nothing changed, 0. A fully cached build is 4.7 s: check and lowering to MIR about 2.4 s, lowering to Cranelift IR 0.6 s, keys 0.3 s, glue, tables and object writing about 0.7 s. Release builds use LLVM and are unchanged.
