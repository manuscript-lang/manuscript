# Session-owned symbol interner

## Summary

- Problem: `Symbol::intern` leaks every identifier into a process-wide table (`symbol.rs`, `Box::leak`, audit item 12). Nothing frees names, so a long-lived LSP grows with every distinct identifier typed.
- Change: a safe `Interner` (one byte buffer, one end offset per name, an open-addressed `u32` slot array) owned by a session, with `Sym(u32)` ids read through `interner.str(sym)`. Dropping the session frees its names.
- Decision requested: none (no language change); owner approved the session-owned design in thread.

## Status

Stage 1 (#2536): the `Interner` and `Sym` types. Stage 2a (#2536): the `Names` handle in the ms-syntax parser and dump. Stage 2b (#2541): every crate reads and interns identifier text through a `Names` handle, and checker `Type`, `Step` and `VtableKey` print through `display(syms)` / `name(syms)`. Stage 3 (this PR): `Symbol` is a `u32` index into an `Interner` that owns its names; `Names` is a `Copy` handle to one interner; `Symbol` no longer has `Display`, `Deref`, `as_str` or text `Ord` (`Names::cmp` orders by text where output is sorted). The process-wide `Box::leak` table is gone. Stage 3 merged as #2544. Stage 4 (this PR): the language server holds an `ms_syntax::Session` and, between messages, starts over with a fresh one when its table passes 1 MiB of text: it drops its analyses and standard-library session, enters the new table, and releases the old one. `tests/name_recycling.rs` drives 300 edits with unique 100-byte names past a small limit and checks that later names leave the process default table and that every response equals a server that never recycles.

## Problem

Measured by parsing: the stdlib (3,166 lines) interns 740 names (6 KB). 20,000 reparses that each introduce one new 8-character name grew the table from 740 to 20,741 names and 135 KB of text, about 7 bytes of text per name plus table overhead; repeated edits of known names add nothing. In the LSP every partial identifier typed counts, so growth is slow but unbounded.

## Design

- `Interner`: a `Mutex`-guarded table of owned heap strings plus an open-addressed `u32` slot array (id 0 is the empty string). `intern` hashes once and compares ids. Dropping an interner frees every name.
- `Symbol(u32)` is plain data: `Copy`, `Eq`, `Hash`, `Ord` on the integer. `Names(&'static Interner)` is the handle: `intern`, `str`, `cmp`.
- The process default interner is never freed. A `Session` owns a leaked interner and frees it with `unsafe fn release`, whose contract is that no `Names`, `Symbol` or `&str` from the session is used afterward. Dropping a `Session` without releasing it leaks, which is safe.
- `Session::enter` makes a session current on a thread so `n(..)` and `Names::global()` reach it.
- The one `unsafe` module is `symbol.rs`: it extends a name's lifetime past the lock guard, and frees names on drop. The change adds it to the `unsafe_boundary` allowlist.

## Stages

1. `Interner` and `Sym` with tests (this PR).
2. Parser and AST produce `Sym`; syntax-crate consumers read through the interner.
3. Checker (`Name`), lowering, tooling and LSP move over; delete `Symbol` and the `Box::leak` table.

4. The language server recycles its name table (drop caches and the library session, release the interner, start a new one) when it exceeds a bound (this PR).

Each stage keeps `ms check`, `ms emit` and the conformance corpus byte-identical.

## Alternatives

- Do nothing: bounded per run, but the language server leaks for as long as it lives.
- Safe table with `Rc<str>` or `Arc<str>` names: no `unsafe`, but every text read clones a counter and returns an owned handle, which changes about 950 `Names::str` call sites and slows the checker.
- `Names<'a>` borrowing the interner: fully checked by the compiler, but every structure holding a handle gains a lifetime and the language server's cached analyses become self-referential.
- Keep `&'static str` and reset the table per workspace: unsound while any `Symbol` outlives the reset.
