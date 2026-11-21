/* The syntax node behind each method row: impl rows are appended in declaration order, one per
 * written method (and a few after an impl for properties it leaves to its interface), so one pass
 * over the module's impls with a cursor over the rows pairs them. `owners`, when given, receives
 * the impl each row's method is written in (both arrays hold `m->count + 1` entries). */
#include <string.h>

#include "ms/methods.h"

const MsMethod **ms_method_rows(MsCheck *c, MsModId module, const MsMethods *m, const MsDecl **owners) {
    const MsMethod **rows = MS_NEW_N(&c->arena, const MsMethod *, (size_t)m->count + 1);
    for (uint32_t i = 0; i <= m->count; i++) {
        rows[i] = NULL;
        if (owners != NULL) {
            owners[i] = NULL;
        }
    }
    const MsModule *syntax = c->mods[module].syntax;
    uint32_t cursor = 0;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind != MS_D_IMPL) {
            continue;
        }
        for (uint32_t k = 0; k < d->u.impl.methods.len; k++) {
            const MsMethod *method = d->u.impl.methods.ptr[k];
            uint32_t at = cursor;
            while (at < m->count && m->decl[at] != &method->func) {
                at++;
            }
            if (at < m->count) {
                rows[at] = method;
                if (owners != NULL) {
                    owners[at] = d;
                }
                cursor = at + 1;
            }
        }
    }
    return rows;
}
