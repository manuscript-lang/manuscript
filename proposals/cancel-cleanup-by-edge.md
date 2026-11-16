# Cancel cleanup by edge, not by registration

## Summary

- A cancelled task frees what its frames own by a runtime cleanup stack that `crates/ms-mir/src/unwind.rs` (2480 lines) fills by inferring ownership from MIR. Every shape it does not model leaks, and when it is unsure it skips the value. Eight point fixes (#4056 to #4221) so far; the nightly sweep (#4052) still finds new shapes.
- Change: a parking call returns to its caller with a cancel flag set, and the caller takes an early-exit edge that runs the same scope-end cleanup as `return` or `?`. Cleanup is produced by the pass that places the normal-path cleanup, from the same move state, so there is no second model to keep in step. Then delete the inference rules.
- Decision requested: build it in stages, each gated by the sweep and by a before/after count. No language or user-visible change.

## Status

Proposal, 2026-11-16, checked against main `981dacf6`. Direction: "do it properly, otherwise we're playing whack a mole" (Chinmay). Two earlier drafts (empty the place on move; infer more from elaborate) failed review; their objections are met in Design.

## Review findings (Fable, 2026-11-16) and what changed

Rejected as first written. Accepted: (1) the push counts below cover faults too, not only parks, so the saving is claimed only once faults use the same exit (stage 1 now includes inline faults, which are cold blocks); (2) a mixed module is unsound, because natives still jump over converted frames and a converted callee returns an undefined result to an unconverted caller, so conversion is whole-program and gated on every native park returning (stage 3 moves before any deletion; until then nothing is marked converted); (3) lowering still places 128 drop sites and `elaborate` has no field paths, so the real bulk is finishing `elaborate-drops` (stage 2 is its stages 2 to 4, with a count of convertible functions as the stage 0 gate); (4) the header has no spare byte, the request flag is set by signal handlers, and shield enter/exit clear it, so the exit needs its own delivered-cancel byte (grow the header) and `Op::Poll` joins the rule; (5) the slot refill is observable (#3040: a promise body that captures `var input` while the parent closes it), so the contract needs a stage 0 answer per hole type and keeps `slot_owned_params` if none exists; (6) shared chains must keep the verifier's identical-live-set rule, so chains are per dominating owner prefix and compile time is a gate. The check costs four instructions plus a load and branch, not three.

## Probe results (2026-11-16)

- Park-only windows are 21 to 43 percent of pushes (router 1730 of 4016, log 2085 of 5730, tls 918 of 3809, tree 215 of 1043; measured by letting `exits_at` return only parks). The rest are fault windows, so the instruction saving needs inline faults in stage 1.
- The drop pass already owns scope-end cleanup (#3752, #3755, #3757): 166 of 560 functions in router are Raw, 793 `scope.own` owners, one owner per moved resource field. Lowering still emits 1130 explicit `drop` ops in the same module, mostly statement temporaries and non-Raw functions. Temporaries and locals may stay in lowering (owner, 2026-11-16), so the cancel exit takes pass owners from the move state and temporaries from SSA value liveness, which is exact. Holes in plain record fields and slot parameters remain the open part.

## Problem

Measured with a temporary counter in `unwind::run` (`ms test` of a stdlib fixture, release build):

| fixture | insts before | insts after | parking call sites | pushes | discards |
| --- | --- | --- | --- | --- | --- |
| router | 22868 | 30040 (+31%) | 695 | 4016 | 2978 |
| log | 25380 | 35028 (+38%) | 873 | 5730 | 4585 |
| tls | 20230 | 26732 (+32%) | 694 | 3809 | 2722 |
| http-websocket | 15978 | 20717 (+30%) | 517 | 2586 | 2006 |
| tree | 7138 | 9060 (+27%) | 155 | 1043 | 780 |

Registration adds a quarter to a third of all instructions, about six push/discard pairs per parking call. Runtime cost per scope is about 48 instructions (push 27, discard 21; the cleanup-cost thread's callgrind, PR 4220) against a few for a C scope. Frame size grows with live owners (`wiki/compiler/unwind-cost-grows-with-values-live-to-scope-end.md`).

The leaks come from facts a registered bitwise copy cannot carry:

- A field moved out and not yet refilled leaves a hole. `move.out` is an alias, so freeing the owner frees the field twice; the pass skips every call in the hole (`hole_step`). `FailingSink.write` leaked a slice this way.
- A callee takes from the caller's `var` slot, parks, and puts back. Whether the callee or the caller frees the taken value is a cross-function fact (`slot_owned_params`).
- A handle that is not an owner at all: `with_access_log` (`stdlib/net/router.ms`) holds an Int pipe handle from `new_slot` across `next(var exchange)` and frees it with `release_slot`. No pass can free that on cancel; the stdlib must make it a resource with a close. This is outside the exit design and is filed with #4222.
- A cover pushed on one exit of a `?` was counted for another.

## Design

**Rule: a parking call can return early, and the early return is cleaned up by the normal-path rules.**

1. *Flag.* The cancel request (already one flag, `cancellation-is-a-host-level-flag`) is mirrored in one byte of the isolate header, which generated code already reads for `guarded`. A park that is cancelled sets it and returns a zero result. Natives do the same: `ffi::report` sets the flag and returns instead of calling `msrt_cancelled()` (the cancel-by-return stages #3088 to #3161 already make most native parks return `Err(Cancelled)`).
2. *Edge.* After each call to a function that can park (the `parks` set the pass already computes), the module has `br.cancel`: load the byte, branch to the function's cancel exit when set. The result of the call is not defined on that edge.
3. *Cleanup.* The cancel exit is a scope-exit edge like `return`: `elaborate` runs the scopes it leaves, in order, dropping or shielded-closing each owner that is still held by its move state, then returns a zero result with the flag still set. Shared cancel blocks form one chain per function, one node per owner in reverse order, so code grows linearly (the registration windows exist today to avoid the quadratic case).
4. *Partial owners.* The move state gains field paths (record fields, as `Part` already does for alt payloads). A moved-out field is then a path state, and the exit releases the other fields with the existing masked release (`type.release`, `alt.release`). This is Rust's move paths; it removes `hole_step` and the skip.
5. *Slots (the cross-call contract).* A slot parameter is borrowed memory. Rule: on every exit, cancel included, a callee leaves each slot parameter fully valid. A taken value that is still held is put back; a part that was consumed is refilled with the type's empty value before the exit. The caller's cancel exit then drops the slot as an ordinary owner. No cross-function inference is left: the contract is the same one the normal return already needs.
6. *Hold-outs.* A native that calls generated code (sort comparators, iteration callbacks, serve handlers) checks the flag after the callback and returns. Until the last jump is gone the cleanup stack stays for the frames above such a native, and the two mechanisms never cover the same owner (a function is converted whole, marked in the module).
7. *Cost gate.* Only modules that start tasks get edges, as now. One byte load and branch per parking call, about 3 instructions against the 48 per scope today.

## Interfaces (fixed so the pieces can be built in parallel)

- Runtime: `Hdr` grows to 24 bytes and gains `unwinding: u8`, set by the park that delivers a cancel (not by the request, which a signal handler sets asynchronously and a shield clears) and cleared when the task's cancel exit completes at the task boundary. `Op::Poll` today reads the shield-aware `cancel` byte and jumps; it becomes an edge on `unwinding` after it sets it.
- IR: `call.cancelable` is any call to a function or extern in the `parks` set; after it, terminator `br.cancel <exit>, <next>` tests `unwinding`. The call's result is undefined on the `<exit>` edge. The exit block has no result and returns zero.
- Natives: every park returns a status or sets `unwinding` through `ms_rt::glue::deliver_cancel()` and returns a zero value; `ffi::report` stops calling `msrt_cancelled()`. A native that calls generated code checks `unwinding` after the call.
- Gate that makes a mixed module impossible: the module carries a `cancel_edges` flag; the runtime build refuses to link a native that still jumps (a counted allow list that shrinks to empty).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-mir` ir, verify | `br.cancel`, cancel exit has no result; verifier proves the exit's live set like any `ret` | verifier cases, one reject per rule |
| `ms-mir` `elaborate.rs` | cancel edge as a scope-exit edge; field-path move state | per-shape unit tests (hole, slot, `?` with several exits) |
| `ms-lower` | hand the pass the remaining owners (`var` locals, resources, temporaries); lowering stops placing their cleanup | `closed_on_path` ledger |
| `ms-clif`, `ms-mir-llvm` | lower `br.cancel`, load of the header byte | conformance on both backends |
| `ms-rt`, `ms-std-*` | `report` returns with the flag; callback sites check it | `make cancel-sweep`, native unit tests |
| `unwind.rs` | shrinks to the native hold-outs, then is deleted | sweep clean, count before/after |

## Alternatives

- Do nothing: eight fixes so far, each adds a rule, and the registration cost stays.
- Empty the place on move and register places (earlier draft): needs a null-safe drop for every type (dyn, boxed alt, indirect fail on zeros) and a place for `move.out`, which is an SSA alias. Kept only as the slot refill in step 5, where the value is a real empty one.
- Infer more in `unwind.rs`: no end, the failure that started this.
- Rust panics for cancel: no unwind tables in generated code, ABI change in every crate (`cancel-by-return.md`).

## Stages

0. *Probes, before any code lands.* (d) Split the pushes by park-only and fault windows. (e) Count functions whose parking-live owners are all Raw. (f) Cost of the delivered-cancel byte and check on both backends. (a) Count, per fixture, live owners at parking call sites to bound branch-argument cost. (b) For each type that can sit in a hole of a slot parameter, name its empty value; list the types with none. (c) List native frames that call generated code. Kill criterion: if (b) finds a hole type with no empty value that real code reaches, or (c) exceeds what a stage can convert, stop and keep the stack for slots.
1. Edge for SSA owners and `?` exits in `elaborate`; unwind skips functions marked converted. Gate: sweep, conformance, instruction count equal or lower.
2. Field-path owners (holes), slot contract, resources and `var` locals moved into `elaborate`. This includes resource locals with no storage (a `Promise` is one Int): the exit closes them like any scope owner, which fixes #4222 (a cancelled task's `outer` promise is never closed, so the runtime drops its untaken result through a plain descriptor). Gate: sweep clean on `iotest-golden`, `tree`, `deque-resource-growth`, `router`.
3. Natives return with the flag; callbacks check it. Gate: sweep, Windows and macOS dispatch.
4. Faults: a fault block in a guarded task becomes a branch into the same exit, free on the hot path. Native faults (`-> !`) keep the stack until they return a status. Delete `unwind.rs` when the last hold-out is gone.
