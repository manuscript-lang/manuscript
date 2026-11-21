/* Written types: what a type reference means in a scope of type variables, with the diagnostics
 * of a bad one. A port of `resolve`, `resolve_alias_use`, `alias_target`, `type_set`,
 * `type_variables`, `type_defaults`, `resolve_type_bounds`, `params` and `signature` of
 * crates/ms-check/src/checker.rs. */
#include <string.h>

#include "ms/check.h"
#include "ms/text.h"
#include "ms/hints.h"
#include "ms/import_hints.h"

/* ---- text and diagnostics ---- */

static MsStr ty_text(const MsCheck *c, MsSym name) {
    return ms_name(c->names, name);
}

static void ty_report(MsResolver *r, MsPhase phase, MsPos pos, MsStr message, MsSym unknown) {
    const MsCheckDiag diag = {.diag = {.pos = pos, .message = message}, .phase = phase, .unknown = unknown};
    ms_report(r->c, r->module, &diag);
}

static void ty_type_error(MsResolver *r, MsPos pos, MsStr message) {
    ty_report(r, MS_PHASE_TYPE, pos, message, 0);
}

static void ty_res_error(MsResolver *r, MsPos pos, MsStr message) {
    ty_report(r, MS_PHASE_RESOLUTION, pos, message, 0);
}

/* ---- types ---- */

static MsTy ty_invalid(MsCheck *c) {
    const MsSym name = ms_intern_cstr(c->names, "<invalid>");
    const MsTyDesc desc = {.name = name, .id = name, .kind = MS_K_INVALID};
    return ms_ty_intern(&c->tys, &desc);
}

/* The description of an existing type, to build a changed copy of it. */
static MsTyDesc ty_desc_of(const MsTyTable *t, MsTy ty) {
    return (MsTyDesc){.name = t->name[ty],
                      .id = t->id[ty],
                      .kind = (MsKind)t->kind[ty],
                      .builtin = (MsBuiltin)t->builtin[ty],
                      .def = t->def[ty],
                      .args = ms_ty_args(t, ty),
                      .nargs = t->nargs[ty],
                      .params = ms_ty_params(t, ty),
                      .nparams = t->nparams[ty],
                      .result = t->result[ty]};
}

/* Whether `ty` is `<invalid>` or mentions it in an argument, parameter or result. */
static bool ty_mentions_invalid(const MsTyTable *t, MsTy ty) {
    if (t->kind[ty] == MS_K_INVALID) {
        return true;
    }
    const MsTy *args = ms_ty_args(t, ty);
    for (uint32_t i = 0; i < t->nargs[ty]; i++) {
        if (ty_mentions_invalid(t, args[i])) {
            return true;
        }
    }
    const MsTyParam *params = ms_ty_params(t, ty);
    for (uint32_t i = 0; i < t->nparams[ty]; i++) {
        if (ty_mentions_invalid(t, params[i].ty)) {
            return true;
        }
    }
    return t->result[ty] != MS_TY_NONE && ty_mentions_invalid(t, t->result[ty]);
}

/* ---- scopes of type variables ---- */

static MsTy ty_lookup(const MsTypeScope *scope, MsSym name) {
    for (; scope != NULL; scope = scope->parent) {
        for (uint32_t i = 0; i < scope->len; i++) {
            if (scope->names[i] == name) {
                return scope->types[i];
            }
        }
    }
    return MS_TY_NONE;
}

const MsTypeScope *ms_variable_scope(MsCheck *c, const MsTy *vars, uint32_t count) {
    MsTypeScope *scope = MS_NEW(&c->arena, MsTypeScope);
    MsSym *names = MS_NEW_N(&c->arena, MsSym, count);
    for (uint32_t i = 0; i < count; i++) {
        names[i] = c->tys.name[vars[i]];
    }
    *scope = (MsTypeScope){.names = names, .types = vars, .len = count};
    return scope;
}

