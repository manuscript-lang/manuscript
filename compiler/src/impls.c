/* The methods of implementations (see ms/methods.h). Mirrors `Checker::implementation` in
 * crates/ms-check/src/contracts.rs for what builds the method rows and for the diagnostics about
 * the receiver, the interface and the operations by name. */
#include <stdlib.h>
#include <string.h>

#include "ms/desugar.h"
#include "ms/methods.h"
#include "ms/text.h"

/* One impl being added. */
typedef struct Impl {
    MsResolver *r;
    MsCheck *c;
    MsMethodTable *table;
    const MsDecl *decl;
    MsTy receiver;
    MsTy contract;
    const MsTy *vars; /* the impl's type variables: the receiver's parameters it still uses */
    uint32_t nvars;
} Impl;

/* ---- small helpers ---- */

static MsStr impl_text(const MsCheck *c, MsSym name) { return ms_name(c->names, name); }

static MsStr impl_show(MsCheck *c, MsTy ty) {
    MsBuf buf = {0};
    ms_ty_show(&buf, c->names, &c->tys, ty);
    const MsStr text = {ms_arena_strndup(&c->arena, buf.data == NULL ? "" : buf.data, buf.len), (uint32_t)buf.len};
    ms_buf_free(&buf);
    return text;
}

static void impl_type_error(const Impl *im, MsPos pos, MsStr message) {
    const MsCheckDiag diag = {.diag = {.pos = pos, .message = message}, .phase = MS_PHASE_TYPE};
    ms_report(im->c, im->r->module, &diag);
}

static bool impl_in_standard_module(const MsCheck *c, MsModId module) {
    const MsStr path = impl_text(c, c->mods[module].path);
    return ms_text_starts_with(path, "@std/");
}

static MsSymId impl_nominal_symbol(const MsCheck *c, MsTy ty) {
    return c->tys.def[ty] == 0 ? MS_NONE : c->tys.def[ty] - 1;
}

/* Type variables are matched by id: resolving a variable's name interns an equal type that may be a
 * different row from the one the variable was declared with. */
static bool impl_same_variable(const MsTyTable *t, MsTy a, MsTy b) {
    return t->kind[a] == MS_K_VARIABLE && t->id[a] == t->id[b];
}

static bool impl_type_mentions(const MsTyTable *t, MsTy ty, MsTy var) {
    if (impl_same_variable(t, ty, var)) {
        return true;
    }
    for (uint32_t i = 0; i < t->nargs[ty]; i++) {
        if (impl_type_mentions(t, ms_ty_args(t, ty)[i], var)) {
            return true;
        }
    }
    for (uint32_t i = 0; i < t->nparams[ty]; i++) {
        if (impl_type_mentions(t, ms_ty_params(t, ty)[i].ty, var)) {
            return true;
        }
    }
    return t->result[ty] != MS_TY_NONE && impl_type_mentions(t, t->result[ty], var);
}

/* ---- the receiver ---- */

/* New variables for the receiver type's parameters, with its bounds over them: what the impl's
 * own `Box[T]` names, whatever its declaration called its parameters. */
static MsTy *impl_receiver_variables(const Impl *im, MsSymId symbol, uint32_t *count) {
    MsCheck *c = im->c;
    uint32_t n = 0;
    const MsTy *declared = ms_sym_vars(c, symbol, &n);
    MsTy *fresh = MS_NEW_N(&c->arena, MsTy, n);
    const MsStr path = impl_text(c, c->mods[im->r->module].path);
    for (uint32_t i = 0; i < n; i++) {
        const MsStr name = impl_text(c, c->tys.name[declared[i]]);
        const MsStr id = ms_arena_fmt(&c->arena, "%.*s/impl%u/%.*s", (int)path.len, path.ptr, im->decl->id, (int)name.len, name.ptr);
        const MsTyDesc desc = {.name = c->tys.name[declared[i]], .id = ms_intern(c->names, id.ptr, id.len), .kind = MS_K_VARIABLE};
        fresh[i] = ms_ty_fresh(&c->tys, &desc);
    }
    const MsTySubst renamed = {.vars = declared, .args = fresh, .count = n};
    for (uint32_t i = 0; i < n; i++) {
        const MsVarInfo bounds = *ms_var_info(c, declared[i]);
        for (uint32_t k = 0; k < bounds.nbounds; k++) {
            MsVarInfo *info = ms_var_info(c, fresh[i]);
            info->bounds = ms_array_resize(info->bounds, info->nbounds + 1, sizeof *info->bounds);
            info->bounds[info->nbounds++] = ms_ty_subst(&c->tys, &c->arena, bounds.bounds[k], &renamed);
        }
    }
    *count = n;
    return fresh;
}

