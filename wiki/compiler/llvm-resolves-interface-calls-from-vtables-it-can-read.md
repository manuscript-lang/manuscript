[Wiki](../index.md) › [Compiler and build](index.md)

# LLVM resolves interface calls only from vtables it can read

Verified: release builds used to define vtables in the Cranelift object, so LLVM saw them as `external global i8` and kept every interface call indirect, even right after `iface.new` in the same function (one `Source` over a list: 4.3 ns per item through the interface, 1.8 concrete). The LLVM module now defines every vtable itself (`LlvmModule::define_vtable`; the first unit holds the definition and each other unit an `available_externally constant` copy of those it names), so the call folds to a direct call and inlines (1.8 ns; a two-stage `Source` chain 12 to 2.7 ns). Addresses and `iface.is` are unchanged.

A value LLVM cannot trace (pulled from a runtime cell, or stored in a heap box across a loop) stays indirect; keep hot interface values in locals and fields, not runtime tables.

Measured 2026-11-06: a MIR devirtualization pass (a `call.method` on a receiver from `iface.new`, `iface.borrow` or `iface.view` becomes a direct call of the thunk, and method thunks inline) made no difference in release: a local, returned or passed interface runs at the direct-loop 0.3 ns per call, and `streams` is unchanged within noise. Do not rebuild it for speed; the stream stage cost is the `Result` through memory and the holder LLVM cannot trace, not the indirect call. It could only matter for a backend that cannot resolve vtables.
See [bench/perf/iface](../../bench/perf/iface/README.md).

Apply when: changing how vtables or other data objects reach LLVM, or chasing the cost of an interface call in a release build.
Evidence: [vtable emission](../../crates/ms-mir-llvm/src/state.rs), [unit text](../../crates/ms-mir-llvm/src/llvm_ir.rs), [streams suite](../../bench/perf/streams/README.md).
Verify: `make conform`; `bench/perf/streams`.
