# `close` is an ordinary `move` method

## Summary

- Problem: #4578 made `close` `fn move` but added name-keyed rules to the checker and lowering (`consuming && params.is_empty() && name == "close"` written four times, a close-only use-after-close message, close-only receiver permissions).
- Change (this PR): a close follows the general `move` rules. Its one remaining difference, the in-place calling convention, is decided in one predicate, `Classifier::is_closer`, not by name tests scattered over the walk and call lowering.
- Stage 2 (built): the owned close ABI removes the rest, with a take-and-refill half close.

## Status

Proposal, 2026-11-19, checked at `f0f1c438`. Owner direction: "make sure we're not special casing this, it should be treated as a move, and use consistent terminology".

## Problem

- Verified: #4578 left these close-only rules (`ms-check/src/ownership/walk*`, `ms-lower/src/call.rs`, `mutation.rs`):
  - a use-after-close message of its own (`close_receivers`);
  - mutable permission for the receiver of any `close`;
  - the receiver mode downgraded to `Mutate` so the callee does not drop it;
  - `consuming_close`, `closing_binding_type`, and `takes_self` exceptions for `close`.
- Verified (`design/proposals/elaborate-drops.md`, Stage 3 probe): the elaborate pass models a closer as `fn(move T)`; the in-place close convention (`CloseKind::writes_back`) is what kept resources out of it.

## Design

Stage 1 (this PR):

- `x.close()` is a `move` call. A later use or a second close is the standard use-after-move error. The close-only message and `close_receivers` are gone.
- A `move` receiver may be changed, as a `move` parameter may (general rule, `patterns.rs`); the close-only receiver permission is gone.
- One predicate decides the in-place convention: `Classifier::is_closer(func)`, from the `move close` declarations. It drives the receiver mode, the scope-end skip of `self`, and `infer_mutated`. Call sites ask `Method::is_close_op`, the one definition of "a `close` with no parameters" (also interface operations such as a stream's).
- Not removed: `field.close()` where the holder closes itself, is `self` in a close, or is a `var` receiver closes the field where it lies (`is_part_closed_in_place`), because a part cannot move out of a holder that closes itself or is not owned. This is a half close (`conn.output.close()`), not a move, and the parts close again at the end.

Stage 2 (built, 2026-11-19; Chinmay chose the take-and-refill half close): closers take the value (`fn(move T)`): the scope-end thunk takes the value out of its slot and calls the close; the composite helpers (type, alternative, optional, list, map) take their parts out, close each by value and release the shell. This removes `is_closer`, `consuming_close`, the `takes_self` exception and `is_part_closed_in_place`. `move` means ownership everywhere: a plain parameter the body closes needs `move`. The half close is a partial move of a resource field out of a mutable holder, refilled in the next statement (`Fact::FieldTake`, `FieldRefill`); `ReadStream.end()` and `WriteStream.end()` use it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` ownership walk, `classify`, `types` | delete the name rules and the message; `is_closer`, `is_close_op`; a `move` receiver may change | `make conform`, `close-use-after-close`, `close-twice` fixtures |
| `ms-lower` `call`, `mutation`, `cx` | ask `is_close_op` and `is_closer` instead of names | `make conform`, close-matrix, resource-matrix, `make leak-check` |
| docs, wiki, agent skill | "moves" and "use after move", not "consumes" | `make repo-check` |

## Alternatives

- Do nothing: the diagnostics and rules name `close` in eight places.
- Build stage 2 later (rejected, built now): every part-closing helper in `close.rs` (about 1,750 lines), the cleanup-stack thunks, `elaborate.rs` and `unwind.rs` change together, and the half-close users need a new API first. A stage 1 PR keeps the language rules general at once.
