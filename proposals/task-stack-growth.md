# Task stacks grow by guarded segments

## Summary

- Problem: a promise task's stack is one 512 KiB slot (#2562), so a task holds about 3,000 ordinary frames where the main program holds 256 MiB; a recursive tree walk inside a promise faults where it used to finish.
- Change: the recursion check every cyclic function already runs (`DepthEnter`) grows the stack instead of faulting: the function re-invokes itself on a fresh guarded 512 KiB slot through a per-function shim, and returns the result. A stack never moves; a task reaches the main program's 256 MiB again; a task that never recurses deeply pays nothing.
- Decision: built as stage 2 of the million-task work (runtime plus one lowering change, no language change). Mechanism and evidence: `wiki/runtime/task-stacks-are-512-kib-slots-in-256-mib-regions.md`.

## Status

Implemented, 2026-11-04, on `claude/project-thread-l5eimt` after stage 1 (PR #2562). Chinmay's direction: stage 2 is growth by guarded segments, on Linux, macOS and Windows together. Skeptical review: revise; it found the MIR inliner copying the check into host bodies and two passes prepending to the entry block (fixed below), and asked for a cap by bytes and a restore at every guard exit (done).

## Decisions not obvious from the code

- The check re-invokes the function from its entry, so `DepthEnter` is the first instruction of the entry block (`ms_mir::verify`): the prologue clones a mutated parameter and registers closers, and a re-invocation after them would leak. The inliner drops an inlined body's checks; `loopslot`, closure-argument specialization and the unwind pass insert after the check.
- Chain cells live at the top of grown segments and `STACK_CHAIN` names the current one, not a per-task table: a signal handler reads them without a lock, and the home slot's top keeps its initial frame.
- The cap is a region's worth of stack for a task; the main task, which owns a region, never grows.
- A task parked on a grown segment is not hibernated; the Windows fault-report walker stops at a segment boundary. Both wait for evidence that they matter.

## Alternatives

- A bigger slot: page tables scale with spacing (2 KB per task per MiB); 1M tasks at 2 MiB is 7.8 GB in all, over the machine.
- Copying stacks (Go): natives and views hold raw pointers into frames, and a frame holds no map of them; not feasible.
- A check in every prologue or Cranelift's `stack_limit`: rejected by direction (checks only in recursive functions), and `stack_limit` traps rather than grows.
- Growing at the call site instead of the callee's entry: needs a thunk per call-site signature and a check at every indirect call; the entry form needs one shim per cyclic function.
