# Two-pass MIR optimizer

## Summary

- Problem: the optimizer is 9.6% of a Debug build and 90% of `ms emit --opt` on large imports; its cost is walks x rounds x function size, so constant-factor fixes (#6822, #6834) do not change the shape.
- Change: replace the early steps plus three rounds of six per-function passes with two walks per function: a forward fused simplifier and a backward ownership/liveness sweep, fed by bottom-up inlining of already-optimized callees.
- Decision requested: approve the staged replacement below. Chinmay's direction: "things need to be mostly single pass, 2 passes at the most".

## Status

Proposal, 2026-11-24, checked against `eeedac8f`.

## Problem

Measured on a 7-line program importing `@std/data/yaml.ms` (`ms emit --opt`, after #6834: 2.2G instructions):

- MIR instructions after each stage: lowering 8.4K, after early simplify/copyelim/probe/inline 13.8K, after `fastpaths` 59.8K (4x, from inlining the view, bytes and string fast paths), after function passes 45.8K, final 49.6K.
- Function passes ran 116, 62 and 38 functions in rounds 1 to 3. Wall time by pass over three rounds: simplify 118 ms, range 80 ms, copyelim 24 ms. A change by one pass makes the next walk the whole function again.
- Instruction counts (callgrind, same program): `opt_simplify_func` 974M of 2.2G (170 calls from function rounds on the expanded 60K-instruction form, 675M; 2 module steps, 300M); its sub-passes run 848 times for 471 calls (1.8 rounds each): cse 224M, fold 184M, branches 153M, dead_owned 101M, phis 78M. `range` 230M, `inline` 179M, `copyelim` 141M. `mir_use_counts` is 4.6%: incremental use counts alone are not worth a stage.
- Rounds 2 and 3 of the function passes change little: `OPT_FUNCTION_ROUNDS` 1 instead of 3 gives 46329 instead of 46334 instructions and 4% less emit time. The cost is volume (the 4x expansion) times visits per instruction (about 100 per sub-pass), not the round count.
- Every pass rebuilds its own def/use facts (`mir_use_counts`, `rg_build_env`, `SfEnv`, `cpe_*`) from scratch.
- Moving `fastpaths` after the function passes (tried) saves only 6% of emit time and leaves the final size the same: the expanded bodies are optimized once either way, so reordering alone does not help.

## Design

Per function, two walks, each visiting an instruction a bounded number of times:

1. Forward walk in reverse post order over the dominator tree (fold, copy propagation, CSE, branch folding, range facts):
   - Values are rewritten as they are visited, so a use sees the folded definition at once; there is no "run to a fixed point".
   - CSE is a dominator-scoped hash table (push on entering a dominated child, pop on leaving), not a function-wide scan.
   - Range facts are an environment scoped the same way (today's `rg_build_env` already clones from the idom). A loop-header block parameter takes its type bound narrowed by the loop's own guard; there is no iteration, so a fact the old fixpoint proved only by iterating is lost, and the Stage 3 check counts how many.
   - Use counts are kept incrementally (increment on a new use, decrement on a removed one); a value reaching zero uses is deleted by the same walk. No pass calls `mir_use_counts`.
   - Branch folding and block merging queue their edits and apply them once at the end of the walk, then the walk is repeated only for the blocks the edit touched.
2. Backward walk, post order: liveness-driven dead code, `dead_owned`, drop and take placement (`lastuse`, `exit_drops`, `copyelim takes`). These are backward problems, so they belong in one backward sweep over the use counts the forward walk left behind.

Inlining: module-level, callees first in call-graph order (SCCs by size threshold, as today). A callee is already through both walks when inlined, so inlining it into the caller marks only the inlined blocks dirty and the forward walk visits those. The early module steps (`simplify`, `copyelim`, `probe`, `inline`) and `function_round` are deleted.

Runtime fast paths (`viewfast`, `bytesfast`, `strfast`): each template is optimized once when first used in a module, then spliced like any callee. The 4x growth is then paid once per template, not once per call site.

Ownership and range fit the two walks because both are dominator-ordered (range, the forward walk) or last-use ordered (ownership, the backward walk). Neither needs a second forward pass once the facts are scoped.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt/opt_simplify*.c`, `opt_copyelim*.c`, `opt_range*.c` | merge into one forward walk (`opt_forward.c`) | `ctest`, `conform`, MIR diff on the 483-program set |
| `opt_lastuse*.c`, `opt_exit_drops.c`, `opt_simplify_dead.c` | merge into one backward walk (`opt_backward.c`) | same |
| `opt_pipeline.c`, `opt_inline*.c` | bottom-up inlining; delete `function_round` and the early steps | same, plus `bench/perf` instruction counts |
| `opt_viewfast.c`, `opt_bytesfast.c`, `opt_strfast.c` | optimize each template once | same |

## Alternatives

- Do nothing: optimizer stays 9.6% of Debug, and every new pass adds a whole-function walk. Constant-factor work is exhausted at about 2x (measured in #6822, #6834).
- Late fast-path expansion only: measured 6% on yaml emit, no change in final size (Problem, last bullet).
- Flat SoA MIR with incremental def/use: the largest rewrite, touching every pass and the verifier; kept as a later step because the walks above get most of the win on the current representation.
- Sparse worklist over the existing passes: keeps 16 sub-passes and their duplicated facts; reduces rounds but not walks.

## Stages

1. Simplify revisits only what changed: per-block dirty bits through the core rounds, so the confirming second round touches changed blocks only; gate: byte-identical `ms emit --opt` on the 483-program set, simplify instruction count down.
2. Forward walk replacing simplify core and CSE (dominator-scoped); gate: perf suite instruction counts no worse than the latest `bench/perf` baseline.
3. Range folded into the forward walk; gate: count of proofs lost against the fixpoint, each regained or justified.
4. Backward walk; gate: conform, ownership tests.
5. Bottom-up inlining, template-once expansion, delete `function_round`; gate: optimizer share of `ms build --build-type Debug` below 5%.

Each stage lands green as its own stacked PR. Target: function passes about 3x fewer instruction visits, optimizer about 4% of a Debug build (hypothesis; Stage 5 reports the measurement).
