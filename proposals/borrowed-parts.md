# Borrowed parts: one rule for results that point into owned data

## Summary

- Problem: whether a method's result borrows from its receiver is decided by two different mechanisms. Methods written in Manuscript are inferred from their body. Built-in methods are decided by a hard-coded name list, repeated in lowering.
- Change: one rule for every type. A result borrows from an argument when its value is a part of that argument. The checker reads this from the callee's body (or, for a body-less built-in, from its declaration), never from a method name.
- Decision requested: how a body-less built-in declares that it borrows (see Open questions). Umbrella for `proposals/borrowing-stdlib-bodies.md` (the "ms-rt-hot" thread), which implements the checker half.

## Status

Proposal, 2026-11-12, checked against `main` at `2903b18`. Direction (Chinmay): "if a type has a method that returns part of that type, it always borrows", for built-in and Manuscript types alike. "Borrow", not "lend".

## Problem

Verified special cases (all in `crates/`):

| # | Where | What it special-cases |
| --- | --- | --- |
| 1 | `ms-check/src/ownership/walk/returns.rs` `native_borrow_receiver` | Name and arity list: `get`, `first`, `last`, `view`, `split`, `lines`, `chars`, `keys`, `values`, `slice`. A Manuscript type with a method called `first` is judged by its body; a built-in is judged by its name. |
| 2 | `returns.rs` `list_get`, `map_get`, `entry_get` | Same names again, to decide which natives count as "the element itself" in `borrow_source`. |
| 3 | `walk/calls.rs` (about lines 386, 446, 470) | Repeats the names `view split lines chars keys values slice` to report "borrows X, which this position would keep". |
| 4 | `walk/calls.rs` (about line 250) | A native receiver that already borrows is exempt from the "would copy out of a collection" error, by name. |
| 5 | `slice` in #1 | Borrows only when the elements are `Int`, `Float` or `Bool`. A type-specific carve-out inside a name rule. |
| 6 | `ms-lower/src/borrow_shape.rs` `borrowed_shape` | Third copy of the list (`get`, `first`, `last` only). Lowering re-derives from names what the checker already recorded as `borrowed_reads`. |
| 7 | `walk/returns.rs` `mixed_returns` | Once any path of a body owns something, the borrow is withdrawn and the part is copied out. `list_get` and `map_get` are exempted by name from the part that makes this an error. |
| 8 | `ms-mir/src/verify/types.rs` (`opt.view` rule) and `borrow_shape.rs` (`opt_is_boxed`) | An optional of a boxed (self-recursive) payload cannot be a view, so lowering silently copies while the checker says "borrow". |
| 9 | `modes.rs` (`method_modes`, `Native::Source` tests) | Source callables use inferred summaries; everything else uses a separate native path. |

Effects: a stdlib method moved from Rust to Manuscript changes how the checker treats it (the "ms-rt-hot" thread hit this with `first`, `last`). Repro shape: a method that returns `none` on one path and `self.get(0)` on another is judged "builds a new value" and stops borrowing.

## Design

One rule, stated once:

> A call's result borrows from an argument (receiver included) when, on every path that returns a value, the returned value is a part of that argument. Paths that own nothing (`none`, `empty` forms) do not count. A path that returns a freshly built value makes the result owned.

- Parts are: the argument itself, a field chain of it, an element or entry of it, `ok(part)`, `error(part)`, `some(part)`, and a `?` forwarding one. Nothing else.
- The rule is the same for built-in and Manuscript types. Built-ins are Manuscript bodies where possible (`List.first`, `List.last`, `List.get`, `Map.get`, `Optional.get`), so they need no special treatment.
- A body-less built-in carries the same fact as a declaration in `stdlib/intrinsics.ms`, read by the same code that reads a body summary (`ResultBorrow`). Rust holds no name list.
- Case 5: `slice` borrowing only scalar elements is replaced by the general rule: the result borrows; a position that must own it clones, like any borrowed part.
- Case 7: `none` stops cancelling the borrow. Mixed borrow and fresh value still makes the result owned, as today.
- Case 8: a borrow of a boxed payload is a borrow in the checker. If lowering cannot show it as a view, it copies; this is allowed only for payloads with `clone` (a copy a program cannot observe). A boxed payload with no `clone` is rejected where it would be kept, with the usual "clone or read in place" fix. Needs a decision before build (see Open questions).
- Lowering stops matching names. `borrow_shape.rs` keys on the checker's `borrowed_reads` fact plus the resolved stdlib symbol, and only chooses the emission shape (entry pointer or list index).

Before and after (sketch, not yet run against a build):

```manuscript
type Stack:
    items: List[Node]

fn Stack.top() Node?:
    if self.items.length() == 0:
        return none
    return self.items.get(self.items.length() - 1)
```

Before (hypothesis, per the "ms-rt-hot" thread; not yet reproduced here): the `get` path is withdrawn because another path returns `none`, so `top` returns a copy and `Node` must be clonable. After: `top` borrows `items`, like `List.last()`. Changing the stack while the result is held is rejected, identically for the built-in `last()`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` ownership (`returns.rs`, `calls.rs`, `modes.rs`) | Delete `native_borrow_receiver`, `list_get`, `map_get`, `entry_get`, and the name lists in calls.rs; read summaries and declarations only | `crates/ms-check/tests/ownership/` accept and reject cases for `first`, `get`, `slice`, `split` |
| `stdlib/intrinsics.ms`, `stdlib/*.ms` | Borrow declarations on body-less natives; `first`, `last`, `get` as bodies | stdlib fixtures; `make conform` |
| `ms-lower` `borrow_shape.rs` | Key on checker fact, drop name matching | `borrowed-container-reads.ms` |
| `ms-mir` `verify/types.rs` | Unchanged unless the boxed decision goes the second way | `opt_lastuse.rs` |
| `documentation/core-language/types/references.md` | Replace "the standard library follows the same rule" list with the one rule | doc checks |

## Alternatives considered

- Do nothing: every stdlib method moved to Manuscript needs a new checker exemption.
- Keep the name list but share it between checker and lowering: removes one copy, keeps the inconsistency for user types.
- A written marker on every borrowing method: contradicts the current rule that borrowing needs no marker.

## Open questions

- Body-less natives (`split`, `lines`, `chars`, `keys`, `values`, `view`, `slice`): keep them as declarations, or rewrite them in Manuscript over smaller primitives? Declarations are smaller; bodies are more uniform. Recommend declarations.
- Boxed payloads: copy when clonable and reject otherwise (recommended), or make `opt.view` work on boxed optionals?
