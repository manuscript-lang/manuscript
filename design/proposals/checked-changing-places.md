# Checked changing places

## Summary

- Complete receiver selection across source, native, contract and function-value call paths.
- Evaluate the ordinary checked receiver once, retaining only its selected indices for writeback.
- Preserve current source semantics and resource close ordering, without a new representation or ABI.

## Status

Implemented after independent skeptical review, 2026-11-07, as a follow-up to #2844 on main `3425b71d7`, preserving #2856 incoming-argument registration.

## Problem

- #2844 corrected nested receiver faults, implicit source receivers, and ordinary resource receiver ordering.
- Contract and function-value `var` argument paths still do not retain their selected indices.
- Indexed map native fast paths still run arguments before receiver preparation.
- Intermediate resource map clearing retires a selection before the final mutation reuses it.
- These remaining gaps violate existing single-selection semantics, not a proposed language change.

## Design

- A checked place read uses normal expression lowering in receiver-first order.
- Retain fully fitted index values only along the local-rooted receiver chain, not nested argument expressions.
- Key retained values by module identity, node identity and position because defaults temporarily switch HIR.
- Retain owned keys as ordinary statement temporaries until writeback completes.
- Reconstruct the current owner at writeback using selected indices; never retain stale projections or raw pointers across sibling calls.
- Retire the whole selection after the final writeback, including paths that discard a changed copy.
- Native fast paths run only after receiver selection; resource entry closes remain in original owner storage before mutation.
- An intermediate map resource clear must not retire the selection needed by the final mutation.
- Computed temporary receivers retain their existing ownership and cleanup behavior.
- Incoming resource ownership during a failed replaced-entry close is handled by upstream #2856 and preserved here. Borrowed-key lifetime across source reassignment (#2843) remains a separate non-goal.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-lower` | Checked selection and scoped index retention in calls and updates | Native fault/order/writeback fixtures |
| E2E fixtures | Explicit, implicit, contract, function-value and resource calls | Baseline failure and corrected execution |
| Compiler wiki | Selection lifetime and fault-order invariants | Repository checks |

## Alternatives

- Do nothing leaves confirmed repeated-selection and native argument-order errors.
- Index-only preparation cannot preserve bounds/key faults between indices.
- Retaining a projection or storage pointer across calls risks stale storage after a sibling mutation.
- Moving entry closes into a taken-owner callback changes resource fault cleanup and is rejected.
