# Shared guard that hands its payload back without copying

Status: **implemented** (2026-10-26, checked against `fe773726`). Direction (coordinator, relaying Chinmay): fix #1381 with a small, general primitive, keep as much as possible in Manuscript. Skeptical review: the first draft (a guard that edits the payload in place) did not hold; it made the guard a copyable handle to one mutable payload, so a stale or duplicated guard could write to the box after close, and it left the `TaskGroup` registry's linear `remove` untouched. This version follows the reviewer's smaller design.

## Summary

- Every `with var g = lock(box):` copied the payload twice, so lock cost was O(payload size) and a `TaskGroup` of n tasks was O(n²) (#1381).
- Change: the `with` close works on the binding's own value (no copy), and `SharedGuard.close` moves its `value` into the box; the closed guard's glue neither copies nor drops the stale `value`.
- No new syntax or type; user code is unchanged. `TaskGroup.results` collects in one pass.
- Measured (release, Linux): 1,000 locks of a 100k-element list 129 ms to 0 ms; 40k tasks 105 s to 2.9 s; 100k tasks 6 s.

## Problem

- `close_call` (`crates/ms-lower/src/with.rs`) copied the guard before `var def close`, then dropped the copy.
- `SharedGuard.close` (`stdlib/sync.ms`) ran `self.box.put(self.value)`, and `put` copied its borrowed argument.
- `TaskGroup.results` forgot entries one at a time (`remove(0)`, a memmove of the whole registry each).
- Non-goals: changing `lock` semantics, `Shared.get`, or `with` syntax.

## Design

- `with` close (normal exit): for a `var def close` the binding's value is passed to `close` through its slot (a slotted `with var`) or moved into a temporary slot and moved back (no copy). The scope still drops what close leaves.
- `Shared.put` (callable only from `@std/sync.ms`) moves its argument bitwise. Its one caller, `SharedGuard.close`, clears `held` first.
- Glue for a record named `SharedGuard[..]` with fields `box, value, held`: drop and copy skip `value` when `held` is false. The cleanup-thunk copy in `close_call` is unchanged: it runs on faults and cancellation only.
- `TaskGroup.results` collects the registry snapshot by index and drops the collected prefix once (`forget_first`).
- Cancellation: unchanged. The guard's `with` cleanup closes it; a cancelled close leaves `held` set and the payload in the guard.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-lower` `with.rs`, `sharedbuilder.rs` | close without copy; `put` moves | `shared-lock-large-payload`, existing `shared`, `tasks-*` |
| `crates/ms-clif` `lower.rs` | closed-guard glue skips `value` | same |
| `stdlib/tasks.ms` | `results` one pass | `shared-lock-large-payload` (20k tasks) |
| `stdlib/sync.ms`, `ms-check`, docs | unchanged | n/a |

## Alternatives

- Do nothing: quadratic, measured above.
- In-place guard (first draft): rejected by review, a copyable handle to one mutable payload (stale writes after close) and a larger checker and lowering change.
- Registry-only fix: leaves `lock` O(n) for every other user.

## Staging and verification

- One change; gates: `make conform` 2286/2286, `cargo test --workspace`, clippy, `scripts/leak-check.sh` on shared and tasks fixtures (0 leaking).
- Known cost: the glue special case matches the guard by name and field names; a second type with that shape would get the same treatment. Revisit if another std type needs a closed state.

## Open questions

- None that change user-visible behavior.
