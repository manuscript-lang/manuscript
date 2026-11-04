[Wiki](../index.md) › [Language](index.md)

# Ownership vocabulary is own, borrow, move, clone, capture

Decision (Chinmay, 2026-11-03): code, diagnostics and docs use five words. Own: one holder frees the value. Borrow: access without taking it, shared or `var`-exclusive; a function that returns a part of an argument "returns a borrow". Move: ownership transfers at last use; parameter mode `Move`. Clone: `.clone()`, the only explicit duplicate; "copy" means only the implicit duplicate of a plain (scalar) value (`Class::Copy`, `Access::Copy`). Capture: a non-escaping closure borrows, an escaping or `promise(fn:)` closure moves in.

Apply when: naming a type, field, op or diagnostic in ownership code, or writing docs. Do not reintroduce "lend", "borrow-returning function", "consume", "clone", "snapshot", or `.copy()`; "view" names only the interface-view representation (`iface.view`, `Fact::ReturnsView`).
Evidence: [ownership notes](../../crates/ms-check/OWNERSHIP.md), [glossary](../../documentation/glossary.md), `ParamMode::Move`, `OwnedBorrow`, `Op::Clone`, `Mode::Move`, `Perm::ClosureOwned`.
Verify: `grep -rniE "\blend|borrow-returning function|consuming param|clone" crates documentation` finds no ownership use.