const MsTy *ms_sym_vars(const MsCheck *c, MsSymId sym, uint32_t *count) {
    const MsDef *def = sym < c->defs_cap ? &c->defs[sym] : NULL;
    if (def != NULL && def->vars != NULL) {
        *count = def->nvars;
        return def->vars;
    }
    const MsTy ty = c->syms.ty[sym];
    *count = ty == MS_TY_NONE ? 0 : c->tys.nargs[ty];
    return ty == MS_TY_NONE ? NULL : ms_ty_args(&c->tys, ty);
}

/* ---- type arguments ---- */

static const MsVarInfo *ty_var_info(MsCheck *c, MsTy var) {
    return ms_var_info(c, var);
}

/* How many leading arguments a use must write: up to the last variable without a default. */
static uint32_t ty_required_arguments(MsCheck *c, const MsTy *vars, uint32_t count) {
    for (uint32_t i = count; i > 0; i--) {
        if (ty_var_info(c, vars[i - 1])->def == MS_TY_NONE) {
            return i;
        }
    }
    return 0;
}

/* The written arguments followed by the defaults of the variables left out, each default over
 * the arguments before it. */
static MsTy *ty_with_defaults(MsCheck *c, const MsTy *vars, uint32_t nvars, const MsTy *written, uint32_t nwritten) {
    MsTy *args = MS_NEW_N(&c->arena, MsTy, nvars);
    memcpy(args, written, (size_t)nwritten * sizeof *args);
    for (uint32_t i = nwritten; i < nvars; i++) {
        const MsTySubst subst = {.vars = vars, .args = args, .count = i};
        args[i] = ms_ty_subst(&c->tys, &c->arena, ty_var_info(c, vars[i])->def, &subst);
    }
    return args;
}

static MsTy *ty_resolve_all(MsResolver *r, const MsTypeRefs *refs) {
    MsTy *out = MS_NEW_N(&r->c->arena, MsTy, refs->len);
    for (uint32_t i = 0; i < refs->len; i++) {
        out[i] = ms_resolve_type(r, refs->ptr[i]);
    }
    return out;
}

/* ---- unknown names ---- */

static bool ty_in_standard(const MsCheck *c, MsModId module) {
    const MsStr path = ms_name(c->names, c->mods[module].path);
    return path.len >= 5 && memcmp(path.ptr, "@std/", 5) == 0;
}

/* The names of the module's types, for a spelling suggestion; `Optional` is left out. */
static MsStr *ty_type_names(MsResolver *r, size_t *count) {
    const MsNameMap *names = &r->c->mods[r->module].names;
    MsStr *out = MS_NEW_N(&r->c->arena, MsStr, names->cap + 1);
    size_t n = 0;
    for (uint32_t i = 0; i < names->cap; i++) {
        if (names->vals[i] == 0) {
            continue;
        }
        const MsStr name = ty_text(r->c, names->keys[i]);
        if (r->c->syms.kind[names->vals[i] - 1] == MS_SYM_TYPE && !ms_text_is(name, "Optional")) {
            out[n++] = name;
        }
    }
    *count = n;
    return out;
}

/* Names other languages spell differently, with the advice that follows "unknown type X". */
static const struct {
    const char *names[5];
    const char *advice;
} ty_spelling_hints[] = {
    {{"Callable", "Function", "Func", "Fn", NULL},
     "; function types are written fn(Int) Int: parameter types in parentheses, then the result type"},
    {{"Option", "Maybe", NULL}, "; an optional type is written T?, e.g. Int? or (fn(Int) Int)?"},
};

