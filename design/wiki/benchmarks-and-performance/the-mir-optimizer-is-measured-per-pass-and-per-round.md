# The MIR optimizer's compile time is measured per pass and per round

Verified (2026-11-24): on a 7-line program importing `@std/data/yaml.ms`, `ms emit --opt` cost 4.54G instructions (526 ms); the optimizer was 90% of it. Found by callgrind, then by timing each pass call:

- A pass that allocates per block or per candidate turns linear code into quadratic work: `lift_slot_takes` recomputed `mir_use_counts` per block (19% of the run); `opt_thread` scanned every block per candidate for loop headers. Count once per function; precompute a table.
- Callgrind counts `rep stosb` per byte, so zeroed arrays look worse than they are in wall time. Large scratch arrays that are written before they are read use `MS_ARENA_NEW_ARRAY_UNINIT` with a one-byte flag array.
- The per-function round ran six passes up to three times. By pass and round on that program: `range` 38 ms in round 1 (45 changes), 33 ms in round 2 and 32 ms in round 3 with no change either time; `copyelim` and `twins` the same. The schedule is now a table (`func_pass_enabled_by` in `opt_pipeline.c`): a pass reruns only when a pass that can give it work changed the function. Output was byte-identical on 483 programs (benchmark suite, yaml, fixtures).

- The runtime fast paths (`viewfast`, `bytesfast`, `strfast`, then the inliner) grew yaml's MIR from 15K to 60K instructions in the early steps, and every per-function pass then walked 4x the code. They now expand as the last step, after the final `simplify`: MIR is 25% larger at the end, but emit time fell 38%, Debug build 6%, Release build 14%, and 24 suite programs stayed within 0.4% of before in instructions (LLVM cleans the expansion). Expanding late exposed a template bug the cleanup had hidden: `sf_compare_bytes` defined `iconst 0` in a loop block and used it in a block it does not dominate. Templates must define a constant in the block that uses it. Fusing fold and CSE into one walk saved nothing (2213M vs 2202M): per-instruction work, not walks, was the cost.

Method: `valgrind --tool=callgrind ms emit prog.ms --opt` for instructions; a `clock_gettime` wrapper around each pass call for wall time per pass and round; compare `ms emit --opt` output against a build of the base to prove a schedule or skip is exact. A skip keyed on a function fingerprint saved only 4% (most unchanged calls are small), so it was not kept.

Apply when: a pass is added to `function_round` (give it an entry in `func_pass_enabled_by`), or compile time of a large import (yaml, json) regresses.
