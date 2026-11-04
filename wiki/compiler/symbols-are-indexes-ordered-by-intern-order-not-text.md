[Wiki](../index.md) › [Compiler and build](index.md)

# Symbols are indexes ordered by intern order, not text

Verified: `Symbol` is a `u32` index into an `Interner` that owns its names (`crates/ms-syntax/src/symbol.rs`), so a name's text, display, and alphabetical order need a `Names` handle. `Symbol`'s own `Ord` compares indexes, which is deterministic (intern order follows parse order) but not alphabetical. The editor's member list was the one place that depended on text order; it now sorts with `Names::cmp`.

Rule: output a user or a snapshot sees must sort with `syms.cmp(a, b)` (or on `syms.str(..)` text), never on `Symbol` order. `Names::str` hands out text that lives as long as its interner: forever for the process default, until `unsafe Session::release` for a session. Release only when no `Names`, `Symbol`, or `&str` from the session is used afterward.

Apply when: sorting, `BTreeMap`/`BTreeSet` keys, or `Ord` derives that involve `Symbol`/`Name`; adding a long-lived process that should free its names.
Evidence: [symbol.rs](../../crates/ms-syntax/src/symbol.rs), [proposal](../../proposals/session-owned-interner.md).
Verify: `cargo test -p ms-syntax -p ms-check`.
