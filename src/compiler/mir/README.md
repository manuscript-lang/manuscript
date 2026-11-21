# src/compiler/mir

MIR: the typed mid-level IR that lowering builds and the optimizer, emitter and linker consume. Passes
exchange a `MirModule` in memory; there is no text between them. Allowed includes: see `src/layers.txt`.

- `mir.h`: types, operations, functions, module declarations.
- `mir_types.c`: the interned type table (packed keys in an `MsNames`) and the opcode table.
- `mir_module.c`: module construction, declarations, name lookup, release.
- `mir_builder.h`, `mir_builder.c`: builds a function; source variables become block parameters (Braun et al.).
- `mir_layout.h`, `mir_boxing.c`, `mir_shape.c`, `mir_layout.c`: boxing of recursive types and the machine layout (leaves, alternative slots, closures, flags).
- `mir_analysis.h`, `mir_analysis.c`, `mir_edit.c`: ownership modes, terminator walks, predecessors, reverse post-order, dominators, bit sets, value ranges; editing helpers (insert, remove, clone, compact).
- `mir_pass.h`, `mir_pass.c`: helpers shared by passes (extern declaration, plain memory, constructors, cancellation points). `mir_frames.c`, `mir_slot_scope.c`: framed values and block-confined stack slots, read by the emitter.
- `mir_desc.h`, `mir_desc.c`: how a type's descriptor is made (kind, size, inner types, slot glue, equality and hash).
- `mir_glue.h`, `mir_glue*.c`: the pass that makes drop, clone, slot, block and closure functions. `mir_glue_demand.c` finds what the module needs; `mir_glue_drop.c`, `mir_glue_alt.c`, `mir_glue_clone.c`, `mir_glue_alt_clone.c`, `mir_glue_closure.c`, `mir_glue_deep.c` build them; `mir_glue_build.c` holds the table and emit helpers.
- `mir_data.h`, `mir_data.c`, `mir_data_const.c`: the static data (descriptors, vtables, globals, unit blocks, long string literals, constant bytes and lists) as symbols with relocations; built after glue.
