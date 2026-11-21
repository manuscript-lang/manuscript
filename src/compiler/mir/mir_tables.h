/* compiler/mir/mir_tables.h: the symbol and line tables handed to `msrt_start` (the runtime's MsTables,
 * runtime/core/frames.h), shared by the back ends. Code addresses are left zero: the back end relocates the
 * entries in `pcs` and the table's own pointers in `pointers`.
 *
 * Ownership: the blob and the relocation array live in the arena the caller passes. */
#ifndef MS_COMPILER_MIR_MIR_TABLES_H
#define MS_COMPILER_MIR_MIR_TABLES_H

#include "compiler/mir/mir.h"

/* One code range of a function: a code offset and the source place it came from. */
typedef struct MirCodeRange {
  uint32_t off, file, line, scope;
} MirCodeRange;

/* What the back end recorded about one compiled function; the ranges are sorted by offset. */
typedef struct MirFuncTable {
  MsSpan name;
  uint32_t file; /* MIR_NONE when unknown */
  uint32_t line;
  uint32_t size; /* bytes of code */
  const MirCodeRange *ranges;
  uint32_t nranges;
} MirFuncTable;

/* The table's own address at `to` is stored at `at` (both offsets in the blob). */
typedef struct MirTablePointer {
  size_t at, to;
} MirTablePointer;

/* The address of function `func`'s code plus `off`, stored at `at` in the blob. */
typedef struct MirTablePc {
  size_t at, func;
  uint32_t off;
} MirTablePc;

#define MIR_TABLE_POINTERS 5

typedef struct MirTables {
  uint8_t *blob;
  size_t size;
  MirTablePointer pointers[MIR_TABLE_POINTERS];
  MirTablePc *pcs;
  size_t npcs;
} MirTables;

/* Builds the tables of `funcs` (in order), the files of `module` and `scopes`, the module-wide list of
 * inlined-callee scopes the code generator made. Everything is in `arena`. */
void mir_fault_tables(MsArena *arena, const MirModule *module, const MirFuncTable *funcs, uint32_t nfuncs,
                      const MirScope *scopes, uint32_t nscopes, MirTables *out);

#endif
