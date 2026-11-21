/* The symbol and line tables handed to `msrt_start` (crates/ms-rt-abi/ABI.md), shared by the backends
 * (fault_tables.rs). Code addresses are left zero: the backend relocates the entries in `pcs` and
 * the table's own pointers in `pointers`. */
#ifndef MS_MIR_TABLES_H
#define MS_MIR_TABLES_H

#include "ms/mir.h"

/* One code range of a function: a code offset and the source place it came from. */
typedef struct MirCodeRange {
    uint32_t off, file, line, scope;
} MirCodeRange;

/* What the tables record about one compiled function; the ranges are sorted by offset. */
typedef struct MirFuncTable {
    MsStr name;
    uint32_t file; /* MIR_NONE when unknown */
    uint32_t line;
    uint32_t size; /* bytes of code */
    const MirCodeRange *ranges;
    uint32_t nranges;
} MirFuncTable;

typedef struct MirTablePointer { size_t at, to; } MirTablePointer; /* offsets in the blob */

/* The address of function `func`'s code plus `off`, stored at `at` in the blob. */
typedef struct MirTablePc { size_t at, func; uint32_t off; } MirTablePc;

typedef struct MirTables {
    uint8_t *blob;
    size_t size;
    MirTablePointer pointers[5];
    MirTablePc *pcs;
    size_t npcs;
} MirTables;

/* Builds the tables of `funcs` (in order), the files of `m` and `scopes`, the module-wide list of
 * inlined-callee scopes the code generator made. Everything is in `arena`. */
void mir_fault_tables(MsArena *arena, const MirModule *m, const MirFuncTable *funcs,
                      uint32_t nfuncs, const MirScope *scopes, uint32_t nscopes, MirTables *out);

#endif
