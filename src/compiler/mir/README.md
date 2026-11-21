# src/compiler/mir

MIR: the typed mid-level IR that lowering builds and the optimizer, emitter and linker consume. Passes
exchange a `MirModule` in memory; there is no text between them. Allowed includes: see `src/layers.txt`.

- `mir.h`: types, operations, functions, module declarations.
- `mir_types.c`: the interned type table (packed keys in an `MsNames`) and the opcode table.
- `mir_module.c`: module construction, declarations, name lookup, release.
- `mir_builder.h`, `mir_builder.c`: builds a function; source variables become block parameters (Braun et al.).
- `mir_layout.h`, `mir_boxing.c`, `mir_shape.c`, `mir_layout.c`: boxing of recursive types and the machine layout (leaves, alternative slots, closures, flags).
- `mir_analysis.h`, `mir_analysis.c`, `mir_edit.c`: ownership modes, terminator walks, predecessors, reverse post-order, dominators, bit sets, value ranges; editing helpers (insert, remove, clone, compact).
