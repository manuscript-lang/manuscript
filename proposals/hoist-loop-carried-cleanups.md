# Hoist cleanup registration for loop-carried owned values

## Summary

- Problem: inside a promise task, a loop that updates an owned list registers and discards a runtime cleanup on every iteration, about 39% slower than the same loop called directly.
- Change: when a loop-carried owned value is only updated in place (`list.set`), register it once before the loop and discard it where the loop exits, as `hoist_loops` already does for values the loop never consumes.
- Decision requested: build it (one pass, one crate); the string-equality cost behind `index_of` is a separate stage.

## Status

Stage 1 implemented 2026-11-14 (185 ms to 113 ms, 3.51G to 1.21G instructions); stage 2 not started. Checked against `main` 346c70a5. Skeptical review: design fits only after three changes (register the pre-header's own parameters, scalar elements only, test the fault paths); applied below.

## Problem

`crates/ms-mir/src/unwind.rs` guards every faulting instruction with `msrt_cleanup_push` and `msrt_cleanup_discard` for the owned values live across it, and the guard runs only in tasks (frame header byte 9). `hoist_loops` removes this for values live into a loop header that the loop never consumes. A list updated by `hist[i] = ...` is not such a value: MIR threads it through a header block parameter (`%23: move list<int>`) and `list.set %23, ...` consumes it and returns a new value passed back on the latch.

Measured (`bench/perf/suite/workers` chunk loop, 200000 iterations, 1 thread, min of N): called directly 113 ms, inside `promise[Int](fn: ...)` 157 ms, Rust 101 ms. The extra 44 ms is the push (build a three-word record, link it) and discard around the overflow and bounds checks, each iteration. Any CPU loop that mutates a list, map or buffer in a task pays it.

## Design

A header parameter is *stable* when every latch argument for it is exactly the result of a `list.set` whose list argument is that parameter, and the element type needs no drop. Native `list.set` stores in place and returns the same pointer, length and capacity (`mir_llvm/lists.rs`, `clif lower/list.rs`), so a record built once names the live storage for every value in the chain. Elements that need a drop are excluded: `list.set` drops the old element before the store, so a faulting or parking close would unwind a list that still holds the dropped element.

- `held` is built from values live before the header, which never includes a header parameter. `hoist_loops` instead registers the pre-header block's own copy of each stable parameter, marks it owned, and marks every value of the chain (the parameter and each `list.set` result) covered in the loop body; `consumed_inside` ignores a `list.set` argument inside a stable chain.
- Exits and `ret` discard the registration first, as today; the value is then owned and dropped by the ordinary plan.
- A bounds fault inside `list.set` now drops the list (today the consumed list is not registered and leaks); the test asserts it.
- A latch that passes the parameter through unchanged on some path, or mixes `push` and `set`, is not stable. An outer loop whose latch carries an inner header parameter is not stable; the inner loop hoists per outer iteration.
- The interpreter's `list.set` copies a shared list (`interp/data.rs`), so it is outside this rule; the pass registers cleanups only in native code.
- A chain with any other consumer (`list.push`, a call taking it by move) is not stable and keeps per-instruction registration. Nothing else changes.
- Cancellation inside the loop drops the entry record, which names the live storage: the same blocks the loop holds.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir/src/unwind.rs` | stable-chain detection in `hoist_loops`, `consumed_inside` | unit test on a `list.set` loop: one push before the loop, one discard per exit, none inside |
| `tests/conformance/fixtures` | task loop that sets a list element and then hits an index fault, an overflow fault and a cancellation; no leak, no double free | conformance, both backends |
| `bench/perf/suite/workers` | dated result with the 1-thread gap | rerun |

## Alternatives

- Do nothing: workers stays at 1.63x Rust at 4 threads; the 1-thread loop is 1.55x.
- Make `msrt_cleanup_push` cheaper: it is already a three-word store and a link; the cost is doing it every iteration.
- Teach the pass about in-place updates for every op (push, insert): changes the record each iteration, so it needs update calls; only `list.set` is a pure in-place update.

## Related stage: generic loop cost behind `index_of`

`List.index_of` on `List[String]` is 54 ms against 20 ms for Rust. The inlined loop is about 44 instructions per element, nearly all in the branchless string-equality decision (mask, shift and `cmov` chains over both tagged words) that decides between "equal", "different" and "call `msrt_string_eq`". An inline slow-path compare removed only 4% (56 to 54 ms), so the cost is the decision. Hypothesis: test the two words for equality first, then compare lengths, and branch to the rest. Stage 2, gated on an instruction-count drop in `bench/perf` `index_of` and `contains` against the latest baseline.

## Stages

1. Unwind hoisting; gate: workers 1-thread promise time within 10% of the direct call, conformance green on both backends.
2. String equality decision; gate: per-element instruction count under 30.
