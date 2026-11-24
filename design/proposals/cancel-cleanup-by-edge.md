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

- Raw functions with a parking call whose owned values at every park are all scope owners (probe before `elaborate`, 2026-11-16): router 80 of 144, log 78 of 93, tls 50 of 75, tree 20 of 31. Raw functions are about 30 percent of all functions (router 166 of 560). The untracked owned values at park sites in router are 171 `take` results (memory slots), 35 parameters, 20 `none` and 16 field fills: the slot and field shapes, not temporaries. So explicit exits need slot state, not a general liveness walk.
- Slot state rule that replaces `slot_owned_params` for local slots: per slot, `Full`, `Taken(v)` or `Taken(consumed)` by dataflow. A cancel exit `put`s `v` back when it is still live, `scope.disown`s the slot when `v` went into a callee (which frees it), and otherwise runs the normal scope cleanup. For a slot parameter, the exit of a callee that consumed a taken part writes the type's empty value into the slot before returning; a type with no empty value keeps its function hybrid. No cross-function inference remains.

## Problem

Measured with a temporary counter in `unwind::run` (`ms test` of a stdlib fixture, release build):

| fixture | insts before | insts after | parking call sites | pushes | discards |
| --- | --- | --- | --- | --- | --- |
| router | 22868 | 30040 (+31%) | 695 | 4016 | 2978 |
| log | 25380 | 35028 (+38%) | 873 | 5730 | 4585 |
| tls | 20230 | 26732 (+32%) | 694 | 3809 | 2722 |
| http-websocket | 15978 | 20717 (+30%) | 517 | 2586 | 2006 |
| tree | 7138 | 9060 (+27%) | 155 | 1043 | 780 |

Registration adds a quarter to a third of all instructions, about six push/discard pairs per parking call. Runtime cost per scope is about 48 instructions (push 27, discard 21; the cleanup-cost thread's callgrind, PR 4220) against a few for a C scope. Frame size grows with live owners (`design/wiki/compiler/unwind-cost-grows-with-values-live-to-scope-end.md`).

The leaks come from facts a registered bitwise copy cannot carry:

- A field moved out and not yet refilled leaves a hole. `move.out` is an alias, so freeing the owner frees the field twice; the pass skips every call in the hole (`hole_step`). `FailingSink.write` leaked a slice this way.
- A callee takes from the caller's `var` slot, parks, and puts back. Whether the callee or the caller frees the taken value is a cross-function fact (`slot_owned_params`).
- A handle that is not an owner at all: `with_access_log` (`stdlib/net/router.ms`) holds an Int pipe handle from `new_slot` across `next(var exchange)` and frees it with `release_slot`. No pass can free that on cancel; the stdlib must make it a resource with a close. This is outside the exit design and is filed with #4222. Done 2026-11-18: the handle is a `SlotOwner` with `fn var close() Void!`.
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
- IR (no new terminator or backend op): after any call in the `parks` set, a pass emits `u = call.rt msrt_unwinding()` (a new leaf extern, role `Unwinding`, returns the header byte as bool) and `condbr u, exit, next`. The exit block `scope.disown`s the call's result, emits `scope.end` for every scope open at the call (innermost first, exactly as an early `return` does), drops the untracked owned SSA values live there, and returns zero. The pass runs before `elaborate`, which places the drops from move state. Backends only inline `msrt_unwinding` as a load of the header byte, an optimization the first version may skip.
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

## Stages (revised: hybrid first, so conversion is per function)

A converted caller of a function that returns with the flag set must check it, so checks go everywhere at once; what a function does on the exit can differ.

1. *Flag and hybrid exits, behavior-neutral.* Every function of a task program checks `msrt_unwinding` after each call that can park. Its exit runs the cleanups the function itself registered (`msrt_cleanup_unwind_to(base)`, the height taken at entry; new runtime entry) and returns `undef` with the flag still set. Natives return with the flag; the task boundary clears it and runs what is left. Nothing is freed differently from today. Gate: conformance, sweep unchanged, check cost measured on `bench/perf`.
2. *Explicit exits (details after #4302).* A pass before `elaborate` converts Raw functions (`Func.explicit_cancel`): after each parking call, `condbr` on `msrt_unwinding` to a block that forgets the call result, runs `scope.end` for every open scope, calls `msrt_cleanup_truncate(base)` (pop without running, so registrations kept for faults are not run a second time), and returns `undef`. The inliner may inline a converted callee only into a converted caller (the caller's own check after the call then catches the flag); `cancel_edges` skips converted functions. Registrations stay for faults until stage 4, so this stage fixes leaks but does not yet remove the push/discard cost. A callee fault cannot return by flag, so removing registrations needs stage 4 first.
   Built (2026-11-17): `cancel_exit.rs`, called from `elaborate::function`, converts a Raw function in a task program whose live owned values at every park are scope owners or fresh results/entry parameters, and that owns no memory slot (`scope.own` kind 2 and up). The exit forgets the call result, drops the untagged owners, ends the open scopes (a close error is dropped), and returns `undef` after `msrt_cleanup_truncate`. Router 56 of 144 parking Raw functions convert, tree 16. Conformance passes with edges on and sweeps match the hybrid counts; the slot and hole shapes are next.
   Built (2026-11-18): the restore contract for `var` slots. A function with `var` slots that builds an explicit exit puts every slot it took from back, as its normal exit does; callers trust slots passed to restoring callees; closure calls restore when every closure of the type does; holes are refilled; local slots still holding an owned value are dropped. `elaborate::settle_restores` proves cycles together. Sweep on router, deque, http-hardening, tree, stream, promise-cross-thread: 794 runs, 1 flaky leak (stream, one block, also on baseline); router 7 to 0, deque 3 to 0, promise 2 to 0.
   (Original stage text follows.) Explicit exits for functions whose parking-live owners are all pass owners or SSA temporaries* (the `scope.end` plus liveness exit; no park registration in those functions). Gate: sweep, instruction count lower than stage 1, runtime lower.
3. *Holes, slots, resource locals without storage* handled in the pass (field-path move state, slot contract). Gate: `iotest-golden`, `tree`, `deque-resource-growth`, `router`, #4222.
4. *Faults*: a fault block in a guarded task branches into the same exit. Delete `unwind.rs` when no function is hybrid.