static bool impl_builtin_comparable(const MsCheck *c, MsTy ty) {
    const MsBuiltin b = ms_ty_builtin(&c->tys, ty);
    return ms_builtin_is_int(b) || ms_builtin_is_float(b) || b == MS_BI_STRING || b == MS_BI_DECIMAL ||
           b == MS_BI_BIGINT || b == MS_BI_DURATION || b == MS_BI_INSTANT || b == MS_BI_TIMESTAMP;
}

/* Reports `receiver` when it is an `opaque type` another module declares; true when it did. */
static bool impl_opaque_denied(const Impl *im) {
    MsCheck *c = im->c;
    const MsSymId symbol = impl_nominal_symbol(c, im->receiver);
    const MsDecl *d = symbol == MS_NONE ? NULL : c->syms.decl[symbol];
    const bool opaque = d != NULL && ((d->kind == MS_D_TYPE && d->u.type.opaque) || (d->kind == MS_D_ENUM && d->u.enumeration.opaque));
    const MsModId owner = symbol == MS_NONE ? MS_NONE : c->syms.module[symbol];
    if (!opaque || owner == MS_NONE || owner == im->r->module) {
        return false;
    }
    const MsStr type = impl_show(c, im->receiver);
    const MsStr module = impl_text(c, c->mods[owner].path);
    impl_type_error(im, im->decl->pos,
                    ms_arena_fmt(&c->arena,
                                 "%.*s is opaque outside %.*s: it takes no new methods or interfaces here; use the "
                                 "functions %.*s exports",
                                 (int)type.len, type.ptr, (int)module.len, module.ptr, (int)module.len, module.ptr));
    return true;
}

/* Whether the receiver may take methods: nominal source data, an `extern type` of its own module,
 * or in a bundled module a native or scalar type. Reports why not. */
static bool impl_receiver_allowed(const Impl *im) {
    MsCheck *c = im->c;
    const MsModId module = im->r->module;
    const MsSymId nominal = impl_nominal_symbol(c, im->receiver);
    const MsKind kind = (MsKind)c->tys.kind[im->receiver];
    const bool standard = impl_in_standard_module(c, module);
    const bool own_extern = kind == MS_K_NATIVE && nominal != MS_NONE && c->syms.module[nominal] == module;
    const bool foreign_native = nominal != MS_NONE && c->syms.native[nominal] != MS_NATIVE_SOURCE && !own_extern && !standard;
    const bool scalar_extension = standard && impl_builtin_comparable(c, im->receiver);
    const bool nominal_data = own_extern || kind == MS_K_TYPE || kind == MS_K_ALTERNATIVE || (standard && kind == MS_K_NATIVE);
    if (scalar_extension || (nominal != MS_NONE && !foreign_native && nominal_data)) {
        return true;
    }
    if (kind != MS_K_INVALID) {
        impl_type_error(im, im->decl->pos,
                        ms_arena_fmt(&c->arena,
                                     "implementation receiver must be nominal source data; declare methods on a type or "
                                     "enum you declare, such as 'fn Point.show() String:', not on built-in or function "
                                     "types"));
    }
    return false;
}

/* The variables the receiver writes keep their place; the others were specialized to a concrete
 * argument (`Box[Int]`), and a bound that names them reads as that argument. */
