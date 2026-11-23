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

1. Cancel exits move into elaboration. Elaboration places, on each cancel exit after a park, the same close or drop of the live owned set that it places on a normal scope exit, instead of `forget`. The verifier gains the cancel edge: an owned value live on it must be consumed there exactly once. Then the cleanup registrations that only a cancel would use are dead and their `mir_unwind` handling is deleted. Done one construct class at a time, with `tools/cancel-sweep.ms` as the oracle, starting with the park-in-loop cases (#6746, #6790).
2. Ownership facts are the only thing lowering decides: owned, borrowed, moved, consumed. Closing decisions (when, which closer, plain slot or not) leave `lower_close.c` and `lower_scope.c` and live in `mir_elab`. Each decision removed from lowering is deleted code, not an addition (#6795 and #6796 were such decisions made wrongly in lowering).
3. Natives return on cancel (`wiki/runtime/natives-end-a-cancelled-call-by-returning.md`). The 16 `ms_cancelled()` call sites are audited one by one; a native that holds owned state across a park returns instead of unwinding, and its arguments stay in the caller's live set (#6784, #6774). A lint flags a new `ms_cancelled` call outside the audited list.
4. Faults are a separate decision, taken after 1 to 3 with numbers. Today a fault leaves by `ms_guard_jump` and the cleanup stack frees owners. Options: (a) treat a fault edge like a cancel edge (status return and one test after each call that may fault, no run-time stack at all); (b) keep a cleanup stack for fault only. A frame-pointer table walk is not an option: Windows cannot follow the frame register (`frames.h`), natives and callbacks are not built with frame pointers, and no table walker exists. The per-call test cost is measured before choosing.
5. Per-field drop flags come with the struct layout (every field its own cell), so a partial move is a flagged leaf, and #6691's nested and one-path moves are `EL_MAYBE` states elaboration already has.

## Limits, said plainly

"By construction" has one hole the verifier cannot close: a wrong ownership fact. A `ret_borrowed` result, a native that consumes its argument and a runtime-held value (promise, group, pipe) are declared by hand (`mir_result_mode`, the extern signature tables). Mitigation: those declarations stay in tables, checked by the leak sweep over every extern, not scattered through lowering code.

## Check that finds a new class by itself

- The verifier above runs on every `ms` compile, so a new construct that forgets an exit fails the build of the test that uses it, in the PR job that already builds all fixtures, not in a nightly.
- Cancel and fault sweeps stay as an independent oracle (`tools/cancel-sweep.ms`, `make leak-check`, `ownership-fuzz`); they already run in `nightly-safety.yml` and become a regression net, not the only net. Add `fault-sweep` (fault at every call that may fault) beside `cancel-sweep`.
- A fixture per row of the table above.

## Alternatives

- Do nothing: another class per day, each fixed locally.
- Keep the run-time cleanup stack and verify it: the stack is bookkeeping the compiler could instead know; its bugs (#6777) and its cost (about 260 instructions per promise) both go with it.
- Reference counting or a tracing collector: a runtime representation change and a language-visible cost for a compiler problem.
- Verifier only, no pass change: finds leaks as ICEs but leaves four places deciding when to close; the verifier would need constant updates.

## Stages

1. Cancel edges in the verifier and in `mir_elab` for the park-in-loop class; delete the matching `mir_unwind` registrations. Measure instructions per promise (tasks thread: 6 push/discard pairs, about 260). 2. The other cancel classes, one at a time, moving each closing decision out of lowering; native audit. 3. Struct layout and field drop flags. 4. The fault decision, with the per-call test cost. 5. `fault-sweep`, the runtime lint, delete the cleanup stack when nothing registers into it. Every stage keeps all sweeps green and cites `bench/perf` counts.
