# A promise start builds its closure once, in place, and names its call site as a constant

## Summary

- Problem: `promise[Int](fn: work(i))` costs about 2,575 instructions on one thread; the same shape in C costs 270 (callgrind of `bench/perf/async-primitives` `inline`, tasks thread, 2026-11-23). Two of the causes are compiler-side: two heap closures per promise (about 350 instructions: `ms_alloc` 32, `mi_malloc` 39, `ms_free` 33, `mi_free` 53, `msrt_obj_drop` 50, closure drop glue about 145) and a run-time capture of 8 return addresses to remember where the promise started (`ms_frames_capture` 169 plus `ms_fault_capture_frames` 31, about 200).
- Change: (1) build one closure per promise, not two, and build it in storage the promise owns; (2) take the call site from the start entry's return address instead of walking 8 frames.
- Decision requested: none; no language or syntax change. Chinmay, 2026-11-23: "let's get closer to c level"; coordinator: make the two changes general for all closures.

## Status

Proposal, 2026-11-23. Runtime entries are the tasks thread's (`src/runtime/core`); this proposal fixes their shape.

## Problem

`promise` in `stdlib/concurrency/promise.ms` starts `fn: complete(id, entry())`. After inlining into the caller, `emit --opt` shows `closure.new @closure.3 %i` (the user's closure, 32 bytes) and `closure.new @closure.16 %id, %entry` (the wrapper, 40 bytes), and the LLVM IR has two `msrt_alloc` calls. A captured closure is a `MK_FN` leaf, one pointer word (`mir_closure_layout` in `mir_layout.c`), so the wrapper holds a pointer to a second heap object; nothing lays a captured closure inline today (the tasks thread assumed it did). Before this proposal's stdlib edit the wrapper was also built three times, once per `match` arm, each capturing the same user closure, which would have blocked a single-owner rule.

The site: the three start entries call `ms_fault_capture_frames` on every promise, but the frames are read only when the promise faults (`ms_frames_describe`, the `task started by:` line).

## Design

1. Embedded closure captures. When a `closure.new` captures a value that is itself a `closure.new` in the same function, moved into this capture and used nowhere else, lay the inner object inside the outer block (the capture's leaf is the inner object's header and captures, not a pointer), and let the outer's drop and clone glue run the inner's framed drop and in-place clone (`MG_CLOSURE_DROP_FRAMED` exists). The inner is only ever called (`call.ind` takes its address as outer plus offset) and never freed on its own, because its single owner is the outer. General: any closure that wraps a closure literal, not only promises. Precondition in `promise`: bind the wrapper once before the `match` so the user's closure has one capturer (stdlib edit, done on this branch).
2. Closure in place. A closure object is a three-word header (clone, drop, code) then its captures; `MG_CLOSURE_DROP_FRAMED` already drops captures without freeing the block. Add `closure.new` over caller-supplied storage (the `framed` form) fed by a runtime-owned block: `p := msrt_promise_closure(id, size)` (per-thread slab of fixed cells, heap past the cell size, tasks thread's offer), then the start entry takes that closure as today and releases the storage after the run or when unstarted work is dropped. Row tables grow, so storage is not in the row. Generality: any `extern` that takes an escaping closure can declare "closure storage from this call" in its signature (`NS_CLOSURE_STORAGE` in the native signature table); the compiler builds the closure there and uses the framed drop glue.
3. Site from the return address. Review (skeptical subagent, 2026-11-23) found a compiler-built constant wrong: `capture_started` keeps up to 64 frames and strips leading `@std` frames, a `blockaddress` is not a return address, and the result would depend on whether the inliner fired. The runtime needs no compiler help: each start entry reads `__builtin_return_address(0)`. When `promise` was inlined into program code that address is the program's call site and one symbolization gives the `task started by:` line (Chinmay: one line, the first program frame). When it is a `@std` frame (a stdlib wrapper starts the promise), the entry falls back to today's frame walk, so the report is the same either way. Cost: a few instructions instead of about 200.

## Order, after review

1. Return-address site (tasks thread; no compiler change) and the bind-once edit in `promise.ms` (here). Re-measure instructions per promise and the wall time of a realistic fan-out (`bench/perf/async-primitives`, not only `inline`).
2. Only if the remaining cost justifies it, embedded captures and runtime-owned storage. Open questions the review raised: per-function layout state so every `closure.new` of a function agrees; inner clone and drop glue in place (`mir_glue_closure.c`), including inner closers under cleanup push and shield; a `Spread` or remote start releases a slab cell on another thread (remote-free path); a cell leaks when an early `?` leaves between `msrt_promise_closure` and the start; a framed or borrowed user closure (`promise.ms` docs: captures read in place).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/concurrency/promise.ms` | wrapper bound once | `async-primitives` `inline` instruction count, promise fixtures |
| `mir/mir_layout.c`, `mir_glue_closure.c`, `emit/emit_closure.c`, `emit_call.c` | captured closure literal laid inline; closure built into runtime storage for externs marked so | `close-matrix`, promise fixtures, ownership-fuzz |
| `runtime/core/promise*.c` (tasks thread) | start entries read their return address, fall back to the frame walk for `@std` frames | `promise-fault-started-line` (#6782) with and without inlining |
| `runtime/core/promise*.c` (tasks thread) | `msrt_promise_closure`, site argument | their tests |

## Alternatives

- Do nothing: 2,575 against 270 instructions stays.
- Runtime `(code, drop)` entries with a raw captures pointer (tasks thread's first offer): equal speed, but the compiler then needs a second capture-reading convention beside closures; one closure form for every consumer is simpler.
- Caller-site parameter (`track_caller`) or a compiler-built constant: a language-visible feature or an inliner-dependent address for a diagnostic line; the return address needs neither.
- Only step 1: saves one of the two objects (about 175, after step 1); steps 2 and 3 remove the rest of the 550.

## Stages

1. Embedded captures; measure the instructions per promise. 2. Site constant. 3. Closure in runtime storage. Each with `bench/perf/async-primitives` before and after against the latest dated baseline.

## Not here

The remaining per-promise cost (six `msrt_cleanup_push`/`discard` pairs, about 260, and one guard call, about 150) is the static unwind tables proposal.