/* Explains an unknown type: where to import it from, or the spelling it was meant to have. */
static MsStr ty_unknown_message(MsResolver *r, MsSym name_sym) {
    MsCheck *c = r->c;
    const MsStr name = ty_text(c, name_sym);
    const MsStr message = ms_arena_fmt(&c->arena, "unknown type %.*s", (int)name.len, name.ptr);
    const MsStr import = ms_type_import_hint(&c->arena, c, name, ty_in_standard(c, r->module));
    if (import.len != 0) {
        return ms_arena_fmt(&c->arena, "%.*s%.*s", (int)message.len, message.ptr, (int)import.len, import.ptr);
    }
    for (size_t i = 0; i < sizeof ty_spelling_hints / sizeof *ty_spelling_hints; i++) {
        for (size_t k = 0; ty_spelling_hints[i].names[k] != NULL; k++) {
            if (ms_text_is(name, ty_spelling_hints[i].names[k])) {
                return ms_arena_fmt(&c->arena, "%.*s%s", (int)message.len, message.ptr, ty_spelling_hints[i].advice);
            }
        }
    }
    const char *builtin = ms_type_alias(name);
    if (builtin != NULL) {
        return ms_arena_fmt(&c->arena, "%.*s; did you mean '%s'?", (int)message.len, message.ptr, builtin);
    }
    size_t count = 0;
    const MsStr *candidates = ty_type_names(r, &count);
    const MsStr hint = ms_did_you_mean(&c->arena, name, candidates, count);
    if (hint.len != 0) {
        return ms_arena_fmt(&c->arena, "%.*s%.*s", (int)message.len, message.ptr, (int)hint.len, hint.ptr);
    }
    return ms_arena_fmt(&c->arena,
                        "%.*s; declare it with 'type %.*s:' / 'enum %.*s:' / 'interface %.*s:', declare it as a type "
                        "parameter, or import it",
                        (int)message.len, message.ptr, (int)name.len, name.ptr, (int)name.len, name.ptr, (int)name.len,
                        name.ptr);
}

/* Explains an arity error caused by a declaration that replaced the prelude type of that name. */
static MsStr ty_prelude_shadow_hint(MsResolver *r, MsSym name_sym) {
    MsCheck *c = r->c;
    const MsSymId prelude = ms_map_get(&c->std_types, name_sym);
    const MsSymId declared = ms_map_get(&c->mods[r->module].names, name_sym);
    if (prelude == MS_NONE || declared == MS_NONE || declared == prelude || !ms_is_prelude_symbol(c, prelude)) {
        return (MsStr){"", 0};
    }
    const MsStr name = ty_text(c, name_sym);
    return ms_arena_fmt(&c->arena,
                        "; this module's own %.*s shadows the prelude %.*s, so rename the declaration to use the "
                        "prelude type",
                        (int)name.len, name.ptr, (int)name.len, name.ptr);
}

/* ---- aliases ---- */

static bool ty_resolving(const MsResolver *r, MsSymId alias) {
    for (uint32_t i = 0; i < r->naliases; i++) {
        if (r->aliases[i] == alias) {
            return true;
        }
    }
    return false;
}

static void ty_push_alias(MsResolver *r, MsSymId alias) {
    if (r->naliases == r->aliases_cap) {
        r->aliases_cap = ms_capacity_for(r->aliases_cap, r->naliases + 1);
        r->aliases = ms_array_resize(r->aliases, r->aliases_cap, sizeof *r->aliases);
    }
    r->aliases[r->naliases++] = alias;
}

/* `type Name = A | B`: a bound-only type whose arguments are its members, with the members of a
 * member set flattened in. */
static MsTy ty_type_set(MsResolver *r, MsSymId alias, const MsTypeRefs *targets) {
    MsCheck *c = r->c;
    MsTy *members = MS_NEW_N(&c->arena, MsTy, targets->len * 2 + 1);
    uint32_t count = 0;
    for (uint32_t i = 0; i < targets->len; i++) {
        const bool was = r->allow_type_set;
        r->allow_type_set = true;
        const MsTy member = ms_resolve_type(r, targets->ptr[i]);
        r->allow_type_set = was;
        const bool flatten = c->tys.builtin[member] == MS_BI_TYPESET;
        const MsTy *flat = flatten ? ms_ty_args(&c->tys, member) : &member;
        const uint32_t nflat = flatten ? c->tys.nargs[member] : 1;
        for (uint32_t k = 0; k < nflat; k++) {
            const MsTy m = flat[k];
            if (c->tys.kind[m] == MS_K_INVALID) {
                continue;
            }
            if (c->tys.kind[m] == MS_K_VARIABLE || c->tys.kind[m] == MS_K_CONTRACT) {
                ty_res_error(r, targets->ptr[i]->pos,
                             ms_arena_fmt(&c->arena, "a type set holds concrete types; name a type such as Int, not a "
                                                     "type parameter or interface"));
                continue;
            }
            bool seen = false;
            for (uint32_t j = 0; j < count; j++) {
                seen = seen || members[j] == m;
            }
            if (!seen) {
                members[count++] = m;
            }
        }
    }
    const MsStr id = ms_name(c->names, c->syms.id[alias]);
    const MsTyDesc desc = {.name = c->syms.name[alias],
                           .id = ms_intern(c->names, ms_arena_fmt(&c->arena, "%.*s#typeset", (int)id.len, id.ptr).ptr,
                                           id.len + 8),
                           .kind = MS_K_CONTRACT,
                           .builtin = MS_BI_TYPESET,
                           .args = members,
                           .nargs = count};
    return ms_ty_intern(&c->tys, &desc);
}

