/* The top-level types of a module: the declaration passes of `check_module` up to the signatures
 * (declare_type_variables, resolve_declaration_defaults, resolve_declaration_bounds,
 * resolve_aliases, resolve_signatures of crates/ms-check/src/checker.rs). */
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/facts.h"

/* ---- declarations ---- */

static bool decl_has_symbol(const MsDecl *d) {
    return d->kind != MS_D_IMPL && d->kind != MS_D_TEST;
}

/* The symbol `d` declared in the module, unless a duplicate name took its place. */
MsSymId ms_decl_own_symbol(const MsCheck *c, MsModId module, const MsDecl *d) {
    const MsSymId sym = ms_map_get(&c->mods[module].names, ms_decl_name(d));
    return sym != MS_NONE && c->syms.decl[sym] == d ? sym : MS_NONE;
}

static const MsTypeParams *decl_params(const MsDecl *d) {
    static const MsTypeParams none = {0};
    switch ((MsDeclKind)d->kind) {
    case MS_D_FN: return &d->u.fn.type_params;
    case MS_D_TYPE: return &d->u.type.type_params;
    case MS_D_ENUM: return &d->u.enumeration.type_params;
    case MS_D_ALIAS: return &d->u.alias.type_params;
    case MS_D_INTERFACE: return &d->u.iface.type_params;
    case MS_D_CONST:
    case MS_D_IMPL:
    case MS_D_TEST: return &none;
    }
    return &none;
}

/* ---- the nominal type of a declaration ---- */

static MsKind nominal_decl_kind(const MsDecl *d) {
    if (d->kind == MS_D_ENUM) {
        return MS_K_ALTERNATIVE;
    }
    if (d->kind == MS_D_INTERFACE) {
        return MS_K_CONTRACT;
    }
    return d->kind == MS_D_TYPE && d->u.type.external ? MS_K_NATIVE : MS_K_TYPE;
}

static MsSym module_type_id(MsCheck *c, MsModId module, MsSym name) {
    const MsStr path = ms_name(c->names, c->mods[module].path);
    const MsStr text = ms_name(c->names, name);
    MsStr hex = ms_arena_fmt(&c->arena, "module/");
    for (uint32_t i = 0; i < path.len; i++) {
        hex = ms_arena_fmt(&c->arena, "%.*s%02x", (int)hex.len, hex.ptr, (unsigned char)path.ptr[i]);
    }
    hex = ms_arena_fmt(&c->arena, "%.*s#%.*s", (int)hex.len, hex.ptr, (int)text.len, text.ptr);
    return ms_intern(c->names, hex.ptr, hex.len);
}

/* The type of a `type`, `enum` or `interface` carrying its variables as arguments. A bundled
 * module's exported types already have one, without arguments. */
static void declare_nominal_type(MsCheck *c, MsModId module, MsSymId sym, const MsTy *vars, uint32_t nvars) {
    MsTyDesc desc = {0};
    if (c->syms.ty[sym] != MS_TY_NONE) {
        const MsTy old = c->syms.ty[sym];
        desc = (MsTyDesc){.name = c->tys.name[old],
                          .id = c->tys.id[old],
                          .kind = (MsKind)c->tys.kind[old],
                          .builtin = (MsBuiltin)c->tys.builtin[old],
                          .def = c->tys.def[old]};
    } else {
        desc = (MsTyDesc){.name = c->syms.name[sym],
                          .id = module_type_id(c, module, c->syms.name[sym]),
                          .kind = nominal_decl_kind(c->syms.decl[sym]),
                          .def = sym + 1};
    }
    desc.args = vars;
    desc.nargs = nvars;
    c->syms.ty[sym] = ms_ty_intern(&c->tys, &desc);
}

