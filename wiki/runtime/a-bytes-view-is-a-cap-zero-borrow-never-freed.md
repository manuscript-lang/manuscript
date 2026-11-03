[Wiki](../index.md) › [Runtime](index.md)

# A Bytes view is a cap-zero borrow that is never freed

Decision (Chinmay, 2026-11-03): O(1) slicing of `Bytes` must fit the one-owner model, so `Bytes.view(start, end)` lends the receiver (like `List.get`) instead of sharing storage with a refcount. `slice` stays a copying `Result`.
Verified: a `Bytes` with `cap == 0` and `len > 0` is a non-owning view (`msrt_bytes_view`); `msrt_bytes_drop` skips it, `clone` copies it. The checker lists `Bytes.view` in `native_lend_receiver`, so storing a view or changing the source while it lives is rejected. Lowering writes the header to a slot and `load`s it, so MIR sees a borrow; a temporary receiver is copied out instead. A native `call.rt` result of type `Bytes` is owned by default, which is why a returned `Bytes` cannot be a view.
Apply when: adding a native that returns part of its receiver, or a static `Bytes` in rodata (embed, #2370).
Evidence: `tests/e2e/testdata/stdlib/bytes-scan.ms` ("view" tests); 70k views of a 64 KiB buffer took 3 ms against 94 ms for `slice`.