static void impl_keep_used_variables(Impl *im, const MsTy *declared, uint32_t count) {
    MsCheck *c = im->c;
    MsTy *used = MS_NEW_N(&c->arena, MsTy, count);
    MsTy *spec_vars = MS_NEW_N(&c->arena, MsTy, count);
    MsTy *spec_args = MS_NEW_N(&c->arena, MsTy, count);
    uint32_t nused = 0;
    uint32_t nspec = 0;
    for (uint32_t i = 0; i < count; i++) {
        if (impl_type_mentions(&c->tys, im->receiver, declared[i])) {
            used[nused++] = declared[i];
        } else if (i < c->tys.nargs[im->receiver]) {
            spec_vars[nspec] = declared[i];
            spec_args[nspec++] = ms_ty_args(&c->tys, im->receiver)[i];
        }
    }
    const MsTySubst specialized = {.vars = spec_vars, .args = spec_args, .count = nspec};
    for (uint32_t i = 0; i < nused; i++) {
        MsVarInfo *info = ms_var_info(c, used[i]);
        for (uint32_t k = 0; k < info->nbounds; k++) {
            info->bounds[k] = ms_ty_subst(&c->tys, &c->arena, info->bounds[k], &specialized);
        }
    }
    im->vars = used;
    im->nvars = nused;
}

/* ---- the interface ---- */

/* An interface argument that is one of the impl's variables carries the interface's declared
 * bounds into this implementation. */
static void impl_add_interface_bounds(const Impl *im) {
    MsCheck *c = im->c;
    const MsSymId symbol = impl_nominal_symbol(c, im->contract);
    uint32_t arity = 0;
    const MsTy *declared = symbol == MS_NONE ? NULL : ms_sym_vars(c, symbol, &arity);
    if (declared == NULL || c->tys.nargs[im->contract] != arity) {
        return;
    }
    const MsTySubst arguments = {.vars = declared, .args = ms_ty_args(&c->tys, im->contract), .count = arity};
    for (uint32_t i = 0; i < arity; i++) {
        for (uint32_t k = 0; k < im->nvars; k++) {
            if (!impl_same_variable(&c->tys, ms_ty_args(&c->tys, im->contract)[i], im->vars[k])) {
                continue;
            }
            const MsVarInfo bounds = *ms_var_info(c, declared[i]);
            MsVarInfo *info = ms_var_info(c, im->vars[k]);
            for (uint32_t b = 0; b < bounds.nbounds; b++) {
                info->bounds = ms_array_resize(info->bounds, info->nbounds + 1, sizeof *info->bounds);
                info->bounds[info->nbounds++] = ms_ty_subst(&c->tys, &c->arena, bounds.bounds[b], &arguments);
            }
        }
    }
}

/* The contract's operations over this impl: its arguments for the interface's variables and the
 * receiver for `Self`. */
typedef struct ImplOperations {
    const MsOperation *ops;
    uint32_t count;
    MsTy *types; /* each operation's signature, substituted */
} ImplOperations;

static ImplOperations impl_contract_operations(Impl *im) {
    MsCheck *c = im->c;
    ImplOperations bound = {0};
    const MsSymId symbol = impl_nominal_symbol(c, im->contract);
    if (symbol == MS_NONE || c->tys.kind[im->contract] != MS_K_CONTRACT || c->syms.module[symbol] == MS_NONE) {
        return bound;
    }
    ms_module_ensure_operations(c, c->syms.module[symbol], im->table);
    const MsOperations *list = ms_interface_operations(im->table, symbol);
    if (list == NULL) {
        return bound;
    }
    uint32_t arity = 0;
    const MsTy *declared = ms_sym_vars(c, symbol, &arity);
    MsTy *vars = MS_NEW_N(&c->arena, MsTy, (size_t)arity + 1);
    MsTy *args = MS_NEW_N(&c->arena, MsTy, (size_t)arity + 1);
    uint32_t n = 0;
    for (uint32_t i = 0; i < arity && i < c->tys.nargs[im->contract]; i++) {
        vars[n] = declared[i];
        args[n++] = ms_ty_args(&c->tys, im->contract)[i];
    }
    vars[n] = ms_self_variable(c, im->contract);
    args[n++] = im->receiver;
    const MsTySubst s = {.vars = vars, .args = args, .count = n};
    bound.ops = list->items;
    bound.count = list->count;
    bound.types = MS_NEW_N(&c->arena, MsTy, list->count);
    for (uint32_t i = 0; i < list->count; i++) {
        bound.types[i] = ms_ty_subst(&c->tys, &c->arena, list->items[i].ty, &s);
    }
    return bound;
}

