# Thread branches whose condition a predecessor knows

## Summary

- Problem: `r = if c: make(a) else: make(b)` followed by `if v := r` builds a `Result` on each arm, joins, then reads the tag and drops it, once per pass.
- Change: a late MIR pass lets a predecessor that passes a known constructor (`alt.new`, `opt.some`/`none`, a constant) to a pure join branch around it, with its own copy of the join and the chosen successor.
- Decision requested: none; no language or visible behavior changes.

## Status

Implemented, 2026-11-23.

## Problem

The `resultvar` guard (`bench/perf/guards/resultvar`) keeps the Result alive through the join: after inlining, each arm ends in `alt.new` and `br join(r)`, and the join runs `alt.tag`, compares and branches. Simplify cannot fold the tag because the join has several predecessors. The old Rust compiler passed this guard through a special path; a general fix is to specialise the join per predecessor.

## Design

For a block P ending in `br J(args)` where J is not a loop header, has at most 8 operations, none writing, allocating or owning, and ends in a branch: evaluate J's operations on what `args` are (constants, `alt.tag` of an `alt.new`, `opt.is_some` of `some`/`none`, `not`, signed `icmp`). When the branch condition is known, copy J's operations and the chosen successor S into a new block that P branches to, mapping J's and S's parameters to P's values. The copy runs the same operations on the same owned values, so ownership edges are unchanged; the existing alt folding then removes the tag read, the field read and the drop of the known constructor. Conditions: S has one predecessor and at most 16 operations; what J defines is used only in J, S and a one-predecessor other target; what S defines is used only in S; S has no cleanup or scope operations. A budget of 192 copied operations per function and 4 rounds bounds growth. It runs after `lastuse` so drops already sit in the arms, and before the final simplify.

## Dead owned values

Threading leaves the other arm's constructor tree (`type.new`, `clone`, an empty map) feeding only a drop. `opt_simplify_dead_owned` (in the simplify rounds) removes any owned value that only drops or other dead constructors consume, to a fixed point, which also covers the earlier per-shape cases. Empty-map construction is marked `pure` and `fresh` (`fn_empty_map`).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt/opt_thread.c`, `opt_pipeline.c` | the pass, a late step | `e2e/accept/thread-known-result` |
| `src/compiler/opt/opt_simplify_dead.c`, `lower/lower_native.c` | dead owned values; pure empty map | same fixture |
| `design/wiki/benchmarks-and-performance` | lesson | none |

## Alternatives

- Do nothing: every Result/Option local assigned on branches keeps an allocation and drop per pass.
- Rewrite the pattern at lowering: keyed on a source shape, and misses inlined callees.
- Scalar replacement of the alt (split it into tag and payload block parameters): more general, larger; threading is the smaller step and composes with it later.
