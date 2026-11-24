# Drop and clone functions for records and enums are written in MIR

## Summary

- Problem: each backend writes its own drop code for a record or an enum (Cranelift `lower/glue.rs`, LLVM `glue_llvm.rs`), including which cases own something, which are borrowed, and how the shared payloadless block of a boxed enum is skipped. Two copies of one language rule can disagree.
- Change: a MIR pass makes one drop function per type, and both backends call it.
- Decision requested: none; this is the first stage of the direction "language logic in MIR, backends only lower".

## Status

Proposal, 2026-11-16, checked against `e0fab5d0`. Stage 1 of the audit in the thread "Move language logic out of the backends into MIR". Clone functions follow in stage 2 (same pass, `Module::clone_glue`: clone every field, rebuild with `type.new` or `alt.new`). Stage 3 adds flag-and-payload optionals and lists (a drop loop over `list.get_u`, a clone loop with `list.push_u`; lists of plain elements keep the backends' block copy) and makes only the functions a program drops or clones, so the pass adds no compile time. Interfaces, closures, strings, maps and types that contain themselves stay in the backends for now.

## Problem

- The drop of an enum is a walk over its cases: skip a borrowed case, drop each owned field, free the block unless the case is a shared payloadless block. Cranelift writes it in `glue_drop_alt`, LLVM in `drop_alt`; the record walk and the boxed-record block release are written twice as well.
- Equality and hash functions are already MIR (`Module::desc_glue`, built in `ms-lower/src/eq.rs`), so drop is the odd one out.

## Design

- `ms_mir::glue::run` runs after `expand` and before `expand_owned`. It finds every record and enum type a value of the program can have, and for those that need a drop and cannot reach themselves, it makes a function whose body is `type.release` (record) or a switch on the tag with one `alt.release` per case (enum). `expand_owned` then lowers the release shorthands like everywhere else.
- `Module::drop_glue` maps a type to its function. `Gen::glue` in both backends returns that function for `Glue::Drop` instead of queueing their own body. The LLVM backend keeps these functions on the leaf calling convention so callers name one symbol.
- The `Glue` kinds and the glue name prefix move to `ms_mir::glue`; both backends had identical copies.
- The verifier skips these functions: they are written after ownership elaboration and some paths do not consume the parameter in the way its rules ask.

## Alternatives considered

- Do nothing: the two copies stay and can drift; every later change to enum layout needs two edits.
- Generate every kind of drop (lists, optionals, interfaces, self-containing types) at once: needs a stack-depth op and list loops in MIR, which other threads are adding; one large PR is harder to check.
- Generate the body from primitive ops directly: needs the same release lowering that `expand_owned` already has, so it would copy it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-mir` | `glue` pass, `Module::drop_glue`, verifier skip | conformance corpus on both backends |
| `ms-clif`, `ms-mir-llvm` | use the MIR drop function; shared `Glue` kinds | conformance corpus, `cargo test` for both crates |
| `ms-build` | run the pass | corpus |

## Measurement

Against `e0fab5d0` on a generated 1,000-module project (a record and an enum per module): release build 19.1 s to 15.0 s (median of 5), check 0.23 s to 0.29 s median with equal minimum (0.21 s and 0.19 s), debug build 1.87 s to 1.81 s. Ten suite programs run at equal speed within noise (for example `interp`, 11 alternating runs: median 0.228 s base, 0.223 s new).

## Stage 4: slot and block glue

The functions that descriptors and interface vtables point at are made in MIR too: slot drop (`take`, `drop`), slot copy (`load`, `clone`, `put`) and the interface payload block drop and clone (the clone allocates with `msrt_alloc`). They are keyed in `Module::addr_glue`. The pass finds the descriptor types by walking `typedesc` ops and each descriptor's inner types, using the same `statics::descriptor` plan the backends use, so the set matches. Generated debug build of the 1,000-module project: 15.2 to 15.9 s against 15.2 to 16.9 s on main (three runs each); the corpus passes 1460 of 1460 on both backends.

## Stage 5: interface drop

Two small ops, `iface.tag` (the ownership tag of the vtable word: 0 owns box and payload, 1 only the box, 2 nothing) and `iface.destroy` (runs the payload destructor in vtable slot 0), let the interface drop be written in MIR: destroy when the tag is 0, free the box when it is 1. Both backends lower the two ops; the interpreter reports them as native only. Corpus 1460 of 1460 on both backends.

## Stage 6: closures

The closure drop (heap and framed), the drop-from tail registered while a capture closer runs, and the clone entry are made in MIR from `ptr.add`, `take`, `load`, `put`, `cleanup.push` and `func.addr`, with capture offsets from `Layouts::closure`. They are keyed in `Module::addr_glue` by the closure function. Demand is every `closure.new`, with the framed variant read from `frames::framed_closure_objects`. Corpus 1460 of 1460 on both backends. Suite `dispatch` (closures and interfaces), nine alternating runs: median 0.287 s base, 0.296 s new (noise); the binary grows 280 bytes. Debug build of the 1,000-module project: 20.8 to 21.5 s base, 20.5 to 21.4 s new.

## Stage 7: boxed optionals, maps and sets

A boxed optional is dropped with `opt.unbox` (the payload moves out of the box, which is freed) and cloned like any optional. A map or set is dropped and cloned in MIR through a stack slot and the runtime's `msrt_slot_drop` and `msrt_slot_copy` with its descriptor, as the backends did. Corpus 1460 of 1460 on both backends.

## Stage 8: drop of data that contains itself

`stack.near N` (new op: whether the stack pointer is within N bytes of the segment limit) lets the guard of recursive drops live in MIR. A recursive type's drop function is a wrapper: when the stack is within `DEEP_DROP_HEADROOM`, `msrt_drop_enter` decides whether to park the value (`msrt_drop_defer` with the slot drop function, a block holding the value) or run the body, and `msrt_drop_leave` follows the body. The body of a boxed enum with a tail field (`Cons(head, tail)`) is a loop: it reads the tail, releases the block with the tail marked moved, and continues with the tail, so a long chain does not recurse. The copy of recursive data (the chain copy needs an op that fills a field of a fresh block) stays in the backends. Corpus 1460 of 1460 on both backends. Instruction counts for `interp` under callgrind: 2,983,575,576 on main, 2,983,575,590 here; wall times of `exprparse`, `objgraph` and `treegrep` equal or better (minimum of seven runs).

## Stage 9: demand from vtables and from expansion

Types dropped only by a vtable's payload block, a descriptor slot function, or a drop that
`expand_owned` emits had no MIR function, so the backends still generated their drops. `glue::run`
now also seeds from the slot and block types and repeats with `expand_owned` until nothing new is
wanted. A corpus run (4,042 fixtures, Cranelift) with the backend fallback logged shows no drop
generated by the backends. The remaining clone fallbacks are bytes, plain lists, interfaces and
recursive data, all excluded on purpose. Debug compile time of the 1,000-module project: 15.79 s
before, 15.57 s after. Callgrind on `bench/perf/clone-costs`: 2,813,658,955 before, 2,817,658,628
after (+0.14%).

## Stage 10: the backends no longer write drops

`ClifGen::glue` and the LLVM `direct_glue` now assert that only copies of recursive data (`Clone`,
`SlotCopy`, `BlockClone`) and cleanup thunks are made by a backend; every drop, slot, block and
closure function comes from MIR. The drop, closure and release-shorthand bodies in `ms-clif`
`lower/glue.rs` and `ms-mir-llvm` `glue_llvm.rs`, and `glue_llvm/closure.rs`, are deleted (about
870 lines net). Debug compile of the 1,000-module project: 16.28 s before, 16.31 s after. Callgrind
on `bench/perf/clone-costs`: 2,813,659,688 before, 2,817,659,361 after (+0.14%, the same as stage 9).

## Stage 11: the clone of recursive data in MIR

Recursive types now get MIR clone functions. A boxed alternative with a chain (`Cons(head, tail)`)
is a loop: each round clones the other fields, makes the block, stores it where the previous
block's tail leaf points (found with `ptr.add` and the block layout) and goes on with the source's
tail. Other recursive data recurses, behind a wrapper that runs the copy on a new stack segment
through `msrt_slot_copy_grown` when `stack.near` says the stack is nearly used up. The backends
make clones only for bytes, lists of plain elements, interfaces and nullable optionals, and
`copy_boxed_iter`, the chain copiers, the segment growth and the field walks are deleted from both
(about 540 lines net). A first version that recursed through the chain ran a 3M-node copy 60%
slower, which is why the chain stays a loop; callgrind on a 300k-node chain copy is 25,561,659
before and 25,561,751 after. `bench/perf/clone-costs`: 2,813,659,688 before, 2,817,659,301 after
(+0.14%). Debug compile of the 1,000-module project: 15.69 s before, 15.81 s after.
