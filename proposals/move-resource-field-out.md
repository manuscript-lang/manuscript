# Move a resource field out of an owned record

## Summary

- Problem: `xs.append(r.door)` with `r` an owned record and `door` a `Resource` is rejected (#2008), although the move is deterministic and a resource cannot be cloned. The only workaround is restructuring.
- Change: accept the move at the field's last use when no record on the path declares its own `close`. The field is moved, not copied. At scope end the record closes only the fields not moved, using one drop flag per moved place when a path moves it and another does not.
- Cost: no syntax, no new type, no MIR op. A binding with a moved resource field registers one cleanup entry per resource field instead of one for the whole record.
- Gate: the #1991 count harness and fixtures for branches, loops, early returns, `try`, nested fields, close order and faults.
- Decision requested: none user-visible beyond #2008 (Chinmay: "if we can move deterministically let's not require clone").

## Status

Implemented, 2026-10-30 (#2008), against `6a9ca18f`. Builds on [field-ownership-dataflow](field-ownership-dataflow.md) (#1991, #1997), whose open question "Resources: should a plain record that holds a Resource field allow moving that field out?" it answers yes. Chinmay: "make sure this is solid, i was thinking from cpp perspective where this might result in free after move" and "we do have a close method that gets called similar to destructors". Soundness claim: every resource is closed exactly once, and no storage is dropped twice.

## Problem

Verified on `6a9ca18f` with `ms check`:

```manuscript
type Room:
    door: Door
    tag: String

fn take(r: Room) List[Door]:
    var xs: List[Door] = []
    xs.append(r.door)    # error: cannot move the resource `r.door` out of `r`
    return xs
```

- `walk.rs` `partial_move` returns false for `Class::Resource`, and the caller reports the error.
- Lowering of an accepted `Move`-class field move still copies (`FnLower::owned`), which is fine for plain data. For a resource a copy would be closed twice (once through the record, once by the new owner): the C++ free-after-move hazard.
- Non-goals: elements (`xs[i]`, use `pop`/`remove`); records with their own `close`; `var` bindings and `var` parameters; receivers; `ref` results.

## Design

**Rule:** a field place `b.f` (or `b.f.g`) of `Class::Resource` moves out of an owned `let` binding or by-value parameter `b` at its last use (same per-place liveness as #1997), provided no record along the path declares `close` itself. Everything else about #1997 stays: later use of the place or of `b` is "moved here but used again", a closure capture of `b` is rejected, a loop that moves without leaving is rejected.

```manuscript
fn take(r: Room) List[Door]:
    var xs: List[Door] = []
    xs.append(r.door)    # accepted: r.door moves; r.tag still belongs to r
    return xs            # r closes nothing: it holds no other resource
```

Semantics, one per bullet:

- **Who closes.** The new owner closes the moved value. The record's scope closes every resource field that was not moved, last declared first, then releases the record's storage without the moved leaves. Order among the remaining fields is unchanged ([close-owned-parts](close-owned-parts.md)).
- **Why no record `close`.** A record's own `close` runs first with `self` whole; a hole would be visible to it. A record with its own `close` stays rejected with today's message. A moved resource may itself have a `close` (it is the new owner's duty).
- **Branches.** Each moved place `p` gets a `Bool` flag, true at binding, false at the move. Scope end tests the flag: `if held(p)` close `p` and release it with the record. A path that never moves `p` closes it exactly as today.
- **Loops, `break`, `return`, `try`.** Every exit runs the same scope-end code, which reads the flags. The checker's last-use rule already rejects a move that can reach itself again, so a flag is cleared at most once per path.
- **Faults and cancellation.** Today one `CleanupPush` entry closes the whole record. A binding with a moved resource field instead registers one entry per resource field (in declaration order, so the stack closes last-declared first). The move discards that field's entry before the new owner takes the value, as `moved_closer` does for a whole binding. The scope end discards the remaining entries.
- **Storage.** The moved leaf is taken with `move.out` (a bit move, no copy). The remaining leaves are dropped with `move.out` + `drop` per leaf, or `rec.release` with a mask when the record is flat; a moved leaf is never dropped through the record. A moved place under a flag releases through a branch on the flag; the flag count is bounded by the number of moved places in the binding.
- **Whole move on another path.** A path that moves `b` whole (`close_moves`) clears the whole-binding flag as today and discards every entry; partial and whole moves cannot both reach one point (use after move).
- **Parameters.** As in #1997, a partial move marks the parameter `Consume`; the callee closes the rest (`implicit_closes`).

Rejected, with a remedy: a record with its own `close` ("`R` closes itself; move the whole `r`, or take the part with a method on `R`"), a `var` binding or `var` parameter, an element, a `ref` result, a closure capture.

## Changes after skeptic review

- **Roles.** Only `Role::Let` and `Role::Parameter` owners qualify, checked explicitly; `for` variables, pattern and arm payloads, `var` bindings and receivers keep the old rejection (their cleanup runs through `rest_closers`, `moved_payloads` and `if let`, not `Closer`). Reject fixtures for each.
- **"Declares `close`".** Today's guard (`class(holder) == Resource`) rejects every holder that merely holds a resource. The checker needs a real `Closeable` impl test per holder on the path, defined once and covering impls in other files; a holder whose impl cannot be seen is rejected.
- **Parameters.** `mark_mutated` can select the `own_copy` branch of parameter binding (`func.rs`), where the callee closes a copy while the caller closes the original. A resource-field move must force the owned path (`consumed` plus `implicit_closes`); lowering errors if `owned_mask` is absent for such a parameter, and a fixture calls the function directly and through an interface/function value. `resource_moves` feeds the flag logic itself, because partial moves are recorded as `Access::Borrow` and do not reach `close_moves`.
- **Release.** `rec.release` takes a static mask, so flagged leaves are not released through it. Scope end drops every unmoved leaf with `move.out` + `drop` and tests the flag around each possibly-moved leaf (linear in leaves, no 2^k variants). A plain `Op::Drop` of the record never runs for such a binding. A binding may not move both a place and a place nested under it (checker error).
- **Unwinder/verifier.** An unfilled `move.out` is accepted by the verifier (types only) and already produced by `copyelim` (`rec.release`); the `move.out` doc comment is updated to say a refill is optional when the record is released afterward.
- **Shapes.** Member paths through `Optional`, `List` and alternatives stay rejected (`field_path`). Fixtures: `Shared` field, a nested record with two resource fields, `Closeable` impl in another file, Debug and Release counts.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check/src/ownership/walk.rs` | `partial_move` accepts `Class::Resource`; rejects only holders that declare `close`; records `resource_moves` | `tests/ownership/accept/partial_move_resource.ms`; reject cases for own `close`, `var`, used-again, closure, loop |
| `crates/ms-check/src/ownership/mod.rs`, `lib.rs`, `checker.rs` | export `resource_moves` (member node to place) to the program | unit/e2e |
| `crates/ms-lower` (`cx.rs`, `close.rs`, `expr.rs`, `func.rs`) | per-field entries and flags for a binding with moved resource fields; member expression emits `move.out` and discards the entry; scope end closes unmoved fields and releases the record | e2e fixtures, count harness |
| `crates/ms-mir` | unchanged (`move.out`, `rec.release`, `drop.if` exist) | verifier runs on every fixture |
| `ms-tooling` (lint `flush`), LSP, formatter, parser | unchanged; flush lint reads `close_moves`, which partial moves do not touch | `make verify` |
| `crates/ms-check/OWNERSHIP.md`, `documentation/core-language`, `mistakes.txt` | rule text, the resource error becomes a rejection only for the cases above | `make docs-check` |

## Alternatives

| Option | Verdict |
| --- | --- |
| Do nothing | Users restructure around a deterministic move; #2007 already improves the message. Rejected by Chinmay's rule. |
| Copy the field and keep closing the original (as `Move` fields do) | Closes the resource twice, or the copy never closes: exactly the free-after-move failure. Rejected. |
| Close the moved field's record eagerly at the move | Changes close order and breaks use of the other fields. Rejected. |
| One thunk with a mask registered once | The cleanup stack passes one value; the mask would need a new slot type. More machinery than per-field entries. Rejected. |
| Allow records with their own `close` | The close sees a hole. Needs a separate design (`take`-style method). Out of scope. |

Drawbacks: one more entry on the cleanup stack per resource field for affected bindings; a function using this keeps a `move.out` hole open, which makes the unwinder skip registering other values across later calls (leak on cancellation only, never a double free; same as the existing hole rule).

## Staging and verification

1. Checker facts and acceptance plus lowering in one PR (the checker alone would produce a double close). Gate: `make verify`, `cargo nextest run --workspace`, `make count-check`, `make leak-check`.
2. Fixtures (`tests/ownership-counts/resource_field_move*.ms`, each asserts the exact close sequence and zero live blocks in Debug and Release): move in a branch (both arms), loop with `break` after the move, early `return`, `try` exit before and after the move, nested field, two moved fields in either order, conditional move of one of two, whole move on one branch and partial on another, fault between entries (guarded task).
3. Go/no-go: any fixture closing a resource twice or not at all, or any leak, stops the change.

## Open questions

None for the owner.
