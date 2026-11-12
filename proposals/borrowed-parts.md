# Borrowed parts: six rules for data that owns data

## Summary

- Problem: whether a result borrows from its receiver is decided by two mechanisms. Methods written in Manuscript are inferred from their body. Built-in methods are decided by a name list (`get first last view split lines chars keys values slice`), repeated in the checker and lowering.
- Change: six rules, the same for every type. Reads borrow, results that are parts borrow, derived results carry their sources, copies are always one explicit `.clone()` away, and lowering picks pointer or value from the type, never from a name.
- Decision requested: approve the rules, and the one open question at the end. Umbrella for `proposals/borrowing-stdlib-bodies.md`.

## Status

Proposal v2, 2026-11-12, against `main` at `2903b18`. Direction (Chinmay): borrow consistently for every type; "write fast code without a whole lot of copies but not prohibit them"; no implicit copies (`views.md`). Builds on `views.md` and `origin-flow-borrows.md`; replaces the special cases listed under Problem.

## Problem

Verified in `crates/`: `ms-check/src/ownership/walk/returns.rs` `native_borrow_receiver` (the name list, plus a type carve-out: `slice` borrows only `Int`, `Float` and `Bool` elements), `list_get` / `map_get` / `entry_get` (names again), `walk/calls.rs` (the list again, twice, plus a name-based exemption near line 250), `ms-lower/src/borrow_shape.rs` (a third copy), `mixed_returns` (one owned path withdraws the borrow, with `list_get` / `map_get` exempted by name), and the MIR verifier (`opt.view` of a boxed optional is refused, so lowering copies where the checker says borrow).

Cost: moving a stdlib method from Rust to Manuscript changes how the checker treats it. The "ms-rt-hot" thread hit this with `first` and `last`.

## Design

1. **Reads borrow.** Naming a part (field, element, entry, slice, view) of a value borrows it from its owner. A shared borrow freezes the owner; `var` is an exclusive borrow. No type or method is special.
2. **A result that is a part borrows.** A function result borrows from an argument (receiver included) when each path that returns a value returns a part of it, or `some`/`ok`/`error` of a part, or forwards one with `?`. Inferred from the body. A path that owns nothing (`none`) does not count against it.
3. **A derived result carries its sources.** A result built from parts (`split`, `keys`, a list of slices) is a new container that holds borrows. It carries the origins of its parts (`origin-flow-borrows.md`), freezes them while live, and needs `.clone()` to be kept past them.
4. **Copies are explicit and never refused.** Keeping a borrow (store in a field, return it from a function that owns its result, capture in an escaping closure) takes `.clone()`. A path that returns a fresh value beside a borrowed part takes `.clone()` on the part. The diagnostic offers the fix. A part moves instead of copying when its owner is a temporary or at its last use.
   Moves: a value with one owner moves instead of copying when it is stored, returned, or bound at its last use; the old name is dead. A borrow never moves anything. A part can move out only when its whole owner goes with it (a temporary, or the owner's last use, and the owner is not read again).
5. **Built-ins follow the same rules.** A built-in is a Manuscript body wherever it can be (`List.first`, `last`, `get`, `Map.get`, `Optional.get`). A body-less native states the same fact in its declaration in `stdlib/intrinsics.ms`, read by the same code as a body summary (`ResultBorrow`). Rust holds no name list.
6. **Only simple types copy implicitly.** The compiler never copies on its own except `Copy`-class values (`Int`, `Bool`, `Float`, enums without payloads). A borrow of anything else is a pointer (`opt.view`, entry pointer, list index), chosen from the type, never from a name. A fallback copy where a pointer is impossible is not allowed: the MIR rule that refuses `opt.view` of a boxed optional must change so the borrow is a pointer to the element (see Open questions).

Cases run against the rules (programs are sketches, not run against a build):

| Case | Verdict |
| --- | --- |
| `fn Stack.top() Node?: if empty: return none; return self.items.get(n)` | Rule 2: borrows `items`. Same as `List.last()`. |
| user `fn Table.first_row() Row?` over a field list | Borrows, no name needed. |
| `parts := text.split(",")` then `text = other` | Rule 3: rejected while `parts` is live. |
| `names.append(parts[0])` | Rule 4: rejected; write `parts[0].clone()`. |
| `fn f(x) String: if c: return x.name; return make()` | Rule 4: reject with fix `x.name.clone()`. Unchanged. |
| `xs.slice(a, b)` of `String` elements | Rule 1 and 3: borrows for any element type, no scalar carve-out. |
| `Node` list with self-containing `Node?` payload | Rule 6: a pointer view, no copy. Needs the MIR change. |
| `m.get(k).get()` on a temporary map | Rule 4: part moves out of the temporary. |

Before and after: a user `fn Deque.back() T?` and the built-in `List.last()` behave identically. Today the first borrows by body and the second by name, and a `none` path in a body makes the user method copy.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` ownership (`returns.rs`, `calls.rs`, `modes.rs`) | Delete `native_borrow_receiver`, `list_get`, `map_get`, `entry_get` and the name lists; read summaries and declarations only; `none` stops withdrawing | `crates/ms-check/tests/ownership/` cases from the table |
| `stdlib/*.ms`, `stdlib/intrinsics.ms` | Bodies for `first`, `last`, `get`; declarations on body-less natives | stdlib fixtures, `make conform` |
| `ms-lower` `borrow_shape.rs` | Key on the checker's `borrowed_reads` fact and the resolved symbol; choose shape only | `borrowed-container-reads.ms` |
| `ms-mir` `verify/types.rs`, `borrow_shape.rs` | Allow `opt.view` of a boxed payload as a pointer to the element; remove the copy fallback | `opt_lastuse.rs`, recursive-node fixture |
| `documentation/core-language/types/references.md` | Replace the stdlib list with these rules | doc checks |

## Alternatives considered

- Do nothing: every method moved to Manuscript needs a new checker exemption.
- Share the name list between checker and lowering: one copy fewer, user types still differ from built-ins.
- Written marker on borrowing methods: contradicts "no marker" and adds syntax.
- Copy whenever a pointer is hard (today's boxed-optional fallback): hides cost, breaks no implicit copies.

## Open questions

- Body-less natives (`split`, `lines`, `chars`, `keys`, `values`, `view`, `slice`): declare in `intrinsics.ms` (recommended, smallest) or rewrite over smaller primitives.
- Boxed payloads: how a view of an element held in a list buffer is represented for a self-containing type. Needs a look at the boxed-optional layout before building.
