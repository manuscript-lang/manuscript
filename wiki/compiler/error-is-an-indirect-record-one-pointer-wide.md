[Wiki](../index.md) › [Compiler and build](index.md)

# Error is an indirect record, one pointer wide

Measured (2026-11-04): `Error` was 11 words, so every `T!` was 12 words and a fallible recursive `walk` had a 416 B release / 480 B Cranelift-debug frame, against 128 B / 192 B for the same function returning `Int`. `RecordDef.indirect` (set in `ms-lower/src/cx.rs` for `Builtin::Error`) makes the record a pointer to a heap block; after the change the frames are 224 B / 288 B.

Rules: `RecSet`/`RecFill` build a fresh block and free the old one, never writing in place, because MIR passes treat record values as SSA values. `RecRelease` and drop glue free the block. Nothing in Rust reads an `Error` layout; the runtime moves it by `TypeDesc` glue. The blank record that `rtcall.rs` builds for a native call with an absent optional record leaks one block if that record is indirect; `Error` is never that argument.

Apply when: adding a record repr, changing `Error` fields, or tracing frame size (`objdump` the `sub rsp` of the function; the stack-slot temporaries and the inlined `Error` construction are the remaining cost).
Evidence: [proposal](../../proposals/boxed-error-record.md).
