[Wiki](../index.md) › [Compiler and build](index.md)

# LLVM resolves interface calls only from vtables it can read

Verified: release builds define vtables in the Cranelift object, so LLVM used to see them as `external global i8` and kept every interface call indirect, even right after `iface.new` in the same function (one `Source` over a list: 4.3 ns per item through the interface, 1.8 concrete). Each unit now gets an `available_externally constant` copy of every vtable it names (`LlvmModule::set_vtable`), so the call folds to a direct call and inlines (1.8 ns; a two-stage `Source` chain 12 to 2.7 ns). The Cranelift object still owns the symbol, so addresses and `iface.is` are unchanged.

A value LLVM cannot trace (pulled from a runtime cell, or stored in a heap box across a loop) stays indirect; keep hot interface values in locals and fields, not runtime tables.

Apply when: changing how vtables or other data objects reach LLVM, or chasing the cost of an interface call in a release build.
Evidence: [vtable emission](../../crates/ms-clif/src/cg.rs), [unit text](../../crates/ms-clif/src/llvm_ir.rs), [streams suite](../../bench/perf/streams/README.md).
Verify: `make e2e`; `bench/perf/streams`.
