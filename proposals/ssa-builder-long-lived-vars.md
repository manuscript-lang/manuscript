# SSA builder: immutable lets skip the reaching-definition search

## Summary

- Problem: `ms_mir::builder::read_var` is quadratic when many variables stay live across many join blocks; it hits Debug too (`--build-type Debug` N=400 0.75s, N=800 2.8s, N=1600 12.7s).
- Change: a builder variable kind `declare_single` for immutable `let` bindings, defined once and read directly. Lowering uses it in `bind_local` and `bind_lent` when `!binding.mutable`.
- Cost: about 30 lines in `builder.rs` and two call sites in `ms-lower/src/func.rs`. No IR, language, or pass change.
- Decision requested: approve after review. The first draft (a "closed block" fast path inside `read_var`) was dropped on review: its closedness is defeated by loops and it needs an SCC pass.

## Status

- Proposal, 2026-10-28, checked against main after #1854.
- Direction: issue #1856; AGENTS.md requires a proposal before restructuring.
- Skeptical review (separate thread): the draft fast path was not ready; the reviewer's first suggestion, bypassing `def_var`/`use_var` for never-reassigned lets, is what this version does.

## Problem

- Repro (`gen-longlived-repro.sh N long`, in project files `architecture/mir-scaling-review/`): N `let k_i = "key{i}".upper()`, then N `if` checks updating `bad`, then N `bad += k_i.length()`. Measured Debug 0.75s, 2.8s, 12.7s at N=400, 800, 1600 (about 4.5x per doubling); a `while` loop before the checks changes nothing (reviewer: 0.84, 3.6, 15.9).
- Cause (verified, `builder.rs` `read_var`): the lazy construction adds a `(var, block)` entry per variable per join between its definition and a read, with a block parameter that is then removed as trivial. N variables x N joins = N² entries.
- Non-goals: reassigned variables (`bad`) keep the existing algorithm, which costs one walk per variable.

## Design

- `declare_single(ty, mode)` returns a `Var` whose value is set by its single `def_var` and returned by every `use_var`/`read_var` (through `resolve`, since the stored value may later be forwarded). A second `def_var` panics.
- Validity: an immutable `let` is defined once and lexically dominates all its uses, so the slow path would also return exactly this value after removing the trivial parameters it adds; no join can carry a different value. Loops do not matter: a `let` inside a loop body is defined on each iteration in the block that dominates its uses.
- Use sites: `bind_local` and `bind_lent` (`crates/ms-lower/src/func.rs`) use it when `!binding.mutable`; `slotify`/closure capture only applies to mutable bindings. Hidden, temporary and loop variables keep `declare_var`.
- Safety net: reading before the definition panics (as the slow path does with "used before it is defined"); defining twice panics, so a lowering path that reassigns an immutable binding fails loudly in `make conform`/`make e2e`.
- Ownership: `Mode::Own` variables carry owned block parameters only at joins; with no parameters the same `Value` flows on, and drops are placed by scopes and the optimizer as before.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir/src/builder.rs` | `declare_single`, direct read | unit test: reads across 1000 joins create no block parameters |
| `crates/ms-lower/src/func.rs` | `bind_local`, `bind_lent` use it for immutable bindings | `make conform`, `make e2e` |
| passes, codegen, runtime, tooling, docs | unchanged | none |

## Alternatives

- Do nothing: Debug N=1600 takes 12.7s; rare but plausible in generated code.
- Fast path in `read_var` keyed on "closed" blocks and a single definition count (first draft): needs closedness over loops (SCC or re-propagation) and loses the "used before defined" check; rejected by review.
- Dominator-based placement (classic SSA) or incremental dominators: asymptotically general, but rewrites the builder; held as a follow-up if reassigned variables turn out to dominate.

## Staging and verification

1. Implement; check `cargo test -p ms-mir`, `make conform`, `make e2e`.
2. Measure Debug N=400/1600 on the repro (6.0s at 1600 after; the remainder is Cranelift register allocation of one huge function, not the builder).
3. Gate: MIR output of the corpus unchanged except renumbering; all fixtures pass; no test gated on any platform.

## Open questions

- None.
