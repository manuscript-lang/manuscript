/* Substitution of type variables, the `sub` of crates/ms-check/src/types.rs over the interned type
 * table. */
#include <string.h>

#include "ms/types.h"

/* The type bound to `ty`'s id, or MS_TY_NONE. */
static MsTy bound_type(const MsTyTable *t, MsTy ty, const MsTySubst *subst) {
    for (uint32_t i = 0; i < subst->count; i++) {
        if (t->id[subst->vars[i]] == t->id[ty]) {
            return subst->args[i];
        }
    }
    return MS_TY_NONE;
}

MsTy ms_ty_subst(MsTyTable *t, MsArena *scratch, MsTy ty, const MsTySubst *subst) {
    MsTy bound = bound_type(t, ty, subst);
    if (bound != MS_TY_NONE) {
        return bound;
    }
    const uint32_t nargs = t->nargs[ty];
    const uint32_t nparams = t->nparams[ty];
    if (ms_ty_kind(t, ty) == MS_K_VARIABLE || (nargs == 0 && nparams == 0 && t->result[ty] == MS_TY_NONE)) {
        return ty;
    }
    MsTy *args = MS_NEW_N(scratch, MsTy, (size_t)nargs + 1);
    MsTyParam *params = MS_NEW_N(scratch, MsTyParam, (size_t)nparams + 1);
    bool changed = false;
    for (uint32_t i = 0; i < nargs; i++) {
        args[i] = ms_ty_subst(t, scratch, t->args_pool[t->args_at[ty] + i], subst);
        changed = changed || args[i] != t->args_pool[t->args_at[ty] + i];
    }
    for (uint32_t i = 0; i < nparams; i++) {
        params[i] = t->params_pool[t->params_at[ty] + i];
        params[i].ty = ms_ty_subst(t, scratch, params[i].ty, subst);
        changed = changed || params[i].ty != t->params_pool[t->params_at[ty] + i].ty;
    }
    MsTy result = t->result[ty] == MS_TY_NONE ? MS_TY_NONE : ms_ty_subst(t, scratch, t->result[ty], subst);
    if (!changed && result == t->result[ty]) {
        return ty;
    }
    MsTyDesc desc = {t->name[ty], t->id[ty], ms_ty_kind(t, ty), ms_ty_builtin(t, ty), t->def[ty], args, nargs,
                     params, nparams, result};
    return ms_ty_intern(t, &desc);
}
