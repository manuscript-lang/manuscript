# Tasks as compiler-built state machines

## Summary

- A waiting task owns a stack. Measured: 7.1 KB per idle websocket connection in `ms` today; of that, 3.5 KB is the hibernated stack and the rest is records and native connection state. A C model of the same server with a one-block state machine per connection holds 60 to 130 B, but it is hand-written with one state and a shared read buffer, so it bounds the saving and does not predict a compiled chain.
- Change: the compiler turns each function that can wait into a frame type and a `step` function; a waiting task is its frame chain. Expected: 0.2 to 0.5 KB per idle connection (hypothesis, to be measured at stage 3).
- Decision: the direction was approved by Chinmay on 2026-11-20. This records the design, the evidence and what a skeptical review found.

## Status

Proposal with a feasibility sketch (not in the tree), 2026-11-20, main `fd2c28aa`. Direction: "yes go for it" (Chinmay). Independent review (Fable) found the first draft's prototype unsound on loops, holes and slots and its baseline inflated; this version fixes the first two in code, refuses the third, and corrects the baseline.

## Problem

- Idle cost (`bench/tasks-proto/wsproto.c`, 8,000 connections, Linux x86-64): an un-hibernated stack task costs 5,120 B plus 1,028 B page tables, of which about 1 KB is a `ucontext_t` that a real switch does not need. Shipped `ms` hibernates to about 3.8 KB bare. The honest saving is about 3 KB per connection; the rest of the 7.1 KB is not the stack.
- Hibernation pins tasks that lend frames (`pool::run_shielded`) and exists to work around the page floor.
- Cancel is a flag plus a cleanup stack that `unwind.rs` fills by inference (`proposals/cancel-cleanup-by-edge.md`).
- Do-nothing is not yet beaten by evidence: the wiki puts 2.9 KB of the parked depth in runtime frames, and thinner park frames are "the next lever"; the C runtime port attacks the same bytes. Real servers also pay 20 to 40 KB per TLS connection and kernel socket memory, which dwarf either design.

## Design

**Sketch** (Rust, kept out of the tree because new compiler work is written in C: `w13/mir-sketch/` in the project files). `convert` ends each block at a wait and splits the function into `f.start`, `f.step(Frame) -> Frame` and `f.cancel(Frame)`. A wait `r = call.rt @w(a)` becomes `tk = @w_begin(a)`, save the live values, return; state `k` resumes with `r = @w_result(tk)`. The code reachable from each resume point is cloned, frame slots are shared by type. Tested on an echo loop in both branch orders (verifier accepts, interpreter output equals the original, `cancel` frees the saved tag exactly once from every state). It refuses slots, moved-out fields (holes), depth ops, the cleanup stack and polls, because the sketch does not model them. It is a feasibility sketch of the form the real pass will not take (frame by value, clone per wait).

**Real shape** (`ms emit examples/websocket-echo`, 150 functions, 73 externs, 15 `leaf`).
- `echo` calls `ReadStream.next`, which reaches `msstd_websocket_receive` through `call.method`; every function on the path becomes a state machine and a caller stores its callee's frame.
- 114 of 150 are "may park" today because only 15 externs are `leaf` and every indirect call counts. A real "may wait" effect (natives declared `waits`, waiting callees, indirect calls by target set) is estimated at 27 to 71 functions (estimate; stage 1 measures it).
- 58 functions use depth ops and 33 use slots. The frame must be a heap block (`TypeDef.indirect`) with slots as fields and `step` taking a pointer; holes (`take`, `move.out`, `fill`) need the move state of `cancel-cleanup-by-edge.md`.

**Rules.**
- Calling form: a waiting function has `start`, `step`, `cancel`. A caller embeds the frame of a statically known, non-recursive callee; indirect callees and waiting recursion allocate per call, sized from `frame_size` in the closure or vtable header. The depth guard stays, so waiting recursion keeps its fault.
- Wait natives split into `begin`, `result` and `cancel(ticket)`; cancel must stop the pending operation before its buffers are dropped. Completions use the ready ring of `runtime/io` (W5); the scheduler (W11) holds `{step, frame}` per task.
- Cancel is itself resumable: its drops include shielded closes that can wait (`msrt_shield_enter; call @close`), so `cancel` is a state machine entry, not a plain function.
- Natives that call waiting generated code (`closure.new @serve.stream` passed to `msstd_http_serving_new`, sort comparators, iteration callbacks) cannot be suspended. Each is rewritten in begin/result form, moved to `.ms`, or forbidden from waiting.
- Borrowers: promise work (`task::lend_current`), `pool::run_shielded` and `promise::ask` read or write a creator's frame. A heap frame must outlive them even if the creator finishes or is cancelled.
- Faults: a fault in a nested `step` frees the parent frames by explicit exits. This needs `cancel-cleanup-by-edge.md` through its fault and holes stages; no mixed module (that proposal found them unsound), so conversion is whole-program and gated.
- Traces and debug: a frame records its function and state; `fault_tables.rs` maps state to line; debug info for frame types is part of stage 4.
- Code size: the real pass keeps one body and demotes crossing values to frame slots; the clone-per-wait form is measured against it first.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| MIR in C (W18) | the transform in its in-place form, written once there | MIR interpreter test, conformance |
| `crates/ms-mir/src/unwind.rs`, `cancel_exit.rs` | cancel and fault exits from frame state | sweep (#4052), cancel fixtures |
| `crates/ms-lower`, `ms-check` | `waits` natives, "may wait" effect, calling form | effect fixtures |
| `runtime/` (W5, W11) | begin/result/cancel natives, task = frame | `make c-test`, corpus |
| `crates/ms-rt/src/task.rs`, `task/`, `sched.rs` | deleted at the end (about 4k lines) | corpus on six platforms |

## Alternatives

- Do nothing: hibernation (3.8 KB) plus thin park frames. Evidence needed first; stage 0 measures it.
- Smaller stacks with growth: removes the page floor, keeps switching, guard pages and unwinding.
- Hand-written callbacks in the runtime only: moves the cost to every stdlib author.

## Stages

0. Measure the do-nothing case in `ms`: idle websocket bytes with hibernation plus the thinnest park frame the C runtime can give. Proceed only if the state-machine estimate (0.2 to 0.5 KB) is still worth the compiler change; otherwise report to Chinmay.
1. "May wait" effect and `waits` natives; gate: the waiting-function count against the 114 above, and the http-tail and tasks benchmarks no slower than the latest dated baseline.
2. In-place transform with slots and holes on `WebSocketSource.next` and the echo handler; gates: compile time and binary size within a limit set from the router fixture, conformance green.
3. Nested and indirect calls; gate: idle chain bytes for 8,000 connections in `ms` against 0.2 to 0.5 KB.
4. Cancel, faults, borrowers, traces on frames; the sweep passes.
5. Runtime flip with W11: stacks deleted; gate: corpus on six platforms, Windows completion-port buffers pinned in the frame.

## Open questions

- None for the language. Waiting recursion keeps its fault only if the depth guard stays; stated so no one finds a behaviour change later.
