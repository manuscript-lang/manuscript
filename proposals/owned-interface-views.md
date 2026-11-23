# A function that returns an interface view returns an owned box

## Summary

- Problem: a function that returns an interface view of a borrowed value (`fn first_error(cause: Cause) Reportable: return cause`) allocates a box for the view and no caller owns it: 32 bytes per call (#6639; 1000 calls leave 31.3 KiB under `MS_FREE_AT_EXIT=1 MIMALLOC_SHOW_STATS=1`).
- Change: restore stage 2 of [views.md](views.md). A function whose interface result borrows its arguments is a *view lender* (`ret_view`): its result is always an owned box (vtable tag 1: the drop frees only the box, never the payload), and the caller drops it like any owned value. The payload is never copied.
- Decision requested: one. The alternative below (clone the payload, one line) is sound and leak-free but is the implicit copy views.md rejected; the owner picks.

## Status

Implemented 2026-11-23 (owner chose the owned-box lender). A returned interface view that is not a fresh owner goes through `iface.own`: one allocation of the payload size (a size word after the vtable slots) with the payload copied, tag 1 so the caller drops it. `Reportable?` results take the same path through an implicit clone. `interface-views` is in `MS_LEAK_FIXTURES`. No interface-view benchmark exists in `bench/perf`; the cost is one small allocation per returned view, which replaced a leaked one.

## Problem

- `view_as_interface` (`lower_conv.c`) builds a returned view as `iface.new` with the kept flag, which `iface_new` (`emit_iface.c`) ignores: a heap box with tag 0, `ScopeDisown`ed, and `ret_borrowed` results are not dropped by callers. Local views were fixed in #6632 (`iface.borrow`); only returned views leak. `interface-views` leaks 9 boxes; the review measured `first_error`, `relay(first_error(c))`, `through`, `either` (false arm), `rebound`, `lend_then_relay` and `lend_id` all leaking.

## Why not by address

- Records up to 16 bytes arrive as register leaves: no address to return. Larger ones arrive as the address of a per-call copy (`spill_arguments`), which may be a shared slot (`temps_shared`) and is declared `nocapture`.
- The worse case: a view into the caller's copy dangles once that caller returns it up a chain (`return relay(first_error(c))`). Only a pass-by-reference ABI would fix it. views.md rejected unboxed fat pointers for the same reason.

## Design

- Classification (`reserve`, `lower_func.c`): when `ms_own_result_is_borrowed` holds and the result type is an interface, set `ret_view` and clear `ret_borrowed`. Checker holds and overlap rules are unchanged. `mir_result_views` already treats `ret_view` calls as views for `copyelim`/`lastuse`; `opt_inline.c:605` already treats them as owning.
- Invariant: a view lender's result is tag 1 (box only), never tag 0 or 2. A function that would return a tag-0 value is an owner (mixed return) and not a lender, so it stays as today (`fresh`).
- What each `return` emits in a lender:
  - a conversion of a borrowed value: `iface.borrow` (box of the leaves, tag 1);
  - a call to a lender, or a view local by name: moved out (take the local, skip its drop), already tag 1;
  - any other interface reference (a parameter, `r.err`, a field of a parameter, `e2` that is a plain reference): `iface.own`, a new op that allocates a box and copies the payload's leaves bitwise (size from a new vtable slot after the copier), tag 1. The payload stays owned by its origin, which the checker holds.
- Why this closes the holes: no tag-2 value is ever produced by a lender, so nothing dangles when a local's box is freed. `lend_then_relay`: `relay` returns `iface.own` of its parameter's leaves, a fresh box independent of `e`'s box. `x := relay(first_error(c))`: the temporary's box can be dropped at statement end; `x` owns its own box. No `view_moves` fact is needed; lowering decides by the shape of the returned expression.
- Callers: a lender's result is owned, so `call_bound_operation` (`lower_call.c:368`), `lower_closure.c:358,410,823`, `mir_depth.c:106-138`, `mir_cancel_edges.c:49`, `emit_call.c:58` and `opt_inline.c` stop treating it as a borrow; the `kept` flag path in `mir_analysis.c:23,116` goes away.
- Mutating interfaces (`ReadStream`, `WriteStream`) keep converting by copy (`contract_mutates`).
- Cost: a passthrough (`relay`, `either` returning an existing interface value) now allocates one box where it copied two words; a conversion costs what it cost.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `lower_func.c`, `mir.h` | `ret_view` for interface results | `e2e/accept/interface-views` |
| `lower_conv.c`, `lower_stmt.c` | per-return emission above, view local taken | new fixture looping every shape under the stats leak check |
| `mir_analysis.c`, `mir_verify_own.c` | drop the kept-flag modes; verifier rule on `ret_view` | `make verify` |
| `emit_iface.c`, `mir_data.c` | `iface.own`, vtable size slot | leak and fixture sweeps |
| the readers listed above | lender results are owned | conformance sweeps |

## Alternatives

- Clone the payload when an interface result borrows (one line in `borrows_result`): the review built it, all ten shapes reached 0 live blocks and `interface-views` passed. It costs one payload clone per call and is the implicit copy views.md and the owner rejected ("no i don't want implicit copying").
- By address, a caller-provided slot (hidden parameter), a per-task arena: rejected above.
- Do nothing: 32 bytes per call in a loop.

## Open questions

- Is a passthrough allocation acceptable, or should `iface.own` skip the box for a source that is already tag 1 and moved? (It does: moved sources are not copied; only plain references allocate.)
- `bench/perf` has no interface-view benchmark; one is needed before the cost claim is cited.
