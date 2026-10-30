# Move from a dead argument that a callee only clones from

## Summary

- Problem: `fn left_of(p: Pair) Big: p.left.clone()` deep-copies `p.left` even when the caller's `p` is dead after the call, because the callee reads `p` borrowed and the caller then drops it.
- Change: infer a third parameter use, clone-source, and lower such a parameter as owned at direct calls whose argument is at its last use. The callee's `rec.get; copy; drop p` is then moved by `copyelim::take_record_fields` (#1993).
- Cost: one more inferred mode and an owned entry for those functions; a caller that is not at the last use pays a whole-value copy instead of a field copy unless the rule below applies.
- Decision requested: build stage 1 (last-use callers only) and gate it on `tests/ownership-counts/dead_record_field.ms`.

## Status

Proposal (under revision after review), 2026-10-30, checked against main `178df7ea`. Direction (Chinmay, 2026-10-30): "separate value semantics from physical copying", moving dead inputs into results rather than cloning them, from general ownership facts. Builds on `proposals/owned-parameters.md`.

Skeptical review, 2026-10-30: **revise, do not build as written.** Objections to resolve first:
- Evidence: the only fixture is a non-recursive `left_of` called from `main`; Release still shows allocs=4, which is unexplained (the inliner should have turned the clone into a move). Find a realistic non-inlinable case and a measured benefit, or the do-nothing case wins.
- Cost: "no call copies more than today" needs a borrowed entry beside the owned one, so every clone-source function gets two entries (plus the indirect wrapper); stdlib and generic instantiations multiply this. Measure it.
- Soundness: with an owned `p`, unwinding must drop `p`'s other fields and skip the caller's drop; `unwind.rs` handling of `Mode::Own` source parameters is unverified, and the "Unproven" list in `owned-parameters.md` applies in full.
- Explained: the Release count is all construction (two heap literals and two lists). The inliner already removes the clone, so the benefit exists only for functions that are not inlined (recursive, large, or reached through a function value). Debug shows the clone (allocs=5). The proposal needs a recursive or large-callee case with a measured Release gain before any build; otherwise the do-nothing case holds.
- Simpler route to try first: infer `Consume` for `p.f.clone()` only, reusing the existing owned-entry path (`owned_mask`, `func.rs`) with last-use callers, so no new mode is added.

## Problem

- Measured (`sh scripts/count-check.sh`, `tests/ownership-counts/dead_record_field.ms`): Debug allocs=5 / 680 bytes, Release allocs=4 / 656 bytes. The clone of `p.left` is one of them.
- Verified: in-function moves work after #1993; `a_field_cloned_out_of_a_dying_record_is_moved_not_copied` and `move-field-from-dead-record` cover a record that dies in the same function after inlining.
- Verified: a read-only parameter is `ParamMode::Borrow` (`crates/ms-check/src/ownership/walk.rs`), so lowering never gives the callee ownership and the clone cannot become a move.
- Non-goals: closures, interface calls and natives (borrowed signature stays), `ref` results, return-slot construction and buffer reuse (separate proposals).

## Design

- Ownership analysis marks a parameter clone-source when every use is `.clone()` of the parameter or of a projection of it, and at least one is a projection (a whole-value clone is already a copy of the same size).
- Lowering treats clone-source as `Consume` for direct calls only when the caller's argument is at its last use (`Use { last }`); otherwise it keeps the borrowed entry. No call ever copies more than today.
- Callee with an owned `p`: lowering of the clone stays `rec.get; copy`, and `copyelim::run_takes` rewrites it to `move.out` plus `rec.release` because `drop p` follows.
- Faults and unwinding: a moved field is never owned by two cleanups; the existing rule (nothing that can fault between the first load and the drop) applies unchanged.
- Observable cleanup: records with a close duty are excluded; their close runs as an explicit call between the load and the drop, so the rewrite does not fire.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` ownership | clone-source parameter fact | unit test on `facts.parameters` |
| `ms-lower` calls | owned entry for clone-source at last-use callers | `dead_record_field.ms` counts drop |
| `ms-mir` copyelim | unchanged (#1993) | existing |
| docs `OWNERSHIP.md` | name the fact | doc check |

## Alternatives

- Do nothing: the copy stays; the callee can't know the caller's `p` is dead. Cost is one deep copy per such call.
- Make callers inline: only works below the inline threshold and not through recursion.
- Whole-value consume for any parameter with a field clone: regresses callers that are not at the last use (copy whole `Pair` instead of `Big`); rejected.

## Open questions

- Does the owned entry double code size for stdlib accessors; measure with `bench/perf/copy-report.sh` before stage 1 lands.
