[Wiki](../index.md) › [Compiler and build](index.md)

# Direct LLVM records above eight leaves are memory, not leaf bags

Verified (yaml parse program, 2026-11-13): the Cranelift lowering flattens a record to scalar leaves, so `flow_value` reads the 456-byte `Flow` 92 times as 57 loads each and LLVM never sees one object. `mir_llvm/records.rs` keeps a record of at most eight leaves as register values (`rec.new`, `rec.get` and `rec.set` only move leaves around), and a larger one as a `ptr` to one immutable `alloca` of a literal struct of its leaves. A copy is one `memcpy`, a field read an offset and one aligned `load`, and `sroa` and `memcpyopt` turn that back into registers and drop unread fields.

- Offsets must be those of `layout::mem_layout` over the flat leaf list, not of nested LLVM structs: a nested struct pads to its own alignment and the flat layout does not. Use a flat literal struct and address fields with typed `getelementptr` on it.
- A block parameter that is a record in memory gets a slot of its own and each edge copies into it; a conditional edge with copies becomes its own block. A swap (an argument that is another parameter's slot) copies aside first. No phi per leaf.
- Only records whose leaves are `i64`, `f64` or `i8` are handled (a narrow integer is `i64` in registers and smaller in memory), and a record holding a `ptr` field falls back: `ptr` is an LLVM `ptr` inside a function and `i64` across a call.
- Direct functions must carry the inlining chain per instruction (`DirectEnv::at`), or fault traces and profiles lose the inlined frames.
- `depth.enter` is the first instruction of a recursive function: it compares `llvm.frameaddress` with the limit cell in the stack region and, below it, reruns the function through its grow shim (`mir_llvm/depth.rs`). It splits the entry block, so `exit_label` counts it.

Apply when: adding ops to the direct emitter, or changing how it passes records across calls.

## Native calling convention (`abi_llvm.rs`)

- A function whose every reference is a call from a directly emitted function (not the entry, an export, a vtable, closure, cleanup, capture closer or a fallback caller) is native: values over 16 bytes pass as `ptr nonnull ... dereferenceable(N)`, results over 16 bytes through `sret`, and `var` parameters still fall back. Everything else keeps the leaf signature, so no thunks exist and the fault tables are unchanged (`cg::native_functions`).
- The shim that grows the stack for a native function passes the pointers through its cells and calls the native symbol (`mir_llvm/depth.rs`); the Cranelift shim only knows leaves.
- A native function that reads memory through a parameter is never `memory(none)` (`mir_llvm/attrs.rs`).
- Not done: `ptr` leaves (a pointer is still an `i64` leaf), named struct types (the spill and `sret` types are literal structs), TBAA and range metadata.
