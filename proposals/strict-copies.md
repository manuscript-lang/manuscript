# Strict copies: lowering emits a copy only where the checker recorded one

## Summary

- Problem: `FnLower::owned` (`crates/ms-lower/src/func.rs`) emits `Op::Copy` whenever a borrowed value lands in an owning position, and the MIR optimizer (`copyelim`, 1,511 lines, nine sub-passes, plus parts of `lastuse`, `optparam`, `strfuse`) turns most of them back into moves or borrows. That is an implicit copy the one-owner model forbids, repaired by passes.
- Change: (1) a strict-copy gate: `owned` on a borrowed place is an internal lowering error; the only copies are `.clone()`, static materialization (string literal, `none`), and checker-recorded conversions. (2) A dense per-node `NodeFacts` table replaces the 17 `Rc<HashMap/HashSet>` ownership side tables so lowering reads one record per node. (3) Delete the `copyelim` sub-passes that stop firing.
- Decision requested: none (no language or user-visible change). Audit items 1 and 8 of `compiler-hacks-audit-2026-11-03`.

## Status

Proposal; stage 1 (gate, opt-in) in #2474; stage 2 begun: the six node-keyed boolean sets are one `NodeFacts` table and the binding-keyed boolean sets (`borrows`, closes, `moved_payloads`, `conditional_moves`) one `BindingFlags` table, 2026-11-03, checked against `e222a770`. Direction (Chinmay): "no implicit copying"; the compiler must follow the one-owner model itself.

## Problem

Measured (`e222a770`, `MS_COPY_TRACE` over 150 `tests/e2e/testdata/accept` fixtures run with `ms test`, stdlib included): 3,404 `owned()` copies emitted by lowering.

| Producer of the copied value | Copies | Meaning |
| --- | --- | --- |
| `StrLit` | 2,615 (77%) | literal into an owning slot: static materialization, not a borrow of a place |
| `OptNone` | 174 (5%) | owns nothing; a null check |
| `Load`, `AltGet`, `OptGet`, `RecGet`, `ListGet`, `Call`, `CallRt`, unknown | ~560 (16%) | borrowed place or result in an owning position: the real implicit copies |

Top sites for the last row: `native_method_tail` (argument to an owning native parameter), `result_method` closures (payload of a borrowed `Result`), `member`, `call_callable`, `lambda`, `list_source`.

## Design

- `owned(x)` keeps three exits: owned already or no drop duty (unchanged); static (`StrLit`, `OptNone`) goes through a new `own_static`; anything else is a gate failure. `clone(x)` is the explicit entry for `.clone()` and recorded conversions.
- Gate failure records `internal: implicit copy of a borrow in <fn> at <pos>` and fails lowering. Stage: first behind an env switch while the ~560 firings are fixed per site, then unconditional.
- Each fixed site takes one of: a move (the checker already proved last use, `moves`/`close_moves`), a borrow (the callee parameter is borrowed), or a checker fact that was missing (add it to the walk). No site gets a copy "to be safe".
- `NodeFacts` (stage 2): `Vec<NodeFacts>` per module indexed by `NodeId`: a `u32` bitset (borrow kind, implicit/explicit close, moved payload, conditional move, view lender/wrap/move, lent match, bound borrow) plus an index into a side `Vec` for payload facts (`close_moves`, `resource_moves`, `getter_borrows`, `owned_lends`). `(Name, NodeId)` keys become the node's id; `Name` is already in the node.
- After the gate is on, delete the `copyelim` sub-passes whose `opt_copyelim` tests no longer exercise a copy, then `buildmove` and the copy cases of `lastuse`. `lastuse` stays for drop placement. `Op::Copy` loses the `rc` effect flag.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-lower/src/func.rs` and callers of `owned` | gate, `own_static`, `clone`; fix ~560 firings | corpus with `MS_STRICT_COPIES=1`, `cargo nextest run -p ms-lower` |
| `ms-check/src/ownership/walk.rs`, `checker.rs` | missing facts; later `NodeFacts` | `tests/ownership-counts` |
| `ms-lower/src/cx.rs` | read `NodeFacts` | `make verify-full` |
| `ms-mir/src/opt/copyelim.rs`, `mod.rs`, `lastuse.rs` | delete dead sub-passes | `crates/ms-mir/tests/opt_copyelim.rs` shrinks with them |
| unchanged: runtime, stdlib `.ms`, codegen | | |

## Alternatives

- Do nothing: the passes work, but each missed pass is a silent allocation, and the refcount-removal thread keeps finding second references. The gate turns a missed fact into a build failure.
- Only count copies (stage a) and keep the passes: leaves the model unenforced.
- Make `Op::Copy` illegal in the verifier: too late; the position is gone by then.
- Facts table first, gate later: the table is a refactor with no behavior check; the gate tells which facts are missing.

## Open questions

- Literal materialization: a borrowed static string into an owner copies bytes. Kept as `own_static` here; interned/static-backed strings would be a separate runtime change.
