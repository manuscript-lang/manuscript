[Wiki](../index.md) › [Compiler and build](index.md)

# Direct LLVM records above eight leaves are memory, not leaf bags

Verified (yaml parse program, 2026-11-13): the Cranelift lowering flattens a record to scalar leaves, so `flow_value` reads the 456-byte `Flow` 92 times as 57 loads each and LLVM never sees one object. `mir_llvm/types.rs` keeps a record of at most eight leaves as register values (`type.new`, `type.get` and `type.set` only move leaves around), and a larger one as a `ptr` to one immutable `alloca` of a literal struct of its leaves. A copy is one `memcpy`, a field read an offset and one aligned `load`, and `sroa` and `memcpyopt` turn that back into registers and drop unread fields.

- A user type is an LLVM named struct with one field per source field (a scalar, or the field type's own struct), reached by field-index path (`FnBuilder::leaf_ptr`, `mir_llvm::field_types`), never by byte offsets. Its byte layout must still equal `layout::mem_layout` over the flat leaf list, because the runtime and the Cranelift object use that; a nested struct pads its tail to its own alignment, so `field_types` returns `None` and the type keeps one field per leaf when any offset would move.
- Terminology: the whole compiler says "type" for a `type Name:` declaration (`TypeId`, `TyKind::Type`, `type.new`, `DeclKind::Type`, `Kind::Type`, `abi_type!`, `TypeList`). `record` survives only for unrelated things (fault records, zip and DNS records, "recorded"). Tooling output (`ms inspect`, `ms diff`, docgen, selectors like `file#type#Name`) also says `"type"`; aliases are `"alias"`. Do not add new uses of "record" or "rec" for user types.
- A block parameter that is a record in memory gets a slot of its own and each edge copies into it; a conditional edge with copies becomes its own block. A swap (an argument that is another parameter's slot) copies aside first. No phi per leaf.
- Only records whose leaves are `i64`, `f64`, `i8` or a narrow integer are handled.
- Direct functions must carry the inlining chain per instruction (`DirectEnv::at`), or fault traces and profiles lose the inlined frames.
- `depth.enter` is the first instruction of a recursive function: it compares `llvm.frameaddress` with the limit cell in the stack region and, below it, reruns the function through its grow shim (`mir_llvm/depth.rs`). It splits the entry block, so `exit_label` counts it.

Apply when: adding ops to the direct emitter, or changing how it passes records across calls.

## Native calling convention (`abi_llvm.rs`)

- A function whose every reference is a call from a directly emitted function (not the entry, an export, a vtable, closure, cleanup, capture closer or a fallback caller) is native: values over 16 bytes pass as `ptr nonnull ... dereferenceable(N)`, results over 16 bytes through `sret`, and `var` parameters still fall back. Everything else keeps the leaf signature, so no thunks exist and the fault tables are unchanged (`cg::native_functions`).
- The shim that grows the stack for a native function passes the pointers through its cells and calls the native symbol (`mir_llvm/depth.rs`); the Cranelift shim only knows leaves.
- A native function that reads memory through a parameter is never `memory(none)` (`mir_llvm/attrs.rs`).
- Held values inside a function: pointer leaves are `ptr` and booleans `i1` (`Layouts::pointer_leaves`, `bool_leaves`; `mod.rs::held_leaves`). Across the leaf convention a pointer is `i64` and a bool `i8`; in memory a bool is a byte (`mem_leaves`). Convert at the edge (`types::abi_leaves`, `load_into`, `store_leaf`), never in the middle.
- Strings, bytes, lists and records are named struct types in one `Types` per module (`aggregate`); their bodies must be written before the first function that uses them, or `llvm-link` rejects a `getelementptr` as unsized.
- Checked arithmetic (`iadd.chk` and friends, `sdiv.chk`, `srem.chk`) uses `llvm.*.with.overflow` and `faults::fault_if`, which splits the block (`Area::splits` must count every split). The result takes its reserved name on the last instruction, after the checks. A function that ends in `fault` or contains a checked op is never `memory(none)`.
- Narrow integers (`Int8` to `UInt32`) are held as the real `i8`/`i16`/`i32` (`held_leaves`) and stored in their own width, so loads and stores convert nothing. Across calls (the leaf convention shared with Cranelift) `to_abi` extends them to `i64` by signedness (`narrow_leaves`) and the entry or `name_leaves` truncates; an enum payload slot is an `i64` (`enums::convert`). Checked ops use `llvm.{s,u}{add,sub,mul}.with.overflow.iN`; unsigned types use `udiv`, `urem` and unsigned `icmp`.
- `Float32` is a real `float` the same way: `float` ops and `llvm.*.f32` intrinsics, 4 bytes in memory, widened to `double` across calls and in enum slots, `f32.round` and same-width `conv` are the register itself, `i2f` to `Float32` is one `sitofp ... to float`. A constant list's bytes come from `Leaf::const_bytes`, shared with Cranelift.

## Closures, interfaces and runtime calls (`mir_llvm/closures.rs`, `calls.rs`)

- A closure object is `%ms.env.<code> = { %ms.closure, capture.. }`: the clone, drop and code header, then each capture as its own memory struct, so a capture starts at its own largest alignment like `cg::CLOSURE_CAPTURES` says. Flattening all captures into one struct would misplace a `Bool` followed by an optional.
- The code of a closure and the methods of a vtable are emitted directly but keep the leaf signature (the runtime and translated code call them by address); they may call native functions.
- `cg::direct_plan` makes the glue and vtable symbols before emission, since only the generator can declare glue. It also decides which closures and borrowed interface boxes live in the frame; the analyses are shared with the Cranelift lowering (`lower::framed_closure_objects`, `framed_iface_borrows`).
- A runtime call passes leaves where the value passes directly and the address of a copy otherwise, with a hidden last result pointer. C shims, `MapNew`, `CleanupDiscard` and `var` parameters fall back. A runtime function's `declare` is first-wins across the unit: a call whose types differ from it (`ptr` against `i64`) is legal IR and the same ABI.
- An area's `emit` also runs for ops its `pre` answered; it must do nothing for them. An interface's two words are `i64` leaves, so `iface.data` is an `inttoptr`.
- A hand-written MIR test must satisfy the verifier: every owned value is dropped or returned.

## Indirect records (`Error`)

- An indirect record is one `ptr` to a heap block named `ms.type.<Name>.block`: its fields' leaves in order, with a map or set field as one nullable `ptr` to a seven-word header (null is the empty value, exactly as `Layouts::type_block` and the Cranelift path write it; both paths share live `Error` values, so the layout must not drift). Field reads are typed GEPs plus loads (`records.rs`).
- Branching inside an instruction (a null header) needs `Area.splits`, which now sees the instruction: `TypeNew` splits once per boxed field, a boxed `TypeGet` and `PtrField` once.
- Done: type, `TypeNew`, `TypeGet`, `PtrField`. `TypeSet`, `TypeFill` and `TypeRelease` still fall back: they need the glue area's `drop_value` for the old fields. `TypeNew` and the boxed paths are checked only by reading and by `opt` verify on a hacked build; they cannot run end to end until the maps area and the optionals area (an `Error` is built with `kind: String?` and a `Map`) land, so rerun the `Error` programs under `MS_LLVM_DIRECT=0/1` when they do.

## Sized integers in MIR

- Decision (Chinmay, 2026-11-13): MIR represents a sized integer sum directly. `iadd.chk`, `isub.chk`, `imul.chk`, `ineg.chk` and `sdiv.chk` on `Int8` to `UInt32` operands fault when the result leaves the type's range (`msrt_fault_int_range`), so no separate range op follows. `narrow.chk` is now `Int` to a sized integer (used by `abs`). The interpreter, verifier, Cranelift (`range_check_sized`), the constant folder (`Ty::sized_range`) and the direct emitter apply the same rule.
