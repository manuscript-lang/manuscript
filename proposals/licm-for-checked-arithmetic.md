# Hoisting loop-invariant checked arithmetic

## Summary
- Problem: `stencil_1000_20` runs 1169M instructions against 911M for checked Rust (1.28x); each cell recomputes `y*n`, `(y-1)*n` and `(y+1)*n` with `imul.chk`.
- Change considered: a MIR pass that hoists loop-invariant faulting ops (`imul.chk`, `iadd.chk`) to a guarded loop preheader.
- Decision requested: do not build it (see Status).

## Status
Proposal, 2026-11-23, checked on main `da52100`. Outcome: not built. The upper bound is zero on LLVM and 8.6% on one kernel on Cranelift, which is not held to C parity. Reviewed by an independent skeptical pass; the do-nothing case held.

## Problem
Inner loop MIR for the stencil has 9 `.chk` ops per cell, three of them invariant in `x` (`y*n`, `(y-1)*n`, `(y+1)*n`). A fault op cannot move out of a loop that may run zero times without a guard, so MIR does not hoist them.

Measured (callgrind, `ms` Release, `/tmp` copies of `bench/perf/kernels` stencil):

| Variant | Instructions |
| --- | --- |
| current source | 1168.85M |
| source with `row`, `up`, `down` computed once per `y` (the best any hoisting pass can do) | 1168.78M |
| checked Rust, same algorithm | 910.95M |
| Debug build (Cranelift): current / hoisted by hand | 1396.7M / 1277.3M (8.6% fewer) |

## Design
A pass would hoist an invariant faulting op to a block entered only when the loop body is known to run, so the fault order is kept. It can reuse the loop and dominator code in `opt_reserve.c` (`rsv_natural_loop`), `opt_range.c` and `opt_loopslot.c`.

## Components touched
| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt` | new pass with loop discovery and a guarded preheader | emit command fixture, conformance fault-order cases |

## Alternatives
- Do nothing (chosen): LLVM already hoists the invariants; hand-hoisting removed 0.01% of instructions, so the pass has no benefit on this kernel. The remaining 1.28x is elsewhere (loads of the list header per `get`, overflow branches), and wall-clock is 1.08x of checked Rust in `bench/perf/kernels/README.md`.
- Hoist with a speculation-safe form (`mul` with a saturating flag, fault later): changes fault ordering rules in `wiki/compiler`.