MsTy ms_alias_target(MsResolver *r, MsSymId alias) {
    MsCheck *c = r->c;
    if (c->syms.ty[alias] != MS_TY_NONE) {
        return c->syms.ty[alias];
    }
    const MsDecl *decl = c->syms.decl[alias];
    if (decl == NULL || c->syms.module[alias] != r->module) {
        return ty_invalid(c);
    }
    if (ty_resolving(r, alias)) {
        const MsStr name = ty_text(c, c->syms.name[alias]);
        ty_res_error(r, decl->pos,
                     ms_arena_fmt(&c->arena,
                                  "type alias %.*s refers to itself; an alias names another type, so break the cycle "
                                  "with a type or enum",
                                  (int)name.len, name.ptr));
        return ty_invalid(c);
    }
    ty_push_alias(r, alias);
    uint32_t nvars = 0;
    const MsTy *vars = ms_sym_vars(c, alias, &nvars);
    const MsTypeScope *outer = r->scope;
    r->scope = ms_variable_scope(c, vars, nvars);
    const MsTypeRefs *targets = &decl->u.alias.targets;
    const MsTy target = targets->len > 1 ? ty_type_set(r, alias, targets) : ms_resolve_type(r, targets->ptr[0]);
    r->scope = outer;
    r->naliases--;
    c->syms.ty[alias] = target;
    return target;
}

/* A written use of an alias: its target with the written arguments substituted. */
static MsTy ty_resolve_alias_use(MsResolver *r, const MsTypeRef *t, MsSymId alias) {
    MsCheck *c = r->c;
    const MsTy target = ms_alias_target(r, alias);
    const MsStr name = ty_text(c, c->syms.name[alias]);
    if (c->tys.builtin[target] == MS_BI_TYPESET && !r->allow_type_set) {
        ty_type_error(r, t->pos,
                      ms_arena_fmt(&c->arena,
                                   "%.*s is a type set, which constrains a type parameter and has no values; write fn "
                                   "f[T: %.*s](...) or use one of its members",
                                   (int)name.len, name.ptr, (int)name.len, name.ptr));
        return ty_invalid(c);
    }
    uint32_t nvars = 0;
    const MsTy *vars = ms_sym_vars(c, alias, &nvars);
    const MsTy *written = ty_resolve_all(r, &t->args);
    uint32_t nwritten = t->args.len;
    const uint32_t required = ty_required_arguments(c, vars, nvars);
    if (nwritten < nvars && nwritten >= required) {
        written = ty_with_defaults(c, vars, nvars, written, nwritten);
        nwritten = nvars;
    }
    if (nwritten != nvars) {
        const MsStr sketch = ms_type_sketch(&c->arena, name, nvars);
        ty_type_error(r, t->pos,
                      ms_arena_fmt(&c->arena, "alias %.*s takes %u type arguments, found %u; write %.*s", (int)name.len,
                                   name.ptr, nvars, nwritten, (int)sketch.len, sketch.ptr));
        return ty_invalid(c);
    }
    const MsTySubst subst = {.vars = vars, .args = written, .count = nvars};
    const MsTy result = ms_ty_subst(&c->tys, &c->arena, target, &subst);
    r->refs[t->id] = result;
    return result;
}

/* ---- named types ---- */

