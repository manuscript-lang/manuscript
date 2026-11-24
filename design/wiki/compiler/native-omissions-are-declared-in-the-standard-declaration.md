[Wiki](../index.md) › [Compiler and build](index.md)

# Native omissions are declared in the standard declaration

Verified: defaults for native functions, methods, and constructor fields are written in the standard `.ms` declaration and checked as ordinary expressions. Constructor omission follows source metadata, application implementations inherit standard interface default permissions and receive concrete values, and native compositions pass `some(n)` through source-defined streams.

Apply when: adding native defaults, changing source/native signatures, or implementing stream compositions.
Evidence: [native default checking](../../crates/ms-check/src/native_defaults.rs), [native defaults fixture](../../../tests/conformance/fixtures/e2e/stdlib/defaults.ms), [stdlib revamp fixture](../../../tests/conformance/fixtures/e2e/accept/stdlib-revamp.ms).
Verify: exercise stored, bound, and generic calls that omit a defaulted argument and fresh records; omit a limit through an application-defined ReadStream and match `none`.

## Native receiver operations are derived from the declaration

Verified: a bodiless inherent method of a standard type is a native receiver operation, found by the loader (`is_receiver_native` in `ms-check/src/stdlib.rs`); there is no table of bindings. Its native identity is the method name, so lowering tells receivers apart by type: a `native == "chars"` test also needs `str_recv`, and `abs`, `sign` and `compare` check `is_int` or `is_float`. Kept callbacks and owned values are declared with `move` in the `.ms` declaration (`fn var List[T].append(move value: T)`, `extern fn msrt_promise_start(id: Int, move work: fn() Void)`); the checker reads only that. Chinmay declined `.ms` markers in 2026-11-03 and reversed it on 2026-11-17 ([declared move mode](../../proposals/declared-move-mode.md)). Lowering still reads the runtime's `// ms: takes:<param>` / `keeps:<param>` as ABI facts from `rt_symbols.txt`; `ms-check/tests/extern_moves.rs` fails when an `extern fn`'s `move` parameters and its symbol's flags disagree, so the two cannot drift.
Apply when: adding a native method or a receiver-specific lowering arm; a name-only match collides with other receivers.
Verify: `make conform`; `extern_move_markers_match_the_runtime_flags`.

Decision (Chinmay, 2026-11-03): the duration units are methods, `3.seconds()`, `500.milliseconds()`, `2.minutes()`, declared on `IntOperations` in `intrinsics.ms` and lowered by receiver type to the runtime's checked `msstd_time_int_*`; the property form `3.seconds` and its checker special case are gone. `.seconds` on a `Timestamp` is a field and is unchanged.
