[Wiki](../index.md) › [Compiler and build](index.md)

# Values above eight leaves live in memory cells, not leaf bags

Verified (yaml parse program, 2026-11-13; kept in the C emitter): a record flattened to scalar leaves was read 92 times as 57 loads each, so LLVM never saw one object, and a 66-leaf record copied 125 times made 8000 stores and 21 s of LLVM time. `compiler/emit/emit_wide.c` keeps a value of more than `wide_leaves` leaves (8 in Release, 4 in Debug; `MS_WIDE_LEAVES` overrides, 0 means never; `src/cli/pipeline.c`) in a stack cell written where it is made. Each instruction that reads it loads just the leaves it names. A copy is one `memcpy`, and Release leaves the cells to `sroa` and `memcpyopt`; Debug hides them so frames stay small.

- A block parameter held in a cell has a cell of its own and no phi: each edge copies the argument's cell into it. Cells that are never live together share storage (`emit_slot_pool`).
- A function called only from MIR functions takes a value over 16 bytes as `ptr nonnull readonly nocapture dereferenceable(N)` and returns one through `sret` (`emit_func.c`); entries, exports, vtables and closures keep the leaf signature.
- Narrow integers and `Float32` are held as their real LLVM types and widened only across the leaf convention; checked arithmetic uses `llvm.*.with.overflow` and splits the block (`emit_checked.c`), so an area that counts blocks must count every split.
- A recursive function checks the stack with `llvm.frameaddress` against the limit cell and reruns itself on a grown stack when below it (`emit_call.c`, `emit_checked.c`).
- Terminology: the compiler says "type" for a `type Name { ... }` declaration. `record` survives only for unrelated things (fault records, zip and DNS records). Tooling output (`ms map --view inspect`, `ms diff`, docgen, selectors like `file#type#Name`) also says `"type"`; aliases are `"alias"`. Do not add new uses of "record" for user types.

Sized integers in MIR (Chinmay, 2026-11-13): `iadd.chk`, `isub.chk`, `imul.chk`, `ineg.chk` and `sdiv.chk` on `Int8` to `UInt32` fault when the result leaves the type's range, so no separate range op follows; `narrow.chk` is `Int` to a sized integer. The constant folder, verifier and emitter apply the same rule.

Apply when: adding ops to the emitter, or changing how it passes large values across calls.
Evidence: [wide values proposal](../../proposals/wide-values-in-memory.md), `src/compiler/emit/README.md`.
Verify: `MS_WIDE_LEAVES=0` and the default give the same output on the conformance corpus.