static void ty_report_arity(MsResolver *r, const MsTypeRef *t, MsTy base, uint32_t found, uint32_t arity,
                            uint32_t required) {
    MsCheck *c = r->c;
    const MsStr name = ty_text(c, c->tys.name[base]);
    const MsStr sketch = ms_type_sketch(&c->arena, name, arity);
    if (required < arity) {
        ty_type_error(r, t->pos,
                      ms_arena_fmt(&c->arena, "%.*s takes %u to %u type arguments, found %u; write %.*s", (int)name.len,
                                   name.ptr, required, arity, found, (int)sketch.len, sketch.ptr));
        return;
    }
    const MsStr hint = ty_prelude_shadow_hint(r, c->tys.name[base]);
    ty_type_error(r, t->pos,
                  ms_arena_fmt(&c->arena, "%.*s requires %u type arguments, found %u; write %.*s%.*s", (int)name.len,
                               name.ptr, arity, found, (int)sketch.len, sketch.ptr, (int)hint.len, hint.ptr));
}

/* The variables of a bundled source module's types exist once the module's own types resolve. */
static void ty_ensure_declared(MsResolver *r, MsSymId sym) {
    const MsModId owner = r->c->syms.module[sym];
    if (owner != MS_NONE && owner != r->module && r->c->mods[owner].source) {
        ms_module_resolve_types(r->c, owner);
    }
}

static MsTy ty_resolve_named(MsResolver *r, const MsTypeRef *t) {
    MsCheck *c = r->c;
    const MsSym name = t->name;
    const MsSymId named = ms_map_get(&c->mods[r->module].names, name);
    MsTy base = ty_lookup(r->scope, name);
    if (base == MS_TY_NONE && named != MS_NONE) {
        ty_ensure_declared(r, named);
    }
    if (base == MS_TY_NONE && named != MS_NONE && c->syms.kind[named] == MS_SYM_ALIAS) {
        return ty_resolve_alias_use(r, t, named);
    }
    if (base == MS_TY_NONE && named != MS_NONE && c->syms.kind[named] == MS_SYM_TYPE) {
        base = c->syms.ty[named];
    }
    if (base == MS_TY_NONE) {
        ty_report(r, MS_PHASE_RESOLUTION, t->pos, ty_unknown_message(r, name), name);
        c->mods[r->module].unknown_type = true;
        return ty_invalid(c);
    }
    if (ms_text_is(ty_text(c, name), "Self") && t->args.len == 0 && c->tys.nargs[base] != 0) {
        /* `Self` in an implementation already carries the receiver's arguments. */
        r->refs[t->id] = base;
        return base;
    }
    const MsTy *written = ty_resolve_all(r, &t->args);
    uint32_t nwritten = t->args.len;
    uint32_t arity = 0;
    uint32_t required = 0;
    const MsTy *vars = NULL;
    if (c->tys.def[base] != 0) {
        vars = ms_sym_vars(c, c->tys.def[base] - 1, &arity);
        required = ty_required_arguments(c, vars, arity);
    }
    if (nwritten < arity && nwritten >= required) {
        written = ty_with_defaults(c, vars, arity, written, nwritten);
        nwritten = arity;
    }
    if (nwritten != arity) {
        ty_report_arity(r, t, base, nwritten, arity, required);
    }
    MsTyDesc desc = ty_desc_of(&c->tys, base);
    desc.args = written;
    desc.nargs = nwritten;
    const MsTy result = ms_ty_intern(&c->tys, &desc);
    r->refs[t->id] = result;
    return result;
}

MsTy ms_ty_apply(MsCheck *c, MsTy base, const MsTy *args, uint32_t nargs) {
    MsTyDesc desc = ty_desc_of(&c->tys, base);
    desc.args = args;
    desc.nargs = nargs;
    return ms_ty_intern(&c->tys, &desc);
}

/* ---- function types, parameters ---- */

MsTyParam *ms_resolve_params(MsResolver *r, const MsParams *params) {
    MsCheck *c = r->c;
    MsTyParam *out = MS_NEW_N(&c->arena, MsTyParam, params->len);
    for (uint32_t i = 0; i < params->len; i++) {
        const MsParam *p = params->ptr[i];
        for (uint32_t k = 0; k < i; k++) {
            if (params->ptr[k]->name == p->name) {
                const MsStr name = ty_text(c, p->name);
                ty_type_error(r, p->pos,
                              ms_arena_fmt(&c->arena,
                                           "duplicate parameter or field %.*s; each name may appear once, so rename one",
                                           (int)name.len, name.ptr));
                break;
            }
        }
        out[i] = (MsTyParam){.name = p->name,
                             .ty = ms_resolve_type(r, p->ty),
                             .flags = (uint8_t)((p->is_mutable ? MS_PARAM_VAR : 0) | (p->moving ? MS_PARAM_MOVE : 0))};
    }
    return out;
}

