# src/compiler/mir

MIR: the typed mid-level IR that lowering builds and the optimizer, emitter and linker consume. Passes
exchange a `MirModule` in memory; there is no text between them. Allowed includes: see `src/layers.txt`.

- `mir.h`: types, operations, functions, module declarations.
- `mir_types.c`: the interned type table (packed keys in an `MsNames`) and the opcode table.
- `mir_module.c`: module construction, declarations, name lookup, release.
