# Close a resource when its binding goes out of scope

## Summary

- Today a `Closeable` binding that is never moved or closed is a compile error (`ownership/walk.rs` `unclosed_resources`, #1526); only `with` or `.close()` closes it.
- Change: that same binding is closed implicitly when its scope exits, exactly as if the rest of the block were wrapped in `with`. No new syntax.
- Cost: one checker fact per binding plus a lowering path that reuses `with_stmt` machinery (`ms-lower/src/with.rs`).
- Decision requested: approve the narrow rule below (never-moved bindings only).

## Status

Proposal, 2026-10-27, against `dcdaee5d`. Direction (Chinmay): "can we follow drop for close? we can avoid with and an indent".

## Problem

- `with let f = open(...):` costs an indent level and a keyword for the common case where `f` lives to the end of the block.
- Forgetting it is a compile error, so the checker already knows every binding that would be closed; it only refuses to act.
- Native handles free the OS resource in Rust `Drop` but skip Manuscript `close()` (flush, shutdown), so drop and `close()` disagree.
- Non-goals: moved resources, fields, collection elements, `Shared[T]` payloads.

## Design

- Rule: a `let`/`var` binding of Resource class (`classify.rs`) that is never moved, captured or closed by hand is closed at scope exit, on every exit (return, `break`, `continue`, error, fault, cancellation), in reverse binding order.
- Moved bindings keep today's rule: the new owner closes them. Conditional moves stay out of scope, so no drop flags.
- Explicit `.close()` or `with` on the binding suppresses the implicit close (no double close).
- Lowering: treat the binding as a `with` whose body is the rest of the block, reusing `CleanupPush`, `closer_for` and `close_call`, so faults and cancellation behave as `with` does.
- `close()` is `var def close() -> Unit`; it cannot return an error, same as `with` today.
- `with` stays valid; it only narrows the close to a sub-block.
- The "never closed" diagnostic is removed; a binding that is moved on some path still needs an explicit close per existing rules.

Before/after:

    # before
    with let f = open(path):
        use(f)
    # after
    let f = open(path)
    use(f)

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` `ownership/walk.rs` | record implicit-close bindings instead of erroring | reject case becomes accept |
| `ms-check` HIR info | `StmtInfo.cleanup` for `let` | golden |
| `ms-lower` `with.rs`, `func.rs` | lower implicit close at the let, scope = rest of block | `tests/lower` expect `call @Res.close` |
| `ms-mir` unwind | unchanged (same `CleanupPush`) | existing |
| formatter, lint, LSP | lint could suggest dropping redundant `with`; optional | none |
| docs `cleanup/scopes.md`, tour | document rule | doc check |
| `ms-rt`, stdlib | unchanged | none |

## Alternatives

- Do nothing: the compile error already prevents leaks; cost is indent and ceremony.
- Full drop glue with drop flags for conditional moves: covers more, but needs flow analysis the checker lacks; defer until the narrow rule proves out.
- Close in Rust `Drop` of native handles: cannot call user `close()`; rejected.

## Staging and verification

- Stage 1: checker + lowering + lower/conformance tests (early return, loop `break`, fault, cancellation, generic bound).
- Stage 2: docs, lint for redundant `with`.
- Gate: `make verify`; every existing `with` fixture still passes.

## Open questions

- Should a conditionally moved binding be an error (recommended, as today) or get drop flags later?
- Should lint flag a `with` that spans the whole remaining block? Recommended: yes, as a suggestion.
