# Session-owned symbol interner

## Summary

- Problem: `Symbol::intern` leaks every identifier into a process-wide table (`symbol.rs`, `Box::leak`, audit item 12). Nothing frees names, so a long-lived LSP grows with every distinct identifier typed.
- Change: a safe `Interner` (one byte buffer, one end offset per name, an open-addressed `u32` slot array) owned by a session, with `Sym(u32)` ids read through `interner.str(sym)`. Dropping the session frees its names.
- Decision requested: none (no language change); owner approved the session-owned design in thread.

## Status

Stage 1 (#2536, merged): the `Interner` and `Sym` types with tests. Stage 2a (#2536): the `Names` handle in the ms-syntax parser and dump. Stage 2b (this PR): every crate reads and interns identifier text through a `Names` handle (`Checker`, `Program`, `Cx` and `FnLower` hold one; free functions take it as a parameter) and checker `Type`, `Step` and `VtableKey` print through `display(syms)` / `name(syms)` instead of `Display`. `Symbol` still has its process-wide table, so behavior is unchanged. Stage 3 flips `Symbol` to an index into the session `Interner`, makes `Names` borrow it, removes `Symbol`'s `Display`, `Deref` and `as_str`, and gives `Ord` an explicit by-text comparator where sorted output depends on it.

## Problem

Measured by parsing: the stdlib (3,166 lines) interns 740 names (6 KB). 20,000 reparses that each introduce one new 8-character name grew the table from 740 to 20,741 names and 135 KB of text, about 7 bytes of text per name plus table overhead; repeated edits of known names add nothing. In the LSP every partial identifier typed counts, so growth is slow but unbounded.

## Design

- `Interner`: `bytes: String`, `ends: Vec<u32>`, `slots: Vec<u32>` (0 is empty; id 0 is the empty string). Intern hashes the text once and compares ids; no `Rc`, `Box`, `unsafe` or lock.
- `Sym(u32)` is plain data: `Copy`, `Eq`, `Hash` on the integer.
- A session (the checker session from #2488; the LSP workspace) owns one `Interner` and drops it with the session.
- `Symbol`'s `Display`, `Debug` and text `Ord` need the interner, so each consumer takes `&Interner`. Sorted output stays by text.

## Stages

1. `Interner` and `Sym` with tests (this PR).
2. Parser and AST produce `Sym`; syntax-crate consumers read through the interner.
3. Checker (`Name`), lowering, tooling and LSP move over; delete `Symbol` and the `Box::leak` table.

Each stage keeps `ms check`, `ms emit` and the conformance corpus byte-identical.

## Alternatives

- Do nothing: bounded per run, but the LSP leaks for as long as it lives.
- Unsafe arena in `symbol.rs`: removes per-string allocation but never frees; the workspace denies `unsafe_code`.
- Keep `&'static str` and reset the table per workspace: unsound while any `Symbol` outlives the reset.
