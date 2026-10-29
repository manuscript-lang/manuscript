# Shared guard without compiler special cases: a close that consumes the guard

## Summary

- `lock(box)` returns `SharedGuard{box, value, held}`; `close` moves `value` back into the box, so the dead guard still holds stale `value` bits. `crates/ms-clif/src/lower.rs` skips them by matching the record name `SharedGuard[` and the field names (`guard_held`, `copy_if`, the `Rec` cases of `glue_drop` and `glue_copy`) (#1422).
- Change: `SharedGuard.close` consumes the guard, so the guard is gone after the hand-back and nothing stale remains. No flag, no name match, no change to `guard.value` or `lock`.
- Two general pieces make it work: a close that takes its receiver by move (already inferred by the ownership pass; lowering learns to call it), and a record counterpart of `alt.take`/`alt.release` so `clone` of a field of a dying record becomes a move.
- Cost: one new MIR op pair, one lowering path for closes, one prelude function (`drop`). Deleted: `guard_held`, `copy_if`, two glue branches, the `held` field.
- Decision requested: approve the consuming close (no syntax) and the prelude `drop`; the rest is implementation.

## Status

Proposal, 2026-10-29, checked against `origin/main` at `69d78f65`. Direction (Chinmay, relayed): "we need to think correctly about shared without special casing"; prefer a general language or stdlib primitive over Rust-side special cases. This replaces the `SharedGuard` part of `consuming-close.md` (2026-10-26), whose other part (a new owned-receiver contract, rejecting a second `close()` for every `Closeable`) stays parked with `close-is-last-use.md`. Nothing implemented.

## Problem

- Verified: `stdlib/sync.ms` `SharedGuard.close` is `if self.held: self.held = false; self.box.put(self.value); wake`. `Shared.put` moves its argument bitwise (`crates/ms-lower/src/sharedbuilder.rs`, "put").
- Verified: `close` is `var fn`, so the caller keeps the binding and drops it afterwards. `emit_close` (`crates/ms-lower/src/close.rs`) passes the binding's slot to `close` and the scope drops what is left.
- Verified: the stale `value` is skipped by name. `guard_held` returns the `held` flag only for a record whose name starts with `SharedGuard[` and whose fields are exactly `box, value, held`; `glue_drop` and `glue_copy` branch on it (`lower.rs:590`, `679`, `1037`).
- Verified: two more places name the type: `close.rs:397` (do not close the guard's `box` as a part) and `ms-check/src/constfaults.rs:116` (lock-twice detection). Out of scope here; the first falls out of this design (see Components), the second is a diagnostic, not codegen.
- Verified: the checker rejects moving a field out of a record: `cannot move `self.items` out of `self`: only a whole variable can move; take an owned copy with `self.items.clone()``. So a `put(self.value)` that really moves is not expressible, which is why the runtime flag exists.
- Why it matters: any std type that hands a field away on close (a second lock-like type) must copy the hack, and an unflagged copy would be a double drop.
- Non-goals: the `lock` API, `guard.value` field access, `with`, the wait queue, partial moves in user code, changing `Closeable` for other types.

## Design

Rule: a `Closeable` implementation whose `close` consumes `self` is closed by moving the binding into it; the callee owns and drops whatever it does not move.

```manuscript
impl Closeable for SharedGuard[T]:
    fn close() Unit:
        let id = self.box.id()
        self.box.put(self.value.clone())   # a copy, then dropped with the guard: see below
        drop(self)                         # consumes the guard; no stale value remains
        msrt_waitq_wake(id)
```

- **Consuming close, no syntax.** The ownership pass already infers `ParamMode::Consume` for a method receiver that the body moves whole (`owned-parameters.md`, stage 2: methods get an owned entry at direct calls). `drop(self)` is such a move. A plain `fn close()` already satisfies `Closeable` (verified: `impl Closeable for G: fn close() Unit:` checks on `origin/main`).
- **`drop`.** New prelude function `drop[T](value: T) Unit`: consumes its argument, which is dropped at once. The way to end a value's life early; also what lets a method consume `self` without handing it to something else.
- **Lowering of a consuming close.** `bind_closing` records that the close function's receiver is owned (`Func::params[0].mode == Own`). Scope end and `moved_closer` call the owned entry with the binding's value moved out of its local, and the local is marked moved so the scope does not drop it again. The cleanup thunk (fault, cancellation) keeps its current shape: it copies the registered value and calls the owned entry, as `writes_back` does today. Interface (vtable) calls keep the borrowed entry, so they copy.
- **Explicit `guard.close()`.** Calling a consuming method moves the binding (existing rule for a consumed receiver), so `guard.close()` followed by a use is `used after move`, and the scope end does not close it again (`close_moves`). This is the only user-visible change: today a second `close()` is a no-op; for the guard it becomes a compile error. Documented in `closeable.md` for implementations with a consuming close.
- **Clone-then-drop becomes a move.** `self.value.clone()` followed by the drop of `self` is `rec.get; copy; …; drop g`. A new MIR pair `rec.take f g` / `rec.release g mask` rewrites it, exactly as `copyelim::run_takes` does for `alt.get; copy; drop` (`crates/ms-mir/src/opt/copyelim.rs`): the taken field moves into the copy's place, `release` frees the record and drops the fields that were not taken. Semantics without the pass is still correct (copy, then drop), so the pass is an optimization, not a contract. Conditions: the source record is owned, dies at the `drop`, is not used between except through other `rec.get`s of fields that are not taken, and each taken field is read once.
- **Fault and cancellation.** `put` still faults on a box that was not taken; a cancelled close leaves the cleanup entry, which copies as today. Shielding (`msrt_shield_enter`) around the close is unchanged.
- **Wake order.** `id()` is read before the guard is consumed; the wake runs after `put`, as today.

Before/after, user code is identical:

```manuscript
import lock from "@std/sync.ms"
import share from "@std/shared.ms"

export fn main() Int:
    let box = share([1, 2, 3])
    var guard = lock(box)
    guard.value.append(4)
    return 0
```

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/core.ms`, `bindings.json` | prelude `drop` (consumes) | e2e: consumed binding is dropped once; reject: use after `drop` |
| `stdlib/sync.ms` | `SharedGuard` loses `held`; consuming `close` as above | existing `shared`, `tasks-*`, `shared-lock-large-payload`, `implicit-close-shared` |
| `crates/ms-lower` `close.rs` | owned-receiver `CloseKind`; `emit_close`/`moved_closer` move the local; the part-closer special case for `SharedGuard` (`close.rs:397`) goes if `box` closes harmlessly, else stays as a follow-up | e2e close order, leak check |
| `crates/ms-lower` `sharedbuilder.rs` | `put` comment no longer mentions the guard flag | unchanged behavior |
| `crates/ms-mir` | `Op::RecTake`, `Op::RecRelease`; verifier, interpreter, `run_takes` for records | MIR unit tests (taken, not taken, field read twice, use between) |
| `crates/ms-clif` `lower.rs` | lower the two ops; **delete** `guard_held`, `copy_if`, the `Rec` branches that use them | `cargo nextest run --workspace`, `scripts/leak-check.sh` |
| `crates/ms-check` | none expected; consumed receiver and `close_moves` exist. Verify `guard.close()` then use is rejected. | reject fixture |
| docs `cleanup/closeable.md`, `stdlib/sync.ms` comments | consuming close; a second `close()` is an error for it | `make docs` |

## Alternatives

- **Do nothing.** Keeps a name-matched hack in the compiler; each future type that hands a field away repeats it. The cost is small today (about 40 lines in `lower.rs`) and real only on the next such type; this is a design-hygiene change, not a speed change. It must still pass the do-nothing test on removable code and generality, not on speed.
- **Generic per-field moved bit in all glue.** Grows every record, touches every drop and copy path, for one type. Rejected (issue comment, 2026-10-26).
- **`value: T?` internal with an accessor.** Changes the public `guard.value` API and ~31 call sites; a language-level call, not needed here.
- **Guard aliasing the box's payload (Rust `MutexGuard`).** Needs a place projection (`guard.value` as an alias of the box slot) that the language does not have; large.
- **General partial move out of a record.** A new checker and drop-elaboration feature for user code (the guide says "a field or element cannot move out"); too large for one stdlib type, and conditional moves add drop flags. Clone-then-drop plus the optimizer gives the same machine code for the unconditional case without a language change.
- **New owned-receiver contract for all `Closeable`.** Parked (`close-is-last-use.md`): the documented idiom closes a field (`task.channel.close()`), and about 13 tests rely on close being idempotent. This design leaves ordinary `var fn close()` types alone; only a close that consumes `self` is affected.

## Staging and verification

1. `rec.take`/`rec.release`: MIR, clif, interpreter, `run_takes` over records; unit tests; no source change. Gate: workspace tests, conformance unchanged, binary identical for programs without the pattern.
2. Prelude `drop` and consuming-close lowering (`emit_close`, thunk, `moved_closer`); a user type with a consuming close in an e2e fixture (fails before, passes after); reject fixture for use after `close()`.
3. Convert `SharedGuard`; delete `held`, `guard_held`, `copy_if`. Gates: `make conform`, `cargo nextest run --workspace`, `scripts/leak-check.sh` on shared and tasks fixtures (0 leaks), `shared-lock-large-payload` time not worse than today (20k tasks, 100k-element list locks; today 2.9 s, 0 ms per large lock), clippy, fmt.
- Go/no-go: if stage 1 does not turn the guard close into a move (the 100k-element lock becomes O(n) again), stop and report rather than add a guard-specific rule.

## Open questions

- Name `drop` for the prelude function: recommended; `List.drop(count)` is a method and does not collide.
- Whether to also remove `close.rs:397` in this change: recommended if the leak check stays at 0, otherwise tracked as its own issue.
