# Index the checker's type and method tables

## Summary

- Problem: `ms check` spends 40% of its instructions in `Checker::implements`, a linear scan of every method per query, and 35% of the profile in hashing and malloc. Types are `Rc<Type>` trees compared and hashed structurally by `Name`.
- Change: stage 1 indexes methods by contract. Interning types (`TyId`) and removing lowering's `tycache` are conditional follow-ups, not in this PR.
- Decision requested: none (no language change). Each stage merges only if its before/after run beats the baseline below.

## Status

Stage 1 implemented, 2026-11-02, checked against `c30abc7d`. Direction (Chinmay): "caching is cope for a slow design. do not add caches and delete all existing caches"; "ensure the perf gain is gate on these". Skeptic review (subagent, 2026-11-02): stage 2 unsupported by evidence, scoped out; stage 1 sound, index placement and generic bucket added.

## Problem

Measured (`c30abc7d`, release `ms check` on `bench/compile-time/gen.py 40 25 10`, 122k lines, callgrind, one machine): 14.45G instructions, 1.9 to 2.6 s wall.

| Where | Ir (inclusive) | Share |
| --- | --- | --- |
| `Checker::implements` (`contracts.rs:739`) | 5.81G | 40% |
| of which `unify` | 1.62G | 11% |
| `syntax::Info::clone` | 0.99G | 7% |
| SipHash, hashbrown, malloc, free (self) | 6.39G | 44% |

- `implements` ran 32.2M times. Past the fast paths it loops over all `self.p.methods`, and each iteration builds a `Subst` (a `HashMap`) and runs `unify`, `sub` and `same`.
- Two lookup tables exist (`methods_by_receiver`, `methods_by_name`), but none by contract, so the loop cannot skip non-matching methods.
- `Name` is `Symbol(&'static str)` (`ms-syntax/src/symbol.rs:12`), so every `HashMap<Name, _>` hashes a pointer with SipHash.
- `same` (`types.rs:739`) walks trees, with a 64-step budget before it starts a pointer-pair `HashSet`; `type_graph_tests.rs` exists to bound this DAG blowup.
- Lowering keys `tycache: HashMap<String, MTy>` by a formatted type string (`ms-lower/src/cx.rs:157,328`). Measured at 0.07% of `ms emit` by the lowering-table thread, so it is removed for design reasons, not speed; it needs a dense id, which only checker interning provides.

## Design

Stage 1, method index (no type change):
- Add `methods_by_contract: HashMap<Name, Vec<usize>>` beside `methods_by_receiver`, filled in `add_method` (`contracts.rs:283`) so later standard methods are included. Key by the contract's `id`. Methods whose contract is a type variable go in one generic bucket scanned for every query, since `sub(mc, s)` can change the id.
- Skip the `Subst` allocation when the method's receiver and the query share no variables (compare heads first).
- Hypothesis: bucket sizes are small; measure methods per contract before building.

Stages 2 and 3 (interned `TyId`, dense `Symbol`, `lower_ty` by id, delete `tycache`) are conditional and get their own proposal only if the post-stage-1 profile still ranks `same`, `sub`, `unify` or `Name` hashing on top. No evidence supports them today. Known hazards for that proposal: `sub` clones variables to snapshot bounds and defaults (`types.rs:829`, `Type::clone`), so id identity conflicts; `same` ignores `def`, `defaults` and param names, so hash-consing must choose key fields; `Subst` is keyed by `Name`, not ordinal; `Definition` holds `RefCell`s and a `Weak`; hash-consing is a dedup table the owner may treat as a cache. `tycache` is 0.07% of `ms emit`, so stage 3 has no standalone value.

Invariants: diagnostics text and order are byte-identical (conformance corpus diff). `implements` is a pure bool, so first-match order does not matter.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/src/contracts.rs`, `checker.rs` | contract index, head check before `Subst` | `cargo nextest run -p ms-check`, conformance corpus diff |

## Alternatives

- Do nothing: leaves 40% of check time in one scan.
- Memoize `implements`: rejected, it is a cache (owner rule).
- Faster hasher: needs a new crate or in-house code and only shrinks the cost.
- Interning now: no evidence; see Design.

## Stages

One PR. Gate: `ms check` on the 122k-line workload drops at least 20% in callgrind Ir against 14.45G (two runs, same machine), conformance output identical, full CI matrix green. Result recorded as a dated section in `bench/compile-time/README.md`. If the gate fails, do not merge.
