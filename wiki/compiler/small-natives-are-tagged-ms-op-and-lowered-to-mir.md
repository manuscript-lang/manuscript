[Wiki](../index.md) › [Compiler and build](index.md)

# Small natives are tagged `ms-op` and lowered to MIR, not called

Verified: the runtime is a prebuilt archive linked without LTO, so a call to a one-instruction native (`msrt_float32_abs`, `msrt_int32_compare`, `msrt_list_length`) stays a real call. A native whose job is a few machine instructions is instead written out by lowering. Chinmay's rule (2026-11-23): move simple things into MIR and keep the runtime for heavy ones; the tag says only what LLVM should see, no Rust types.

How it works:
- Tag the C declaration with `/* ms-op: msrt_float32_abs fabs */` in the runtime header. `cmake/EmbedNativeSigs.cmake` turns these lines into `ms_native_ops` (`ms_native_op_find`). The operation names are the keys of `fn_inline_scalar_op` in `src/compiler/lower/lower_scalar_ops.c`.
- `native_on` (`x.abs()`, bodiless standard operations) and `call_runtime` (`extern fn`, such as `math.sqrt`) both ask for the tag before they call. An operation emits MIR (`fabs`, `inarrow.opt`, `icmp`, `i2f`, `list.len`) and returns false, emitting nothing, when the operand types are not what it expects; the native is then called, so the C function must stay while a tag points at it.
- Keep an `ms-sig:` line only when the native needs it for something else: out-parameters (range conversions), descriptors, a domain for failures, or passing a list or string by address (`list_length`). A pure scalar native has just its `ms-op` line.
- Faults keep their text and location: `Int.abs` of the lowest value is `ineg.chk` (integer overflow), a sized `abs` is `narrow.chk` (out of range).

Apply when: adding a small runtime native, or seeing a tiny `msrt_` call in a hot loop's MIR (`ms emit file.ms`).
Verify: `ms emit` shows the MIR op and no `call.rt`; compare edge cases (NaN, -0.0, the lowest values, range edges) before and after; `make conform` has no new failures. Evidence: [`lower_scalar_ops.c`](../../src/compiler/lower/lower_scalar_ops.c). Measured on the kernels: `mandel_400` 17.5 to 11.3 ms, `vm_5M` 155 to 133 ms.