static void declare_type_variables(MsResolver *r) {
    MsCheck *c = r->c;
    const MsModule *syntax = c->mods[r->module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        const MsSymId sym = decl_has_symbol(d) ? ms_decl_own_symbol(c, r->module, d) : MS_NONE;
        if (sym == MS_NONE) {
            continue;
        }
        const MsTypeParams *params = decl_params(d);
        MsTy *vars = ms_declare_type_variables(r, sym, params);
        MsDef *def = ms_def(c, sym);
        def->vars = vars;
        def->nvars = params->len;
        if (c->syms.kind[sym] == MS_SYM_TYPE) {
            declare_nominal_type(c, r->module, sym, vars, params->len);
        }
    }
}

/* ---- defaults, in the order their dependencies need ---- */

enum { DEFAULTS_UNSTARTED, DEFAULTS_STARTED, DEFAULTS_DONE };

typedef struct DefaultsWalk {
    MsResolver *r;
    const MsModule *syntax;
    MsNameMap declared; /* declaration name -> index */
    uint8_t *state;
} DefaultsWalk;

static void defaults_of(DefaultsWalk *w, uint32_t index);

/* Resolves the defaults of every declaration a written type names first. */
static void defaults_of_named(DefaultsWalk *w, const MsTypeRef *t) {
    if (t == NULL) {
        return;
    }
    if (t->kind == MS_TYPE_NAMED) {
        const uint32_t dependency = ms_map_get(&w->declared, t->name);
        if (dependency != MS_NONE) {
            defaults_of(w, dependency);
        }
        for (uint32_t i = 0; i < t->args.len; i++) {
            defaults_of_named(w, t->args.ptr[i]);
        }
        return;
    }
    for (uint32_t i = 0; i < t->params.len; i++) {
        defaults_of_named(w, t->params.ptr[i]->ty);
    }
    defaults_of_named(w, t->result);
}

static void defaults_of(DefaultsWalk *w, uint32_t index) {
    if (w->state[index] != DEFAULTS_UNSTARTED) {
        return;
    }
    w->state[index] = DEFAULTS_STARTED;
    const MsDecl *d = w->syntax->decls[index];
    MsCheck *c = w->r->c;
    const MsSymId sym = decl_has_symbol(d) ? ms_decl_own_symbol(c, w->r->module, d) : MS_NONE;
    if (sym != MS_NONE) {
        const MsTypeParams *params = decl_params(d);
        for (uint32_t i = 0; i < params->len; i++) {
            defaults_of_named(w, params->ptr[i]->def);
        }
        uint32_t nvars = 0;
        const MsTy *vars = ms_sym_vars(c, sym, &nvars);
        ms_resolve_type_defaults(w->r, params, vars);
    }
    w->state[index] = DEFAULTS_DONE;
}

static void resolve_declaration_defaults(MsResolver *r) {
    const MsModule *syntax = r->c->mods[r->module].syntax;
    DefaultsWalk walk = {.r = r, .syntax = syntax};
    walk.state = MS_NEW_N(&r->c->arena, uint8_t, syntax->ndecls + 1);
    memset(walk.state, 0, syntax->ndecls + 1);
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        if (decl_has_symbol(syntax->decls[i])) {
            (void)ms_map_add(&walk.declared, ms_decl_name(syntax->decls[i]), i);
        }
    }
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        defaults_of(&walk, i);
    }
    ms_map_free(&walk.declared);
}

/* ---- bounds and aliases ---- */

static void resolve_declaration_bounds(MsResolver *r) {
    MsCheck *c = r->c;
    const MsModule *syntax = c->mods[r->module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        const MsTypeParams *params = decl_params(d);
        bool bounded = false;
        for (uint32_t k = 0; k < params->len; k++) {
            bounded = bounded || params->ptr[k]->bounds.len != 0;
        }
        const MsSymId sym = bounded ? ms_decl_own_symbol(c, r->module, d) : MS_NONE;
        if (sym == MS_NONE) {
            continue;
        }
        uint32_t nvars = 0;
        const MsTy *vars = ms_sym_vars(c, sym, &nvars);
        const MsTypeScope *outer = r->scope;
        r->scope = ms_variable_scope(c, vars, nvars);
        ms_resolve_type_bounds(r, params, vars);
        r->scope = outer;
    }
}

