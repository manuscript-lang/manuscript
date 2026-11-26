[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Skipping a settled simplify rerun saves almost nothing

Verified: on the 122k-line generated project, 22k of the 39.5k `opt_simplify_func` calls found nothing, about 43% of the instructions simplify walks. A function fingerprint (hash of every block, instruction and terminator) stored when simplify settled skipped only 1015 calls, because 26k of the other calls follow a pass (copyelim, inline, unwind threading) that changed the function after simplify left it. The hash cost more than it saved (+1.3% instructions on the small project), so it was dropped. A per-function changed flag fails the same way; the lever is cheaper no-change rounds, not fewer of them. Sharing use counts, predecessors and reverse post-order across the sub-passes of a settled round is worth about 1.5% at most.

Apply when: tempted to memoise or skip per-function optimiser passes.
Evidence: callgrind of `ms build --emit ir --opt ` on the generated compile-time project (`bench/perf/tools/compile_time.ms`).
Verify: count calls that skip versus run before building the skip.