/* ---- rows ---- */

typedef struct ImplRow {
    MsSym id;
    MsTy contract;
    MsTy ty;
    const MsFunc *decl;
    MsPos pos;
    const MsTy *own; /* the method's own variables, after the impl's */
    uint32_t nown;
} ImplRow;

#define IMPL_GROW_COLUMN(m, column, needed) \
    ((m)->column = ms_array_resize((m)->column, (needed), sizeof *(m)->column))

static void impl_grow_methods(MsMethods *m) {
    if (m->count < m->cap) {
        return;
    }
    const uint32_t cap = ms_capacity_for(m->cap, m->count + 1);
    IMPL_GROW_COLUMN(m, id, cap);
    IMPL_GROW_COLUMN(m, receiver, cap);
    IMPL_GROW_COLUMN(m, contract, cap);
    IMPL_GROW_COLUMN(m, ty, cap);
    IMPL_GROW_COLUMN(m, decl, cap);
    IMPL_GROW_COLUMN(m, native, cap);
    IMPL_GROW_COLUMN(m, inherent, cap);
    IMPL_GROW_COLUMN(m, module, cap);
    IMPL_GROW_COLUMN(m, local, cap);
    IMPL_GROW_COLUMN(m, pos, cap);
    IMPL_GROW_COLUMN(m, vars_at, cap);
    IMPL_GROW_COLUMN(m, nvars, cap);
    m->cap = cap;
}

static void impl_push_variables(MsMethods *m, const MsTy *vars, uint32_t count) {
    if (m->vars_len + count > m->vars_cap) {
        m->vars_cap = ms_capacity_for(m->vars_cap, m->vars_len + count);
        m->vars = ms_array_resize(m->vars, m->vars_cap, sizeof *m->vars);
    }
    if (count > 0) {
        memcpy(m->vars + m->vars_len, vars, (size_t)count * sizeof *vars);
    }
    m->vars_len += count;
}

/* An extension declared outside the receiver's module is visible in its own module only, unless a
 * bundled module extends a native standard type, which applies wherever it is used. */
static bool impl_extends_elsewhere(const Impl *im) {
    const MsCheck *c = im->c;
    const MsSymId nominal = impl_nominal_symbol(c, im->receiver);
    if (nominal == MS_NONE || c->syms.module[nominal] == MS_NONE) {
        return false;
    }
    const bool extends_native = impl_in_standard_module(c, im->r->module) && c->syms.native[nominal] != MS_NATIVE_SOURCE;
    return c->syms.module[nominal] != im->r->module && !extends_native;
}

static bool impl_has_inherent_contract(const MsCheck *c, MsTy contract) {
    return contract != MS_TY_NONE && ms_text_ends_with(impl_text(c, c->tys.name[contract]), MS_INHERENT_SUFFIX);
}