static void resolve_aliases(MsResolver *r) {
    const MsModule *syntax = r->c->mods[r->module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        const MsSymId sym = d->kind == MS_D_ALIAS ? ms_decl_own_symbol(r->c, r->module, d) : MS_NONE;
        if (sym != MS_NONE) {
            (void)ms_alias_target(r, sym);
        }
    }
}

/* ---- signatures, fields and cases ---- */

static void resolve_cases(MsResolver *r, MsDef *def, const MsDecl *d) {
    MsCheck *c = r->c;
    const uint32_t count = d->kind == MS_D_ENUM ? d->u.enumeration.cases.len : 0;
    def->cases = MS_NEW_N(&c->arena, MsCaseRow, count);
    def->ncases = count;
    for (uint32_t i = 0; i < count; i++) {
        const MsCase *cs = d->u.enumeration.cases.ptr[i];
        for (uint32_t k = 0; k < i; k++) {
            if (d->u.enumeration.cases.ptr[k]->name == cs->name) {
                const MsStr name = ms_name(c->names, cs->name);
                const MsCheckDiag diag = {.diag = {.pos = cs->pos,
                                                   .message = ms_arena_fmt(&c->arena,
                                                                           "duplicate case %.*s; rename or remove one "
                                                                           "of them",
                                                                           (int)name.len, name.ptr)},
                                          .phase = MS_PHASE_TYPE};
                ms_report(c, r->module, &diag);
                break;
            }
        }
        def->cases[i] = (MsCaseRow){.name = cs->name,
                                    .fields = ms_resolve_params(r, &cs->fields),
                                    .nfields = cs->fields.len};
    }
}

static void resolve_nominal_signature(MsResolver *r, MsSymId sym, const MsDecl *d) {
    MsDef *def = ms_def(r->c, sym);
    if (d->kind == MS_D_TYPE) {
        def->fields = ms_resolve_params(r, &d->u.type.fields);
        def->nfields = d->u.type.fields.len;
    }
    resolve_cases(r, ms_def(r->c, sym), d);
}

static void resolve_signatures(MsResolver *r) {
    MsCheck *c = r->c;
    const MsModule *syntax = c->mods[r->module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        const bool resolvable = decl_has_symbol(d) && d->kind != MS_D_CONST && d->kind != MS_D_ALIAS;
        const MsSymId sym = resolvable ? ms_decl_own_symbol(c, r->module, d) : MS_NONE;
        if (sym == MS_NONE) {
            continue;
        }
        uint32_t nvars = 0;
        const MsTy *vars = ms_sym_vars(c, sym, &nvars);
        const MsTypeScope *outer = r->scope;
        r->scope = ms_variable_scope(c, vars, nvars);
        if (d->kind == MS_D_FN) {
            c->syms.ty[sym] = ms_resolve_signature(r, &d->u.fn.params, d->u.fn.result);
        } else {
            resolve_nominal_signature(r, sym, d);
        }
        r->scope = outer;
    }
}

void ms_module_resolve_types(MsCheck *c, MsModId module) {
    ms_module_declare(c, module);
    MsModuleRow *row = &c->mods[module];
    if (row->facts != NULL) {
        return;
    }
    MsFacts *facts = MS_NEW(&c->arena, MsFacts);
    *facts = (MsFacts){.node_count = row->syntax->node_count};
    facts->type_ref_ty = MS_NEW_N(&c->arena, MsTy, facts->node_count + 1);
    memset(facts->type_ref_ty, 0, ((size_t)facts->node_count + 1) * sizeof *facts->type_ref_ty);
    row->facts = facts;
    MsResolver resolver = {.c = c, .module = module, .refs = facts->type_ref_ty};
    declare_type_variables(&resolver);
    resolve_declaration_defaults(&resolver);
    resolve_declaration_bounds(&resolver);
    resolve_aliases(&resolver);
    resolve_signatures(&resolver);
    free(resolver.aliases);
}