MsTy ms_resolve_signature(MsResolver *r, const MsParams *params, const MsTypeRef *result) {
    MsCheck *c = r->c;
    const MsTyParam *list = ms_resolve_params(r, params);
    const MsSym fn = ms_intern_cstr(c->names, "fn");
    const MsTyDesc desc = {.name = fn,
                           .id = fn,
                           .kind = MS_K_FUNCTION,
                           .params = list,
                           .nparams = params->len,
                           .result = ms_resolve_type(r, result)};
    return ms_ty_intern(&c->tys, &desc);
}

static MsTy ty_resolve_fn(MsResolver *r, const MsTypeRef *t) {
    MsCheck *c = r->c;
    const MsTy signature = ms_resolve_signature(r, &t->params, t->result);
    MsTyDesc desc = ty_desc_of(&c->tys, signature);
    MsTyParam *positional = MS_NEW_N(&c->arena, MsTyParam, desc.nparams);
    if (desc.nparams != 0) {
        memcpy(positional, desc.params, (size_t)desc.nparams * sizeof *positional);
    }
    for (uint32_t i = 0; i < desc.nparams; i++) {
        positional[i].flags |= MS_PARAM_POSITIONAL;
    }
    desc.params = positional;
    const MsTy result = ms_ty_intern(&c->tys, &desc);
    r->refs[t->id] = result;
    return result;
}

MsTy ms_resolve_type(MsResolver *r, const MsTypeRef *t) {
    if (t == NULL) {
        return ty_invalid(r->c);
    }
    return t->kind == MS_TYPE_FN ? ty_resolve_fn(r, t) : ty_resolve_named(r, t);
}

/* ---- type variables ---- */

static bool ty_is_intrinsic_parameter(MsResolver *r, MsSym name_sym) {
    const MsCheck *c = r->c;
    const MsSymId named = ms_map_get(&c->mods[r->module].names, name_sym);
    if (named != MS_NONE && c->syms.module[named] == MS_NONE) {
        return true;
    }
    const MsStr name = ty_text(c, name_sym);
    return ms_text_is(name, "Equal") || ms_text_is(name, "Comparable") || ms_text_is(name, "Hashable") ||
           ms_text_is(name, "Clonable");
}

MsTy *ms_declare_type_variables(MsResolver *r, MsSymId owner, const MsTypeParams *params) {
    MsCheck *c = r->c;
    MsTy *vars = MS_NEW_N(&c->arena, MsTy, params->len);
    const MsStr owner_id = ms_name(c->names, c->syms.id[owner]);
    for (uint32_t i = 0; i < params->len; i++) {
        const MsTypeParam *p = params->ptr[i];
        const MsStr name = ty_text(c, p->name);
        bool repeated = false;
        for (uint32_t k = 0; k < i; k++) {
            repeated = repeated || params->ptr[k]->name == p->name;
        }
        if (ty_is_intrinsic_parameter(r, p->name) || repeated) {
            ty_res_error(r, p->pos,
                         ms_arena_fmt(&c->arena,
                                      "duplicate or intrinsic type parameter %.*s; choose a different type parameter "
                                      "name",
                                      (int)name.len, name.ptr));
        }
        const MsStr id = ms_arena_fmt(&c->arena, "%.*s/%.*s", (int)owner_id.len, owner_id.ptr, (int)name.len, name.ptr);
        const MsTyDesc desc = {.name = p->name, .id = ms_intern(c->names, id.ptr, id.len), .kind = MS_K_VARIABLE};
        vars[i] = ms_ty_fresh(&c->tys, &desc);
    }
    return vars;
}

