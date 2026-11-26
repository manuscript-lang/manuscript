[Wiki](../index.md) › [Compiler](index.md)

# Debug suffixes hid lines from the copy-forwarding pass

Verified (2026-11-23, `StringBuilder.append("x")` x 50000, `ms build --build-type Release`): `emit_copies.c` forwards `or x, 0` copies, constants and `inttoptr(ptrtoint)` casts, but every instruction ends `, !dbg !N` in a build with debug info, so none of those lines parsed and the pass did nothing. The emitted `ptrtoint`/`add`/`inttoptr` round trip then blocked LLVM's store-to-load forwarding, and the loop re-decoded a constant string each iteration. The pass now reads a line without its `, !dbg` suffix and writes it back, and rewrites an `inttoptr` of a slot address plus constants as `getelementptr i8, ptr %slot, i64 off`: 5.77M to 2.67M instructions.

Apply when: a pass over the emitted text of `emit_func.c` matches instruction shapes. Test it on a build with debug info (`ms build`), not only `ms build --emit ir `, which has none.
Verify: `opt` with `default<O3>` on the real input folds a loop over a constant slot.
