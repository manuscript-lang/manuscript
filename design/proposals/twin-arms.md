# Merge branch arms that run the same operations

## Summary

- Problem: `if b < a: dst[k] = b; j += 1 else: dst[k] = a; i += 1` stays two data-dependent branches, so it mispredicts where C uses a conditional move.
- Change: a MIR pass merges the two arms into one block when they run the same operations, and selects what differs.
- Decision requested: none; no language or visible behavior changes.

## Status

Implemented, 2026-11-23.

## Problem

A bottom-up merge sort over `List[Int]` with a comparator takes 93 ms for 1M Ints. The same loop in C with bounds and overflow checks takes 68 ms, at the same instruction count (about 450M against 484M). Rewritten with `if` arms that only set variables, so `ifconv` selects them, the Manuscript version takes 61 ms. The gap is the branch, not the checks: each arm holds a bounds check, a `take; list.set.u; put` and an increment, which `ifconv` rejects because the arms are not pure.

## Design

Two blocks are twins when they have the same parameters, instruction sequence (op, immediate, result types, `exact` bits) and terminator kind, and every successor is shared or itself a twin pair reached only from them. Each operand pair is the same value, the value at the same position in each block, or a scalar that differs. A differing scalar defined outside both blocks becomes a block parameter, and each side's edges pass its own value. A scalar from one arm mixed with the other is chosen by a `select` on a flag parameter. Differing constants are not merged as instruction operands (range analysis and `exact` need them). Then a branch whose two edges reach one block turns its differing arguments into `select`s.

The pass starts at a branch whose arms each have it as sole predecessor and take scalar parameters only, so both arms start with the same owned values. The verifier requires owned sets to agree across incoming edges, and a first version that merged fault blocks reached from different places broke it (the verifier caught it); merging the whole arm tree from the branch avoids that. Loops are left alone: a successor that dominates an arm is refused.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt/opt_twins.c`, `opt_pipeline.c` | the pass, after `ifconv` in the function rounds | `e2e/accept/twin-arms` |
| `design/wiki/benchmarks-and-performance` | lesson | none |

## Alternatives

- Do nothing: sorts, merges and every two-way update with checked stores keep a mispredicting branch per element.
- Extend `ifconv` to speculate checked stores: a store may fault, so hoisting it above the branch is unsound without predicating the fault, which costs as much as the branch.
- Sink common code into the join: LLVM's sinking cannot handle arms whose results feed the join differently; the select form handles them.
