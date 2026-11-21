/* The fault tables of a module whose functions each have one code range per instruction, 4 bytes
 * apart, for the tests of the pass and emitter tools. */
#ifndef MS_TOOLS_SYNTHETIC_TABLES_H
#define MS_TOOLS_SYNTHETIC_TABLES_H

#include <string.h>

#include "ms/mir_tables.h"

static void synthetic_tables(MsArena *arena, const MirModule *m, MirTables *t) {
    MirFuncTable *funcs = MS_NEW_N(arena, MirFuncTable, m->nfuncs ? m->nfuncs : 1);
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        MirCodeRange *ranges = MS_NEW_N(arena, MirCodeRange, 1);
        uint32_t n = 0, cap = 0, off = 0;
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t k = 0; k < f->blocks[bi].ninsts; k++, off += 4) {
                const MirLoc l = f->blocks[bi].insts[k].loc;
                if (n == cap) {
                    MirCodeRange *grown = MS_NEW_N(arena, MirCodeRange, cap = cap ? cap * 2 : 8);
                    memcpy(grown, ranges, sizeof *ranges * n);
                    ranges = grown;
                }
                ranges[n++] = (MirCodeRange){off, l.file, l.line, l.scope};
            }
        }
        funcs[fi] = (MirFuncTable){ms_name(&m->names, f->name), f->loc.file, f->loc.line, off + 1,
                                   ranges, n};
    }
    uint32_t nscopes = 0;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        nscopes += m->funcs[fi].nscopes;
    }
    MirScope *scopes = MS_NEW_N(arena, MirScope, nscopes ? nscopes : 1);
    for (uint32_t fi = 0, at = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        for (uint32_t k = 0; k < f->nscopes; k++) {
            scopes[at++] = f->scopes[k];
        }
    }
    mir_fault_tables(arena, m, funcs, m->nfuncs, scopes, nscopes, t);
}

#endif