static void impl_add_row(Impl *im, const ImplRow *row) {
    MsCheck *c = im->c;
    MsMethods *m = &im->table->methods;
    impl_grow_methods(m);
    const uint32_t at = m->count++;
    m->id[at] = row->id;
    m->receiver[at] = im->receiver;
    m->contract[at] = row->contract;
    m->ty[at] = row->ty;
    m->decl[at] = row->decl;
    m->native[at] = MS_NATIVE_SOURCE;
    m->inherent[at] = impl_has_inherent_contract(c, row->contract);
    m->module[at] = im->r->module;
    m->local[at] = impl_extends_elsewhere(im);
    m->pos[at] = row->pos;
    m->vars_at[at] = m->vars_len;
    m->nvars[at] = im->nvars + row->nown;
    impl_push_variables(m, im->vars, im->nvars);
    impl_push_variables(m, row->own, row->nown);
}

static MsSym impl_row_id(const Impl *im, MsStr operation) {
    MsCheck *c = im->c;
    const MsStr path = impl_text(c, c->mods[im->r->module].path);
    const MsStr receiver = impl_text(c, c->tys.name[im->receiver]);
    const MsStr contract = impl_text(c, c->tys.name[im->contract]);
    const MsStr id = ms_arena_fmt(&c->arena, "%.*s/%.*s/%.*s/%.*s", (int)path.len, path.ptr, (int)receiver.len,
                                  receiver.ptr, (int)contract.len, contract.ptr, (int)operation.len, operation.ptr);
    return ms_intern(c->names, id.ptr, id.len);
}

/* ---- methods ---- */

static const MsTypeScope *impl_scope_with(MsCheck *c, const MsTypeScope *parent, MsSym name, const MsTy *ty) {
    MsTypeScope *scope = MS_NEW(&c->arena, MsTypeScope);
    MsSym *names = MS_NEW(&c->arena, MsSym);
    *names = name;
    *scope = (MsTypeScope){.parent = parent, .names = names, .types = ty, .len = 1};
    return scope;
}

static bool impl_scope_has(const MsTypeScope *scope, MsSym name) {
    for (; scope != NULL; scope = scope->parent) {
        for (uint32_t i = 0; i < scope->len; i++) {
            if (scope->names[i] == name) {
                return true;
            }
        }
    }
    return false;
}

/* The type parameters a method declares for itself, in the impl's scope: `r->scope` gains them. */
static MsTy *impl_method_variables(Impl *im, const MsMethod *method, uint32_t index) {
    MsCheck *c = im->c;
    const MsTypeParams *params = &method->func.type_params;
    MsTy *own = MS_NEW_N(&c->arena, MsTy, params->len);
    const MsStr path = impl_text(c, c->mods[im->r->module].path);
    for (uint32_t i = 0; i < params->len; i++) {
        const MsStr name = impl_text(c, params->ptr[i]->name);
        if (impl_scope_has(im->r->scope, params->ptr[i]->name)) {
            impl_type_error(im, params->ptr[i]->pos,
                            ms_arena_fmt(&c->arena,
                                         "type parameter %.*s shadows a type parameter of the impl; choose a different "
                                         "name",
                                         (int)name.len, name.ptr));
        }
        const MsStr id = ms_arena_fmt(&c->arena, "%.*s/impl%u/%u/%.*s", (int)path.len, path.ptr, im->decl->id, index,
                                      (int)name.len, name.ptr);
        const MsTyDesc desc = {.name = params->ptr[i]->name, .id = ms_intern(c->names, id.ptr, id.len), .kind = MS_K_VARIABLE};
        own[i] = ms_ty_fresh(&c->tys, &desc);
        im->r->scope = impl_scope_with(c, im->r->scope, params->ptr[i]->name, &own[i]);
    }
    return own;
}

static const MsOperation *impl_find_operation(const ImplOperations *ops, MsSym name) {
    for (uint32_t i = 0; i < ops->count; i++) {
        if (ops->ops[i].name == name) {
            return &ops->ops[i];
        }
    }
    return NULL;
}

static bool impl_has_field(const Impl *im, MsSym name) {
    const MsSymId nominal = impl_nominal_symbol(im->c, im->receiver);
    const MsDef *def = nominal == MS_NONE || nominal >= im->c->defs_cap ? NULL : &im->c->defs[nominal];
    for (uint32_t i = 0; def != NULL && i < def->nfields; i++) {
        if (def->fields[i].name == name) {
            return true;
        }
    }
    return false;
}

