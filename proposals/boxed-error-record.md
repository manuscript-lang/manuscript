# Error is one pointer: smaller frames for every fallible function

## Summary

- `Error` is an 11-word record (message 2, kind 2, details 7), so every `T!` is 12 words. Each fallible function returns through a 96-byte area and keeps the unpacked words in its frame.
- Change: the standard `Error` record lives in a heap block and its value is one pointer. `T!` becomes a tag and a payload word. No syntax, semantics or runtime ABI change.
- Decision requested: approve a record repr flag, `RecordDef.indirect`, set for `Builtin::Error` only.

## Status

Implemented, 2026-11-04, on main e6c1e2b4. A skeptical review asked for the debug baseline above and flagged in-place `RecSet`; the implementation allocates a fresh block and frees the old one instead, so no block is written in place. After: `walk` with the error path is 0xa8 + 56 = 224 B release and 0x110 + 16 = 288 B debug (from 416 and 480). Conformance corpus, 380 e2e fixtures and the leak sweep (365 programs) pass. Part of the frame-size work started by the "million tasks" thread (141 B/frame LLVM, 390 B Cranelift on `million-tasks/frames.ms`).

## Problem

Measured on this sandbox (x86_64 Linux, `objdump` of the frame of `walk`, the recursive tree walk of `frames.ms`: a string, a list, two recursive calls). `walk` returning `Int!` with a real `error(Error("neg"))` path:

| build | `walk` returns `Int` | `walk` returns `Int!`, error reachable |
| --- | --- | --- |
| LLVM release | 128 B (6 pushes + 0x48 + return address) | 416 B (0x168 locals) |
| Cranelift debug | 192 B (0xb0 + 16) | 480 B (0x1d0 + 16); 400 B with the error path unreachable |

(The shipped `frames.ms` shows 128 B in release only because LLVM proves its `Int!` never errs and drops the error path.)

- The park path is the same: `Promise.wait` returns `T!` and has a 0x2d8 (728 B) frame; `switch_away` 208 B, `msrt_token_park` 320 B, `msrt_promise_wait` 256 B. Resident stack per parked task is about 2.9 KB, and stage 1 hibernation copies exactly the used bytes.
- Nothing in Rust reads an `Error` layout: values are built in MIR (`error_record`, `rtcall.rs`) and moved by `TypeDesc` glue (`msrt_promise_take[Error]`).

## Design

- `RecordDef` gains `indirect: bool`, set in `ms-lower/src/cx.rs` for the record where `t.is(Builtin::Error)`, the way `Std::Result` is set for the alternative. It is a layout fact only; MIR text, interpreter, optimizer and verifier ignore it.
- `ms-clif/src/layout.rs`: an indirect record has the single leaf `i64`, a pointer to a block laid out as the concatenated field leaves (`Layouts::rec_block`). `Shape` of an alternative holding it shrinks by 10 words with no other change.
- `ms-clif/src/lower.rs`, the six places that read record leaves: `RecNew` allocates the block and stores the fields; `RecGet` loads the field's leaves; `RecSet`/`RecFill` build a fresh block from the old fields and free the old one (the set consumes its input); `RecRelease` and drop glue read the block, drop the fields, free it; clone glue allocates a new block of cloned fields; `PtrField` loads the block pointer first.
- Borrows are free: a borrowed `Error` is a pointer copy and is never dropped, as for every borrowed value today. `error(e)` moves the pointer into the `Result`; no allocation on the error path beyond building the `Error` itself.
- Cost: one `msrt_alloc`/`msrt_free` per `Error` created, on a path that already allocates `details` and message strings (a literal message and `kind` do not allocate today, so this adds one allocation to `error(Error("x"))`).
- Parity: the change is in backend-independent Cranelift IR, which the LLVM path translates, so Linux, macOS and Windows share it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir` `RecordDef`, parser | `indirect` field, default false | MIR round trip unchanged |
| `crates/ms-lower/src/cx.rs` | set `indirect` for `Builtin::Error` | existing conformance corpus |
| `crates/ms-clif` layout, lower | indirect record repr, six sites | a Rust test of `Result[Int, Error]` width; frame-size test on `frames.ms` variant |
| `bench/perf/` | dated page: frame bytes, recursion depth per MiB, `T!` call cost | before/after on this machine |
| `wiki/compiler` | one page on the indirect record | |

## Alternatives

- Do nothing: fallible recursion costs 416 to 480 B per frame, so a 512 KiB task stack holds about 1,100 frames of fallible code.
- Box the `Err` case of every `Result` payload over two words: general, but `alt.view` wraps a borrowed payload with no owner for a new block, and every alternative site (construct, get, take, release, unbox, glue) changes. Rejected: more sites and a leak hazard for the same effect on `Error`.
- Shrink `Error`: `details` is a 7-word `Map`; a smaller map header or a list of pairs changes the public type and map performance.
- Box every record over N words: user records lose locality and gain an allocation per construction; no evidence it helps.

## Open questions

- Should `indirect` be generalised to a declared marker for user types? Recommended: no, not until a second type needs it.
