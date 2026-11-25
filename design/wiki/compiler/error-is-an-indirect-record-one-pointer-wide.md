[Wiki](../index.md) › [Compiler and build](index.md)

# Error is an indirect record, one pointer wide

Measured (2026-11-04): `Error` was 11 words, so every `T!` was 12 words and a fallible recursive `walk` had a 416 B release frame, against 128 B for the same function returning `Int`. `TypeDef.indirect` (`compiler/mir/mir_layout.c`; set for `Error`) makes the record a pointer to a heap block; after the change the frame is 224 B.

Rules: `TypeSet`/`TypeFill` build a fresh block and free the old one, never writing in place, because MIR passes treat record values as SSA values. `TypeRelease` and drop glue free the block. The runtime does not read an `Error` layout; it moves it by type-descriptor glue (`mir_glue*.c`). A blank type built for a native call with an absent optional record leaks one block if that record is indirect; `Error` is never that argument (check this in `compiler/lower/lower_native*.c`).

Apply when: adding a record repr, changing `Error` fields, or tracing frame size (`objdump` the `sub rsp` of the function; the stack-slot temporaries and the inlined `Error` construction are the remaining cost).
Evidence: [proposal](../../proposals/boxed-error-record.md).

## Temporary slots are shared between blocks

Verified: the emitter gives block-confined temporaries one shared slot (`emit_slot_pool`, `compiler/emit/emit_cx.h`); a slot whose address is stored, returned, branched with or used in a second block keeps its own. Do not share a slot where the runtime keeps the address past the call (a task argument): sharing a slot the runtime held crashed the HTTP e2e fixtures with SIGSEGV. `MS_POISON_SLOTS=1` (`make poison-check`) fills dead slots and catches stale views.

## Empty maps and the park path

An empty map is seven zero words, so building an `Error` needs no call or 56 B slot (`runtime/core/map.c`). Frames that stay on the stack while a task parks (`switch_away`, promise wait) were 208 to 784 B and are now about 100 B: mark cold or heavy helpers `noinline`, because LLVM sizes a frame for the largest inlined path and every parked task pays for an inlined cold path.

## A collection field in an indirect record is a nullable pointer

An `Error` was 88 B: message 16, kind 16, and the seven-word `details` header inline. An indirect record now stores a `Map` or `Set` field as one pointer (`mir_layout.c`, the indirect type's block leaves), so `Error` is 40 B. The pointer is null while the collection is the all-zero empty value (descriptor word also zero, since a stamped empty map keeps its header); the first insert through a pointer field allocates a zeroed header . Source stays the same: `Error(msg, kind: k, details: {...})` and `err.details[...]` read and build the field as before, because the type ops and the glue expand and pack it.

Rules: free a record only through the type release glue (drops what was not moved out, frees non-null headers, then the block) (contents already moved) in the glue; a plain `free(block)` leaks the header. A place read of `err.details` through a pointer field allocates the header once, which is harmless but not free; read with the get op when only reading.

Measured (2026-11-12): dropping an `Error` with no details is a null check instead of a `msrt_slot_drop` of seven zero words; `result-records` 10.9 to 9.0 ms against Rust 5.9 ([bench](../../../bench/perf/element-types/README.md)).