static void impl_check_method_names(const Impl *im, const MsMethod *method, uint32_t index) {
    MsCheck *c = im->c;
    const MsStr name = impl_text(c, method->func.name);
    for (uint32_t k = 0; k < index; k++) {
        if (im->decl->u.impl.methods.ptr[k]->func.name == method->func.name) {
            impl_type_error(im, method->pos,
                            ms_arena_fmt(&c->arena, "duplicate implementation operation %.*s; define each operation once per impl",
                                         (int)name.len, name.ptr));
            break;
        }
    }
    /* An inherent method is reachable only as `value.name()`, which a field of the same name always
     * shadows; an interface operation stays reachable through a view. */
    if (im->decl->synthetic && impl_has_field(im, method->func.name)) {
        const MsStr receiver = impl_show(c, im->receiver);
        impl_type_error(im, method->pos,
                        ms_arena_fmt(&c->arena,
                                     "operation %.*s has the same name as a field of %.*s; `value.%.*s` always reads the "
                                     "field, so rename one of them",
                                     (int)name.len, name.ptr, (int)receiver.len, receiver.ptr, (int)name.len, name.ptr));
    }
}

static void impl_check_mutating(const Impl *im, const MsMethod *method, const MsOperation *op) {
    if (op == NULL || !method->mutating || op->decl->mutating) {
        return;
    }
    MsCheck *c = im->c;
    const MsStr name = impl_text(c, method->func.name);
    const MsStr contract = impl_show(c, im->contract);
    impl_type_error(im, method->pos,
                    ms_arena_fmt(&c->arena,
                                 "implementation of %.*s is declared var fn but %.*s declares it fn; an operation that "
                                 "changes its receiver is declared `var fn` in the interface too",
                                 (int)name.len, name.ptr, (int)contract.len, contract.ptr));
}

static void impl_add_method(Impl *im, const ImplOperations *ops, uint32_t index) {
    MsCheck *c = im->c;
    const MsMethod *method = im->decl->u.impl.methods.ptr[index];
    impl_check_method_names(im, method, index);
    const MsTypeScope *outer = im->r->scope;
    MsTy *own = impl_method_variables(im, method, index);
    const MsTypeScope *with_own = im->r->scope;
    ms_resolve_type_bounds(im->r, &method->func.type_params, own);
    im->r->scope = outer; /* a default sees the impl's variables, not the method's own */
    ms_resolve_type_defaults(im->r, &method->func.type_params, own);
    im->r->scope = with_own;
    const MsTy signature = ms_resolve_signature(im->r, &method->func.params, method->func.result);
    impl_check_mutating(im, method, impl_find_operation(ops, method->func.name));
    const ImplRow row = {.id = impl_row_id(im, impl_text(c, method->func.name)),
                     .contract = im->contract,
                     .ty = signature,
                     .decl = &method->func,
                     .pos = method->pos,
                     .own = own,
                     .nown = method->func.type_params.len};
    impl_add_row(im, &row);
    im->r->scope = outer;
}

/* ---- operations the impl leaves to the interface ---- */

/* A property without operations has no method to carry its evidence, so the impl itself is a row. */
static void impl_add_property_row(Impl *im) {
    MsCheck *c = im->c;
    if (ms_ty_is(&c->tys, im->contract, MS_BI_DATA) && c->tys.kind[im->receiver] != MS_K_NATIVE &&
        !impl_in_standard_module(c, im->r->module)) {
        const MsStr receiver = impl_show(c, im->receiver);
        impl_type_error(im, im->decl->pos,
                        ms_arena_fmt(&c->arena,
                                     "%.*s is Data when its parts are; only an extern type or the standard library "
                                     "declares Data, so remove this impl",
                                     (int)receiver.len, receiver.ptr));
    }
    const ImplRow row = {.id = impl_row_id(im, (MsStr){"", 0}), .contract = im->contract, .ty = im->contract, .pos = im->decl->pos};
    impl_add_row(im, &row);
}

