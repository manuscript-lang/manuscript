/* User enums in the lowering: an `enum` without type parameters whose cases carry scalars is a MIR
 * alternative with one case per declared case, in order. `Case(args)` is `alt.new` (lower_alt.c)
 * and a `match` over it branches on `alt.tag` (lower_body.c). A case that owns something (a
 * String, a list) waits for the ownership side, like the payloads of Optional and Result. */
#include "ms/lower_internal.h"

/* The MIR type of enum `ty`, declared on first use; MIR_NONE when it is not one this pass lowers. */
MirTy le_type(Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    if (ms_ty_kind(tys, ty) != MS_K_ALTERNATIVE || tys->nargs[ty] != 0 || tys->def[ty] == 0 || tys->builtin[ty] != 0) {
        return MIR_NONE;
    }
    const MsSymId sym = tys->def[ty] - 1;
    if (sym >= lb->c->defs_cap || lb->c->syms.kind[sym] != MS_SYM_TYPE || lb->c->defs[sym].ncases == 0) {
        return MIR_NONE;
    }
    if (lb->type_of[ty] == LB_TYPE_PENDING) {
        return MIR_NONE; // an enum reaching itself through a list is not lowered
    }
    if (lb->type_of[ty] != MIR_NONE) {
        return lb->type_of[ty];
    }
    lb->type_of[ty] = LB_TYPE_PENDING;
    const MsDef *def = &lb->c->defs[sym];
    MirCaseDef *cases = MS_NEW_N(&lb->m->arena, MirCaseDef, def->ncases);
    for (uint32_t i = 0; i < def->ncases; i++) {
        const MsCaseRow *row = &def->cases[i];
        MirField *fields = MS_NEW_N(&lb->m->arena, MirField, (size_t)row->nfields + 1);
        for (uint32_t slot = 0; slot < row->nfields; slot++) {
            const MirTy payload = lb_mir_ty(lb, row->fields[slot].ty);
            if (payload == MIR_NONE || mir_needs_drop(lb->m, payload)) {
                lb->type_of[ty] = MIR_NONE;
                return MIR_NONE;
            }
            const MsStr field = ms_name(lb->c->names, row->fields[slot].name);
            fields[slot] = (MirField){mir_name(lb->m, field.ptr, field.len), payload};
        }
        const MsStr name = ms_name(lb->c->names, row->name);
        cases[i] = (MirCaseDef){mir_name(lb->m, name.ptr, name.len), fields, row->nfields};
    }
    MsBuf text = {0};
    ms_ty_show(&text, lb->c->names, tys, ty);
    const uint32_t id = mir_add_alt(lb->m, mir_name(lb->m, text.data, text.len));
    ms_buf_free(&text);
    lb->m->alts[id].cases = cases;
    lb->m->alts[id].ncases = def->ncases;
    lb->type_of[ty] = mir_ty_alt(lb->m, id);
    return lb->type_of[ty];
}
