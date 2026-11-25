[Wiki](../index.md) › [Compiler and build](index.md)

# The Debug back end is Cranelift behind a shared library, one object for the whole program

Decision (Chinmay, 2026-11-25): Cranelift is built by `manuscript-lang/cranelift-bundle` as a shared library with a C shim, fetched and loaded by path like libLLVM; no Cranelift patch lives in this repo and every MIR op must lower to it. `compiler/emit_cl` mirrors `compiler/emit` file for file; a rule decided in MIR is not decided again there.

Verified (2026-11-25): a YAML parse and print program builds in Debug in 0.50 s wall and 0.64 s CPU instead of 1.33 s and 3.3 s, and the e2e fixtures run with the same output. Pitfalls that cost time: Cranelift's unsigned 64-bit to `f32` conversion panics on x64 (the emitter halves with a sticky bit instead); a Float32 returned by an `msrt_*` function is already a double; `Decimal` hashes by address in `msstd_value_hash`, so a test passes under LLVM only because two stack copies share a cell.

Apply when: changing `src/compiler/emit_cl`, the bundle's C API, or anything that decides how Debug objects are written.
Evidence: [proposal](../../proposals/cranelift-debug-backend.md), `src/compiler/emit_cl/`.
Verify: `MS_CRANELIFT=<libms_cranelift> ms test <fixture>` prints no `falling back to LLVM` and matches the LLVM output.
