# Consuming close: retire the SharedGuard glue special case

Status: **proposal** (2026-10-26, checked against `origin/main` after #1406). Direction (coordinator, relaying Chinmay): prefer a general language or stdlib primitive over Rust-side special-casing; the name-matched `SharedGuard` glue is a workaround (#1422).

## Summary

- #1406 made `SharedGuard.close` hand its payload back without copying, by teaching drop/copy glue in `crates/ms-clif/src/lower.rs` to skip `value` when `held` is false for a record named `SharedGuard[..]`.
- The compiler knows one stdlib type by name; any other type with a moved-out field needs the same hack.
- Proposed: let a closer own the value it closes, so `close` can move a field out and the rest drops at return. No flag, no name match.
- Cost: the checker must allow moving a field out of an owned receiver. Today it rejects it.
- Decision requested: approve the consuming receiver direction (below) or choose an alternative.

## Problem

- Today `var def close()` receives a slot pointer and the caller keeps ownership, so `self.value` cannot be moved out:

  ```
  var def close() -> List[Int]:
      return keep(self.items)
  ```

  fails `ms check` with `cannot move `self.items` out of `self`: only a whole variable can move; take an owned copy with `self.items.clone()`` (verified on `origin/main`).
- The only way to give the payload back without a copy is therefore a runtime "already moved" state that the glue honors.
- Non-goals: changing `lock` semantics, `with` syntax, or `Shared`.

## Design

- Allow a `Closeable` implementation to declare `def close() -> Unit` with an owned receiver: `with` calls it after the block, passing the binding by move. The block is over, so nothing else uses the binding.
- Inside an owned receiver, `self.field` may move at its last use (as `match` on an owned scrutinee already moves payloads); the unmoved remainder drops when `close` returns.
- `SharedGuard.close` becomes `self.box.put(self.value)` with no `held` flag. Closing twice is impossible because the binding is consumed.
- Fault and cancellation: the runtime cleanup stack still holds the live binding. On unwind the thunk calls the same owned `close` on the binding's current value; the cleanup entry is discarded first on normal exit, so it runs once.
- `Closeable` stays `var def close()` for ordinary resources; an owned `close` satisfies a separate contract spelling, to be settled in review.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check` ownership | owned receiver; move of a field out of it at last use | accept and reject cases in `ownership` tests |
| `crates/ms-check` contracts | `with` accepts an owned `close` | conformance fixture |
| `crates/ms-lower` `with.rs` | pass the binding by move; thunk on unwind | existing `with` and `shared`/`tasks-*` fixtures |
| `crates/ms-clif` `lower.rs` | delete `guard_held`/`copy_if` | same |
| `stdlib/sync.ms` | drop `held`; plain move in `close` | `shared-lock-large-payload` |
| docs (`cleanup/closeable.md`) | owned close | `make docs` |

## Alternatives

- Do nothing: keeps a name-matched hack in the compiler; a second type needing it repeats it.
- Generic per-field "moved" bit honored by all drop/copy glue: grows every record and touches all codegen paths for one stdlib type.
- Option-typed payload with an accessor: breaks `guard.value = ...` for users.
- Make `put` take the guard's field through a native that clears it: still needs a defined empty value for droppable `T`, which Manuscript lacks.

## Staging and verification

- Stage 1: checker accepts owned receivers and field moves, with reject cases; no stdlib change.
- Stage 2: lowering for `with`; convert `SharedGuard`; delete the glue; gates `make conform`, `cargo nextest run --workspace`, `scripts/leak-check.sh` on shared/tasks fixtures.
- Go/no-go: leak check stays at 0 and the 20k-task fixture does not regress.

## Open questions

- Spelling of an owned receiver (and whether it can be inferred from a field move in `close`). Recommendation: infer, no new syntax.
- Whether `Closeable` itself should become owned-receiver for all types. Recommendation: no, keep the current contract and let the checker accept either.
