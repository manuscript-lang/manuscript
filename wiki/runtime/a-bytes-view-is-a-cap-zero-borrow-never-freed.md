[Wiki](../index.md) › [Runtime](index.md)

# A Bytes view is a cap-zero borrow that is never freed

Decision (Chinmay, 2026-11-03): O(1) slicing of `Bytes` must fit the one-owner model, so `Bytes.view(start, end)` lends the receiver (like `List.get`) instead of sharing storage with a refcount. `slice` stays a copying `Result`.
Verified: a `Bytes` with `cap == 0` and `len > 0` is a non-owning view (`msrt_bytes_view`); `msrt_bytes_drop` skips it, `clone` copies it. The checker lists `Bytes.view` in `native_lend_receiver`, so storing a view or changing the source while it lives is rejected. Lowering writes the header to a slot and `load`s it, so MIR sees a borrow; a temporary receiver is copied out instead. A native `call.rt` result of type `Bytes` is owned by default, which is why a returned `Bytes` cannot be a view.
Lowering decides by ownership, never by the op that defined the receiver (#3930): an owned temporary receiver is copied out; any other receiver, a literal's static data included, gives a borrow, and a `String` view is registered in `views` so an immutable `let` holds it without a copy. Matching `StrLit` (#3907) made a bound literal and an inline one take different paths.
Apply when: adding a native that returns part of its receiver, or a static `Bytes` in rodata (embed, #2370).
Evidence: `tests/conformance/fixtures/e2e/stdlib/bytes-scan.ms` ("view" tests), `run-string-view-of-literal` and `run-string-view-of-bound-literal` snippets; 70k views of a 64 KiB buffer took 3 ms against 94 ms for `slice`.

Embedded bytes (#2370, Chinmay 2026-11-03: store raw bytes, not base64): MIR `bytes` yields a borrowed `Bytes` over `Module.blobs` placed in rodata (`cap == 0`, like a view). Generated `[embed]` modules call `msstd_embed_bytes("<base64>")` inside `fn load(index)`; lowering decodes the literal at compile time (`native.rs`, hand-lowered `embed/bytes`), so the argument must be a literal. `return`ing the borrowed value copies it, which is `EmbeddedTree.read`'s only cost. Do not store the value without a copy: a `Map[String, Bytes]` of statics would copy every file on each `files()` call.
Evidence: `tests/conformance/fixtures/e2e/projects/embedded_files`; a 3 MiB embedded file reads in about 6 ms total and the binary holds the bytes unencoded (valgrind clean).

`String.view_bytes()` (Chinmay, 2026-11-15: an interface view, a new String method; `as_bytes` stays the copying `Writable` contract) lends the text as a cap-zero `Bytes` (`msrt_string_view_bytes`, checker `Derived`). A text of at most `STR_INLINE_MAX` bytes may sit in a spill slot that the next temporary reuses (`slotshare`), so it is copied, as `view_of` does; a temporary receiver goes through `msrt_string_to_bytes`. Lowering therefore marks the result owned: releasing a cap-zero view is a no-op and the copies free. Pointing at the receiver's slot looked fine in `main` and failed in a `test` block under Cranelift.
Evidence: `bytes-scan.ms` ("view_bytes" tests), leak sweep clean; the URL port's `decode_component`, `encode_component`, `parse` and `parse_query` mixed loop, 20,000 rounds, went from 327.0M to 320.2M instructions (-2.1%) and 30 to 26 ms by dropping the whole-text copy.

