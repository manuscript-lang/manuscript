[Wiki](../index.md) › [Compiler and build](index.md)

# The LLVM backend is its own crate and needs only MIR

Decision: `ms-mir-llvm` turns MIR into LLVM IR text and depends only on `ms-mir` and `ms-rt-abi`, never on `ms-clif` (Chinmay, 2026-11-13: "llvm is a standalone backend for mir"). Machine layout (`ms_mir::layout`) and the frame analysis (`ms_mir::frames`) live in MIR because both backends use them.

Why it holds: the emitter names its own symbols and writes its own data (descriptors, vtables, globals, shared enum blocks), so no Cranelift object has to agree with it on names. The crate also writes `main` and the fault and profile tables as one more LLVM module (`tables_unit`); the shared table layout is `ms_mir::fault_tables`. `ms-build` is the driver: it runs the pinned LLVM tools and reads the objects' DWARF (`crates/ms-build/src/llvm/`). `ms-clif` is Cranelift only and knows nothing of LLVM. Naming rules for exported functions and `ms_entry` exist in both backends, because the runtime looks them up by name.

Apply when: adding a backend feature, data object or symbol; do not call into `ms-clif` from `ms-mir-llvm`.
Evidence: [crate entry](../../crates/ms-mir-llvm/src/lib.rs), [driver](../../crates/ms-mir-llvm/src/program.rs), [driver](../../crates/ms-build/src/llvm.rs).
Verify: `cargo tree -p ms-mir-llvm` lists no `ms-clif` or `cranelift`.