void ms_resolve_type_defaults(MsResolver *r, const MsTypeParams *params, const MsTy *vars) {
    MsCheck *c = r->c;
    bool defaulted = false;
    const MsTypeScope *outer = r->scope;
    for (uint32_t i = 0; i < params->len; i++) {
        const MsTypeParam *p = params->ptr[i];
        if (p->def == NULL) {
            if (defaulted) {
                const MsStr name = ty_text(c, p->name);
                ty_type_error(r, p->pos,
                              ms_arena_fmt(&c->arena,
                                           "type parameter %.*s needs a default because an earlier parameter has one; "
                                           "give %.*s a default or move it before the defaulted parameters",
                                           (int)name.len, name.ptr, (int)name.len, name.ptr));
            }
            continue;
        }
        defaulted = true;
        /* Only the variables before this one are visible in its default. */
        MsTypeScope earlier = *ms_variable_scope(c, vars, i);
        earlier.parent = outer;
        r->scope = &earlier;
        const MsTy resolved = ms_resolve_type(r, p->def);
        if (!ty_mentions_invalid(&c->tys, resolved)) {
            ms_var_info(c, vars[i])->def = resolved;
        }
    }
    r->scope = outer;
}

static const char *const ty_bound_not_interface =
    "a bound must be an interface; write T: SomeInterface where SomeInterface is declared with 'interface'";

static MsStr ty_bound_name(const MsCheck *c, const MsTypeRef *b) {
    return b->kind == MS_TYPE_NAMED ? ty_text(c, b->name) : (MsStr){"fn", 2};
}

static void ty_add_bound(MsCheck *c, MsTy var, MsTy bound) {
    MsVarInfo *info = ms_var_info(c, var);
    info->bounds = ms_array_resize(info->bounds, info->nbounds + 1, sizeof *info->bounds);
    info->bounds[info->nbounds++] = bound;
}

/* Reports a bound that is not an interface; true when it is not one. */
static bool ty_reject_bound(MsResolver *r, const MsTypeRef *b, MsTy resolved) {
    MsCheck *c = r->c;
    if (c->tys.kind[resolved] == MS_K_CONTRACT) {
        return false;
    }
    if (c->tys.kind[resolved] == MS_K_VARIABLE) {
        const MsStr name = ty_bound_name(c, b);
        ty_type_error(r, b->pos,
                      ms_arena_fmt(&c->arena,
                                   "a bound must be an interface, but %.*s resolves to a type parameter; rename the "
                                   "type parameter or name an interface",
                                   (int)name.len, name.ptr));
    } else if (!ty_mentions_invalid(&c->tys, resolved)) {
        ty_type_error(r, b->pos, ms_arena_fmt(&c->arena, "%s", ty_bound_not_interface));
    }
    return true;
}

void ms_resolve_type_bounds(MsResolver *r, const MsTypeParams *params, const MsTy *vars) {
    MsCheck *c = r->c;
    for (uint32_t i = 0; i < params->len; i++) {
        for (uint32_t k = 0; k < params->ptr[i]->bounds.len; k++) {
            const MsTypeRef *b = params->ptr[i]->bounds.ptr[k];
            if (b->kind == MS_TYPE_NAMED && ty_lookup(r->scope, b->name) == MS_TY_NONE) {
                const MsSymId named = ms_map_get(&c->mods[r->module].names, b->name);
                const bool is_type = named != MS_NONE && c->syms.kind[named] == MS_SYM_TYPE;
                const MsKind kind = is_type && c->syms.ty[named] != MS_TY_NONE ? (MsKind)c->tys.kind[c->syms.ty[named]]
                                                                              : MS_K_CONTRACT;
                if (is_type && kind != MS_K_CONTRACT && kind != MS_K_VARIABLE) {
                    ty_type_error(r, b->pos, ms_arena_fmt(&c->arena, "%s", ty_bound_not_interface));
                    continue;
                }
            }
            const bool was = r->allow_type_set;
            r->allow_type_set = true;
            const MsTy resolved = ms_resolve_type(r, b);
            r->allow_type_set = was;
            if (!ty_reject_bound(r, b, resolved)) {
                ty_add_bound(c, vars[i], resolved);
            }
        }
    }
}
