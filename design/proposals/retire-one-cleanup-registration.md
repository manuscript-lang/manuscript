# Retire one completed cleanup registration

## Summary

- An intact temporary Optional resource passed to a source reader loses its close obligation (#2972).
- Keep its existing resource slot while the call borrows it, then retire only that registration.
- Add one internal runtime primitive; preserve source ownership, cleanup order, and language APIs.

## Status

Approved for implementation; 2026-11-08; main `5492d5192`; independent review requires exact retirement, trap, and bounded-loop tests.

## Problem

- Verified: direct Optional mapping closes its input, but an equivalent source helper does not.
- `call_callable` puts the owner in ordinary temporaries; `close_temp` excludes wrapper payloads.
- That exclusion also protects wrappers whose payloads have moved; removing it is not safe.
- Existing `hold_resource_temp` already owns intact payloads in slots and protects fault paths.
- Its retirement uses `cleanup_discard(handle)`, which also discards every newer registration.
- Verified rejected candidate: bind a whole-returned temporary, then fault; its new local closer is lost.
- A canceled marker retired at statement end still discards that newer local registration.
- Moving cleanup to lexical-scope end can accumulate registrations in repeated loop conditions.

## Design

- Keep `cleanup_discard` for its existing stack-suffix contract.
- Keep `cleanup_cancel` for a reserved no-op registration whose handle is used again later.
- Add `cleanup_remove(handle)` for final, one-time retirement of exactly one registration.
- Removal never runs the action and never changes the indexes of live entries.
- Mark the entry with a null-action tombstone; a valid pushed action is never null.
- Trim only a trailing run of removed tombstones, never canceled/reserved entries.
- After an ordinary discard exposes tombstones, trim them as well.
- Cleanup execution skips removed entries rather than calling a null action.
- Reusing the index of a trimmed entry is safe: a removed handle must never be used again.
- Handle zero remains a no-op, matching existing conditional registrations.
- Adjust saved trap cleanup bases after trimming, as discard already does.
- An interior tombstone can remain only while a newer registration remains live.
- Repeated completed temporaries with no newer live owner return the stack to its prior size.
- No generations, allocation per registration, or new synchronization are introduced.

- At the borrowed source-call boundary, hold intact owned resource arguments with their closer.
- On normal statement completion, remove that registration, then close/drop its slot value.
- If a source helper returns the argument whole, remove the old registration and transfer its sole value.
- The new lexical owner can register its cleanup independently; retiring the old one cannot erase it.
- Borrowed named arguments remain borrowed; consumed parameters still receive ownership.
- Copy a permitted borrowed part before releasing its temporary owner.
- Keep the callee's resource faults and cleanup error behavior unchanged.
- Stage acquired resource arguments before later arguments/defaults in written evaluation order.
- Retain their guards through borrowing calls; consumed parameters take the owned slot value.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-rt/fault.rs` | Exact retirement and tombstone pruning | Nested owners, reserved handles, reuse, traps, bounded loops |
| Runtime symbol table | Add the internal primitive | Generated ABI checks |
| `ms-lower/call.rs` | Preserve intact caller-owned argument cleanup | Optional and Result source helpers |
| `ms-lower/close.rs` | Retire the exact completed temporary | Whole transfer, newer owner, source fault |
| `ms-lower/rtcall.rs` | Existing cleanup-retirement role | Unwind ownership verification |
| Native source tests | Exact close counts and ordering | Both build profiles, scalar and heap-bearing resources |

## Alternatives

- Do nothing leaves supported source abstraction boundaries silently leaking resources.
- Remove the wrapper exemption: moved payloads could close twice.
- Use `cleanup_discard`: verified to erase newer owners after result binding.
- Use `cleanup_cancel` alone: reserved entries accumulate after completed loop conditions.
- Compact interior entries: invalidates index-based handles still held by generated code.
- Add generation handles or a linked cleanup registry: unnecessary new representation and lookup cost.
- Close input arguments immediately after the source call: changes temporary lifetime/order and complicates result faults.

## Stages

- Independently review the primitive's handle lifetime and guard-base invariants before implementation.
- Verify runtime retirement controls, then native source fault/transfer regressions and broad ownership tests.
- Run ordinary CI and full platform qualification; no failing or unreviewed implementation is merged.