/* `TestHooks` has no-op defaults, so an impl may leave operations out: each becomes an ordinary
 * method that does nothing. */
static void impl_add_default_operations(Impl *im, const ImplOperations *ops) {
    MsCheck *c = im->c;
    const MsDecl *d = im->decl;
    for (uint32_t i = 0; i < ops->count; i++) {
        bool written = false;
        for (uint32_t k = 0; k < d->u.impl.methods.len; k++) {
            written = written || d->u.impl.methods.ptr[k]->func.name == ops->ops[i].name;
        }
        if (written || !ms_ty_is(&c->tys, im->contract, MS_BI_TESTHOOKS)) {
            continue;
        }
        MsFunc *func = MS_NEW(&c->arena, MsFunc);
        *func = (MsFunc){.name = ops->ops[i].name};
        const ImplRow row = {.id = impl_row_id(im, impl_text(c, ops->ops[i].name)),
                         .contract = im->contract,
                         .ty = ops->types[i],
                         .decl = func,
                         .pos = d->pos};
        impl_add_row(im, &row);
    }
}

/* ---- one impl ---- */

static bool impl_resolve_receiver(Impl *im) {
    MsCheck *c = im->c;
    MsResolver *r = im->r;
    const MsTypeRef *written = im->decl->u.impl.receiver;
    const MsSym name = written->kind == MS_TYPE_NAMED ? written->name : ms_intern_cstr(c->names, "fn");
    const MsSymId symbol = ms_map_get(&c->mods[r->module].names, name);
    MsTy *declared = NULL;
    uint32_t count = 0;
    if (symbol != MS_NONE && c->syms.decl[symbol] != NULL && c->syms.kind[symbol] == MS_SYM_TYPE) {
        declared = impl_receiver_variables(im, symbol, &count);
    }
    r->scope = ms_variable_scope(c, declared, count);
    im->receiver = ms_resolve_type(r, written);
    if (impl_opaque_denied(im) || !impl_receiver_allowed(im)) {
        return false;
    }
    impl_keep_used_variables(im, declared, count);
    r->scope = ms_variable_scope(c, im->vars, im->nvars);
    return true;
}

static void impl_add_implementation(Impl *im) {
    MsResolver *r = im->r;
    if (!impl_resolve_receiver(im)) {
        return;
    }
    im->contract = ms_resolve_type(r, im->decl->u.impl.contract);
    if (im->c->tys.kind[im->contract] != MS_K_CONTRACT && im->c->tys.kind[im->contract] != MS_K_INVALID) {
        impl_type_error(im, im->decl->pos,
                        ms_arena_fmt(&im->c->arena, "implementation target must be an interface declared with 'interface'"));
    }
    impl_add_interface_bounds(im);
    const ImplOperations ops = impl_contract_operations(im);
    r->scope = impl_scope_with(im->c, r->scope, ms_intern_cstr(im->c->names, "Self"), &im->receiver);
    for (uint32_t i = 0; i < im->decl->u.impl.methods.len; i++) {
        impl_add_method(im, &ops, i);
    }
    if (ops.count == 0 && im->decl->u.impl.methods.len == 0 && im->c->tys.kind[im->contract] == MS_K_CONTRACT) {
        impl_add_property_row(im);
    }
    impl_add_default_operations(im, &ops);
}

void ms_module_add_implementations(MsCheck *c, MsModId module, MsMethodTable *table) {
    const MsModule *syntax = c->mods[module].syntax;
    MsResolver resolver = {.c = c, .module = module, .refs = c->mods[module].facts->type_ref_ty};
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        if (syntax->decls[i]->kind != MS_D_IMPL) {
            continue;
        }
        Impl im = {.r = &resolver, .c = c, .table = table, .decl = syntax->decls[i]};
        resolver.scope = NULL;
        impl_add_implementation(&im);
    }
    free(resolver.aliases);
}
