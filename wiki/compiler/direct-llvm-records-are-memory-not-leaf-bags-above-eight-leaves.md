[Wiki](../index.md) › [Compiler and build](index.md)

# Direct LLVM records above eight leaves are memory, not leaf bags

Verified (yaml parse program, 2026-11-13): the Cranelift lowering flattens a record to scalar leaves, so `flow_value` reads the 456-byte `Flow` 92 times as 57 loads each and LLVM never sees one object. `mir_llvm/records.rs` keeps a record of at most eight leaves as register values (`rec.new`, `rec.get` and `rec.set` only move leaves around), and a larger one as a `ptr` to one immutable `alloca` of a literal struct of its leaves. A copy is one `memcpy`, a field read an offset and one aligned `load`, and `sroa` and `memcpyopt` turn that back into registers and drop unread fields.

- Offsets must be those of `layout::mem_layout` over the flat leaf list, not of nested LLVM structs: a nested struct pads to its own alignment and the flat layout does not. Use a flat literal struct and byte offsets.
- A block parameter that is a record in memory gets a slot of its own and each edge copies into it; a conditional edge with copies becomes its own block. A swap (an argument that is another parameter's slot) copies aside first. No phi per leaf.
- Only records whose leaves are `i64`, `f64` or `i8` are handled (a narrow integer is `i64` in registers and smaller in memory), and a record holding a `ptr` field falls back: `ptr` is an LLVM `ptr` inside a function and `i64` across a call.
- Direct functions must carry the inlining chain per instruction (`DirectEnv::at`), or fault traces and profiles lose the inlined frames.

Apply when: adding ops to the direct emitter, or changing how it passes records across calls.
