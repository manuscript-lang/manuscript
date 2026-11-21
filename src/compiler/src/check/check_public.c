/* Public signatures name only public types (ms/public_sig.h). */
#include "ms/public_sig.h"

/* The types one walk has visited: a type is reported once per declared site. */
typedef struct PublicWalk {
    MsCheck *c;
    MsModId module;
    MsPos pos;
    MsBuf seen; /* MsTy */
} PublicWalk;

static bool public_seen(PublicWalk *w, MsTy ty) {
    for (size_t i = 0; i < MS_VEC_LEN(w->seen, MsTy); i++) {
        if (MS_VEC_AT(w->seen, MsTy, i) == ty) {
            return true;
        }
    }
    MS_VEC_PUSH(w->seen, MsTy, ty);
    return false;
}

static void public_type(PublicWalk *w, MsTy ty) {
    MsCheck *c = w->c;
    if (ty == MS_TY_NONE || public_seen(w, ty)) {
        return;
    }
    const uint32_t def = c->tys.def[ty];
    if (def != 0 && c->syms.module[def - 1] == w->module && !c->syms.is_exported[def - 1]) {
        const MsStr name = ms_name(c->names, c->tys.name[ty]);
        const MsCheckDiag diag = {.diag = {.pos = w->pos,
                                           .message = ms_arena_fmt(&c->arena,
                                                                   "public signature exposes private type %.*s; add "
                                                                   "'export' to its declaration or keep the function "
                                                                   "private",
                                                                   (int)name.len, name.ptr)},
                                  .phase = MS_PHASE_TYPE};
        ms_report(c, w->module, &diag);
    }
    const MsTy *args = ms_ty_args(&c->tys, ty);
    for (uint32_t i = 0; i < c->tys.nargs[ty]; i++) {
        public_type(w, args[i]);
    }
    const MsTyParam *params = ms_ty_params(&c->tys, ty);
    for (uint32_t i = 0; i < c->tys.nparams[ty]; i++) {
        public_type(w, params[i].ty);
    }
    public_type(w, c->tys.result[ty]);
}

/* One `check_declared` call: a fresh walk over `ty`. */
static void public_declared(MsCheck *c, MsModId module, MsPos pos, MsTy ty) {
    PublicWalk w = {.c = c, .module = module, .pos = pos};
    public_type(&w, ty);
    ms_buf_free(&w.seen);
}

/* The bounds and the default of one type variable. */
static void public_variable(MsCheck *c, MsModId module, MsPos pos, MsTy variable, bool bounds) {
    const MsVarInfo *info = ms_var_info(c, variable);
    for (uint32_t i = 0; bounds && i < info->nbounds; i++) {
        public_declared(c, module, pos, info->bounds[i]);
    }
    if (info->def != MS_TY_NONE) {
        public_declared(c, module, pos, info->def);
    }
}

static void public_nominal(MsCheck *c, MsModId module, const MsDecl *d, MsSymId sym, const MsMethodTable *table) {
    const MsDef *def = ms_def(c, sym);
    for (uint32_t i = 0; i < def->nfields; i++) {
        public_declared(c, module, d->pos, def->fields[i].ty);
    }
    for (uint32_t i = 0; i < def->ncases; i++) {
        for (uint32_t k = 0; k < def->cases[i].nfields; k++) {
            public_declared(c, module, d->pos, def->cases[i].fields[k].ty);
        }
    }
    const MsOperations *operations = table == NULL ? NULL : ms_interface_operations(table, sym);
    for (uint32_t i = 0; operations != NULL && i < operations->count; i++) {
        public_declared(c, module, d->pos, operations->items[i].ty);
        for (uint32_t k = 0; k < operations->items[i].nvars; k++) {
            public_variable(c, module, d->pos, operations->items[i].vars[k], true);
        }
    }
}

void ms_module_check_public(MsCheck *c, MsModId module, const MsMethodTable *table) {
    const MsModule *syntax = c->mods[module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind == MS_D_TEST || d->kind == MS_D_IMPL) {
            continue;
        }
        const MsSymId sym = ms_decl_own_symbol(c, module, d);
        if (sym == MS_NONE || !c->syms.is_exported[sym]) {
            continue;
        }
        if (c->syms.kind[sym] == MS_SYM_FN || c->syms.kind[sym] == MS_SYM_ALIAS) {
            public_declared(c, module, d->pos, c->syms.ty[sym]);
        } else {
            public_nominal(c, module, d, sym, table);
        }
        uint32_t nvars = 0;
        const MsTy *vars = ms_sym_vars(c, sym, &nvars);
        for (uint32_t k = 0; k < nvars; k++) {
            public_variable(c, module, d->pos, vars[k], true);
        }
    }
}
