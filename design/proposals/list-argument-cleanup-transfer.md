# Keep list element cleanup through native transfer

## Summary

- #3027 leaks an evaluated incoming Closeable when list bounds or a later operand fault.
- Keep its registered owner until the native list operation has successfully stored it.
- Reuse existing leaf list mutators and exact cleanup retirement; change no language rule.

## Status

Implemented; 2026-11-08; checked main 18c8c8f and dependent cleanup base 8013a15.
The user requested proper fixes rather than partial patches. Independently reviewed for a dependent draft; merge remains gated on base and platform qualification.

## Problem

- Verified: `items.set(10, Item(2, log))` closes existing Item(1), not incoming Item(2).
- `insert` and `replace` reproduce the same failure in Debug and Release.
- `items.set(value: Item(2, log), index: panic("index"))` leaks before mutation starts.
- Reproductions and expected reverse-acquisition close logs are in #3027.
- `native_args` guards only when a later argument contains `try`.
- `mutator_call` registers resources only after all arguments and retires before bounds.
- `element_value` is too early a general transfer point: push/insert may still overflow.
- The fallback prepend/insert code creates intermediate lists before further concat calls.
- Direct insert already dispatches in place; the new guarded path must precede that dispatch.

## Design

- A direct list insertion argument owns exactly one registered slot from its evaluation.
- Register only an actually owned semantic payload, not a borrowed optional transport copy.
- Perform an implicit Optional conversion before registering; the guard owns the final element.
- Resolve close behavior from the checked element type, not an invented ABI type mapping.
- Evaluate operands in written order; retain their guards across later faults and `try` exits.
- Reorder argument records only after evaluation; the cleanup stack remains acquisition ordered.
- Leave ordinary non-list/native call evaluation unchanged.
- Guard an owned computed resource-list receiver before arguments, in the same acquisition order.
- Keep incoming guards through final receiver selection, bounds checks and old-entry close.
- Mutate a guarded receiver in its registered slot so cleanup sees its current header.
- On Unit success close/drop the computed receiver; a returned receiver transfers that owner.
- Use a dedicated guarded-list transfer path for append, prepend, insert, set and replace.
- Pass the registered incoming slot directly to the existing leaf native mutator.
- Do not take or copy its payload into a second owning temporary before the operation.
- Native bounds/reserve validation precedes its consuming byte copy.
- On native failure the incoming slot still owns its value and unwinds normally.
- On success retire its exact cleanup registration, then remove its statement-temp entry.
- Do not close, take or drop the now-consumed incoming slot after success.
- Exact removal must retain newer lexical owners; this depends on held PR #2984.
- Use existing native insert for the guarded path, not reconstruction through concat.
- The leaf operation and exact retirement contain no source callback or cancellation poll.
- `set` explicitly closes its old resource before mutation, preserving close ordering.
- Descriptor drop can invoke a closure capture closer; it is not assumed nonfaulting.
- Use native replace to detach old storage and install incoming before dropping old storage.
- A drop fault then sees the new owner in the receiver, not a partially dropped old element.
- A same-list observing capture is rejected because the escaping capture takes the resource list.
- `replace` returns the old owner without closing it; caller cleanup owns the returned value.
- Register the outgoing replace owner before closing a computed receiver, which can fault.
- Transfer the outgoing owner only after computed receiver cleanup completes.
- Keep original error messages, negative-index rules, valid end insertion and source order.
- No map/set changes, cleanup suffix truncation, or generic `element_value` changes.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-lower/native/defaults.rs` | list-only argument owner registration | later fault/try/named order |
| `ms-lower/native/list.rs` | retain guards through old close and bypass premature fast path | ordinary and slot-backed receivers |
| `ms-lower/native/mutate.rs` | guarded native slot transfer | set/insert/append/prepend/replace |
| `ms-lower/close.rs` | explicit successful-consumption retirement | newer owner survives exact removal |
| `tests/e2e/testdata/accept` | resource event logs and failures | Debug and Release native runs |
| runtime ABI | unchanged; reuse existing leaf primitives | inspect validation-before-copy contracts |

## Alternatives

- Do nothing retains confirmed leaks on ordinary invalid indexes and later operand faults.
- Retire in `element_value`: loses cleanup during reserve/overflow and intermediate concat.
- Validate early: changes written evaluation order and misses later faults or changed receiver size.
- Add new runtime transaction APIs: unnecessary if existing slot operations satisfy failure atomicity.
- Register the copied optional wrapper blindly: gives borrowed resources a second close duty.

## Required validation before publication

- Invalid positive, negative and end indexes for set/insert/replace; valid negative/end controls.
- Computed, named, optional and aggregate incoming resources; exactly-once normal cleanup.
- Written named order, later successful/failing `try`, and later ordinary fault.
- Failed old close with older/newer owners; reverse acquisition cleanup order.
- Ordinary, field/index-selected and closure-slot-backed receiver places.
- Replacement result retained and discarded; repeated transfers and nested scopes.
- Receiver mutation during operand evaluation uses the final current bounds.
- Independently inspect MIR ownership and leaf success-to-retirement window.
- Audit computed receivers on success and failure; old entries and final contents close once.
- Bound consuming-call adapter rejection is separately tracked in #3049, not bypassed here.
- Run compiler/MIR checks, affected native fixtures, broad cleanup controls and exact-head CI.
- Keep the dependent draft held until the base and platform/LLVM gates are satisfied.
