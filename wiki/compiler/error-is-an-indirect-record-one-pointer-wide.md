[Wiki](../index.md) › [Compiler and build](index.md)

# Error is an indirect record, one pointer wide

Measured (2026-11-04): `Error` was 11 words, so every `T!` was 12 words and a fallible recursive `walk` had a 416 B release / 480 B Cranelift-debug frame, against 128 B / 192 B for the same function returning `Int`. `TypeDef.indirect` (set in `ms-lower/src/cx.rs` for `Builtin::Error`) makes the record a pointer to a heap block; after the change the frames are 224 B / 288 B.

Rules: `TypeSet`/`TypeFill` build a fresh block and free the old one, never writing in place, because MIR passes treat record values as SSA values. `TypeRelease` and drop glue free the block. Nothing in Rust reads an `Error` layout; the runtime moves it by `TypeDesc` glue. The blank record that `rtcall.rs` builds for a native call with an absent optional record leaks one block if that record is indirect; `Error` is never that argument.

Apply when: adding a record repr, changing `Error` fields, or tracing frame size (`objdump` the `sub rsp` of the function; the stack-slot temporaries and the inlined `Error` construction are the remaining cost).
Evidence: [proposal](../../proposals/boxed-error-record.md).

## Temporary slots are shared between blocks

`crates/ms-clif/src/slotshare.rs` gives the k-th block-confined temporary of every block one slot (call out-parameters, string copies, spilled call arguments; `Lower::temp_slot` / `spill_temp`). A slot whose address is stored, returned, branched with or used in a second block keeps its own. Do not use `spill_temp` where the runtime keeps the address: `msrt_cleanup_push` holds its slot until the scope ends, and sharing it crashed the HTTP e2e fixtures with SIGSEGV. After: the error-reachable `walk` is 240 B Cranelift debug and 208 B LLVM release; the remaining release cost is the inlined `Error` construction (a 56 B map copy) plus the saved registers.

## Empty maps and the park path

`msrt_map_new` has `ExternRole::MapNew`: code generation emits seven zero words (`ms_rt::map::empty()` is all zero, a unit test pins it), so building an `Error` needs no call or 56 B slot. After that the error-reachable `walk` is 128 B in release, equal to its non-fallible version.

Frames that stay on the stack while a task parks (`switch_away`, `msrt_token_park`, `msrt_promise_wait`, `Promise.wait`) were 208, 320, 256 and 784 B; they are now 96, 96, 112 and 96 B. The Rust ones shrank by marking cold or heavy helpers `#[inline(never)]` (`set_deadline`, `expire_timers`, `poll_ready`, `reactor_wait`, `deliver_remote_posts`, `cancel_all_waiters`, `init_current`): LLVM sizes a frame for the largest inlined path, so any inlined cold path is paid by every parked task. `Promise.wait` builds its errors in one `failure` function for the same reason. Cleanup-entry slots (`msrt_cleanup_push`) are still one per owned temporary and are not shared.

## A collection field in an indirect record is a nullable pointer

An `Error` was 88 B: message 16, kind 16, and the seven-word `details` header inline. An indirect record now stores a `Map` or `Set` field as one pointer (`Layouts::type_field_boxed`, `type_block`), so `Error` is 40 B. The pointer is null while the collection is the all-zero empty value (descriptor word also zero, since a stamped empty map keeps its header); the first insert through `PtrField` allocates a zeroed header (`map_header_ensure`). Source stays the same: `Error(msg, kind: k, details: {...})` and `err.details[...]` read and build the field as before, because `TypeGet`, `TypeNew`, `TypeSet` and the glue expand and pack it (`type_load_field`, `type_pack`).

Rules: free a record only through `type_release` (drops what was not moved out, frees non-null headers, then the block) or `type_free_block` (contents already moved); a plain `free(block)` leaks the header. A place read of `err.details` through `PtrField` allocates the header once, which is harmless but not free; use `TypeGet` when only reading.

Measured (2026-11-12): dropping an `Error` with no details is a null check instead of a `msrt_slot_drop` of seven zero words; `result-records` 10.9 to 9.0 ms against Rust 5.9 ([bench](../../bench/perf/element-types/README.md)).
