# Every owned value is closed by one pass, on every exit, or the build fails

## Summary

- Problem: closing owned values is done in several places, each deciding for itself when to close, so every new construct can forget an exit. Seven leak or double-close classes in one day (#6691, #6746, #6784, #6790, #6795, #6796, #6774, plus #6797 and #6786) were each fixed where they showed. The compiler bug bash found them by cancelling every test at every park, after the fact.
- Change: finish the move to one closing pass. Lowering says only who owns a value and where it moves. `mir_elab` (already built for scope exits) places every close, now including cancel exits, from its ownership dataflow, and the verifier (already in every build) checks cancel edges too. The run-time cleanup stack goes once nothing registers into it.
- Decision requested: none; no language or syntax change. Chinmay, 2026-11-23: "structure code such that future leaks are simply not possible", "not whack-a-mole".

## Status

Proposal, 2026-11-23, after #6785 (`var` records in cells). Builds on the existing `mir_elab`, `mir_verify_own.c` and `mir_cancel_edges.c`; field drop flags need the struct layout follow-up of `proposals/in-place-var-records.md`.

## The leak classes it must cover by design

| Class | Case | Why it passes by construction |
| --- | --- | --- |
| Partial move | #6691: field moved on some paths, fault, nested `a.b.c`, early exit, match close order | each field path is an owned leaf with a static drop flag; the record's close is the set of flagged leaves |
| Cancel at park | #6746 var assigned in a loop; #6790 captured reader | a park has a cancel edge; elaboration closes the owned set live there |
| Owned argument of a native that parks | #6784 `run` with `env` | arguments and temporaries are owned values live across the call, so they are in the edge's set |
| Resource var changed by a lambda | #6795 | a captured `var` is an owned cell whatever bound it; no "plain slot" decision exists |
| Temporary of a returned call | #6796 `return f(make())` | the temporary is owned until the call consumes it; return is an edge like any other |
| Pending return value on the error edge | #6797 | the pending value is an owned value in the edge's set, consumed once by `ret` |
| Native-held state | #6774 TLS handshake | natives that park return on cancel; the state is an owned value of the caller |
| Cleanup stack bookkeeping | #6777 serial bug | the stack shrinks to fault-only, then goes |

## What exists (review, 2026-11-23)

The migration is already under way, and this proposal finishes it rather than starting another one. A Raw function carries only scope markers (`scope.begin/own/end/disown/mark`); `mir_elab*.c` runs a move-state dataflow (`EL_LIVE`, `EL_MAYBE`, partial-move states) and places the scope-exit drops, closes and drop flags. `mir_verify_own.c` already enforces linear ownership and an empty live set at `ret`, in every build. `mir_cancel_edges.c` already makes a cancelled park leave by ordinary returns (it tests the `unwinding` byte after each park). What is not done: it is "hybrid" (the owned values on the cancel exit are `forget`-ed and the run-time cleanup stack, built by `mir_unwind*`, frees them through `msrt_cleanup_unwind_to`), and elaboration does not place cancel exits. Closing is still decided in `lower_close.c`, `lower_scope.c`, `opt_exit_drops.c`, `mir_unwind_closers.c` and `own/closers.c`. 93 `fn_own`/`fn_disown` call sites in `lower/` carry ownership facts today.

## Design

0. Where the exit is built (found 2026-11-23). `mir_cancel_edges` is off in every build today (`options->cancel_edges` is never set; a cancel still leaves by `ms_cancelled()` and the cleanup stack), and it runs after elaboration, so it cannot close. Closing at an exit is not only `scope.end`: `emit_end` in `lower_scope.c` also pins outer `var` locals and settles moved ones, which a MIR pass cannot redo. So the exit is built in lowering, by the helper `?` already uses: after a call that may fault or park, test `msrt_unwinding`, and on the set branch run `fn_scope_unwind(fn, 0)` (all open scopes, as `fn_return_error` does), then `ret` an undefined result. A later pass deletes the test and its dead block after calls that provably cannot fault or park (`mir_parking_funcs` gives the set). Elaboration then closes on that edge as on any early return, with drop flags where owners differ per site. The runtime contract: a cancelled or faulted native sets the byte and returns (tasks thread).
1. Cancel exits move into elaboration. Elaboration places, on each cancel exit after a park, the same close or drop of the live owned set that it places on a normal scope exit, instead of `forget`. The verifier gains the cancel edge: an owned value live on it must be consumed there exactly once. Then the cleanup registrations that only a cancel would use are dead and their `mir_unwind` handling is deleted. Done one construct class at a time, with `tools/cancel-sweep.ms` as the oracle, starting with the park-in-loop cases (#6746, #6790).
2. Ownership facts are the only thing lowering decides: owned, borrowed, moved, consumed. Closing decisions (when, which closer, plain slot or not) leave `lower_close.c` and `lower_scope.c` and live in `mir_elab`. Each decision removed from lowering is deleted code, not an addition (#6795 and #6796 were such decisions made wrongly in lowering).
3. Natives return on cancel (`wiki/runtime/natives-end-a-cancelled-call-by-returning.md`). The 16 `ms_cancelled()` call sites are audited one by one; a native that holds owned state across a park returns instead of unwinding, and its arguments stay in the caller's live set (#6784, #6774). A lint flags a new `ms_cancelled` call outside the audited list.
4. Faults leave by the same path (Chinmay, 2026-11-23: "can we fault as normal return path so everything works?"). A fault sets the task's `unwinding` byte and the fault record and returns; every call that may fault or park is followed by the one test `mir_cancel_edges.c` already emits after a park, and a fault inside a function (bounds, overflow, `panic`) branches to the same exit. Elaboration fills the exit with the closes. The guard longjmp (`ms_guard_jump`), the run-time cleanup stack and `mir_unwind*` go. The test is skipped after a call to a function that provably cannot fault or park. Cost is measured on `bench/perf` first (expected: two instructions per fallible call). Stack overflow and out-of-memory stay fatal to the task (no stack to return on). A frame-pointer table walk is not an option: Windows cannot follow the frame register (`frames.h`), natives and callbacks have no frame pointers. Natives with callbacks (sort comparators, `map`) must stop on a pending status; the native audit covers them.
4a. Compiled checks (found 2026-11-24, after panics and failing closes moved to return, b59a42f6d3). A check (`IAddChk`, `SDivChk`, `list.get`, `opt.unwrap`, ...) is one instruction whose cold path calls a noreturn `msrt_fault_*`; the back end writes that path (`emit_fault_if`) and `mir_expand` makes the list ones after elaboration, so nothing knows the live owners there. Plan: lowering emits a `fault.site %r` test after each checked instruction, as it does after a call, with a `leave` block that runs `fn_unwind_exit`; consecutive sites with no ownership event between them share one `leave`. The back end sends the check's cold path (`post`, then `br leave`) to the true edge of the site that uses the check's result; the site is the constant false on the normal path, so the hot path gains nothing. Generated helpers with no lowered scope (no owners) fall back to `post; ret undef`. The runtime `msrt_fault_*` post and return. A verifier rule pairs every check with its site, so a pass that separates them is an ICE, not a leak.
5. Per-field drop flags come with the struct layout (every field its own cell), so a partial move is a flagged leaf, and #6691's nested and one-path moves are `EL_MAYBE` states elaboration already has.

## Limits, said plainly

"By construction" has one hole the verifier cannot close: a wrong ownership fact. A `ret_borrowed` result, a native that consumes its argument and a runtime-held value (promise, group, pipe) are declared by hand (`mir_result_mode`, the extern signature tables). Mitigation: those declarations stay in tables, checked by the leak sweep over every extern, not scattered through lowering code.

## Check that finds a new class by itself

- The verifier above runs on every `ms` compile, so a new construct that forgets an exit fails the build of the test that uses it, in the PR job that already builds all fixtures, not in a nightly.
- Cancel and fault sweeps stay as an independent oracle (`tools/cancel-sweep.ms`, `make leak-check`, `ownership-fuzz`); they already run in `nightly-safety.yml` and become a regression net, not the only net. Add `fault-sweep` (fault at every call that may fault) beside `cancel-sweep`.
- A fixture per row of the table above.

## Alternatives

- Do nothing: another class per day, each fixed locally.
- Static unwind tables: no walker exists and Windows cannot follow the frame register; status returns need no walker.
- Keep the run-time cleanup stack and verify it: the stack is bookkeeping the compiler could instead know; its bugs (#6777) and its cost (about 260 instructions per promise) both go with it.
- Reference counting or a tracing collector: a runtime representation change and a language-visible cost for a compiler problem.
- Verifier only, no pass change: finds leaks as ICEs but leaves four places deciding when to close; the verifier would need constant updates.

## Stages

1. Cancel edges in the verifier and in `mir_elab` for the park-in-loop class; delete the matching `mir_unwind` registrations. Measure instructions per promise (tasks thread: 6 push/discard pairs, about 260). 2. The other cancel classes, one at a time, moving each closing decision out of lowering; native audit. 3. Struct layout and field drop flags. 4. Faults on the same edges, with the per-call test cost measured first. 5. `fault-sweep`, the runtime lint, delete the cleanup stack when nothing registers into it. Every stage keeps all sweeps green and cites `bench/perf` counts.

## Outcome (2026-11-24, stages 1 and 4)

Faults and cancels leave by return in every compiled program: the cleanup stack (`msrt_cleanup_*`, `Hdr.cleanups`), the guard `longjmp` (`ms_guard_enter`, `ms_guard_jump`), the raise machinery in `fault.c` and the passes `mir_unwind*` and `mir_shed` are deleted. A raised fault (`ms_fault`, stack overflow, out of memory) ends the process; every other fault is posted. Guards are plain calls. Stack overflow is no longer recoverable, so the three fixtures that caught it became `run` fixtures expecting exit 139. Stage 2 (moving closing decisions out of lowering) and stage 3 (struct layout) remain. The wiki page [faults and cancels leave by return](../wiki/runtime/faults-and-cancels-leave-by-return.md) records the contract and the failure modes found on the way.
