/* Interface operations (see ms/methods.h). Mirrors the interface half of `resolve_signature_pass`
 * in crates/ms-check/src/checker.rs, with `declare_self`, `operation_variables` and
 * `check_self_use`. */
#include <stdlib.h>
#include <string.h>

#include "ms/methods.h"

void ms_methods_init(MsMethodTable *table) { *table = (MsMethodTable){0}; }

void ms_methods_free(MsMethodTable *table) {
    for (uint32_t i = 0; i < table->operations_cap; i++) {
        free(table->operations[i].items);
    }
    free(table->operations);
    free(table->operations_done);
    MsMethods *m = &table->methods;
    free(m->id);
    free(m->receiver);
    free(m->contract);
    free(m->ty);
    free(m->decl);
    free(m->access);
    free(m->native);
    free(m->inherent);
    free(m->module);
    free(m->local);
    free(m->pos);
    free(m->vars_at);
    free(m->nvars);
    free(m->vars);
    *table = (MsMethodTable){0};
}

const MsOperations *ms_interface_operations(const MsMethodTable *table, MsSymId sym) {
    if (sym >= table->operations_cap || table->operations[sym].count == 0) {
        return NULL;
    }
    return &table->operations[sym];
}

static MsOperations *operations_of(MsMethodTable *table, MsSymId sym) {
    if (sym >= table->operations_cap) {
        const uint32_t cap = ms_capacity_for(table->operations_cap, sym + 1);
        table->operations = ms_array_resize(table->operations, cap, sizeof *table->operations);
        memset(table->operations + table->operations_cap, 0,
               (size_t)(cap - table->operations_cap) * sizeof *table->operations);
        table->operations_cap = cap;
    }
    return &table->operations[sym];
}

static void add_operation(MsOperations *list, MsOperation op) {
    if (list->count == list->cap) {
        list->cap = ms_capacity_for(list->cap, list->count + 1);
        list->items = ms_array_resize(list->items, list->cap, sizeof *list->items);
    }
    list->items[list->count++] = op;
}

/* ---- diagnostics ---- */

static void report_type_error(MsResolver *r, MsPos pos, MsStr message) {
    const MsCheckDiag diag = {.diag = {.pos = pos, .message = message}, .phase = MS_PHASE_TYPE};
    ms_report(r->c, r->module, &diag);
}

/* ---- Self ---- */

/* The variable `Self` stands for the implementing type of `contract`, an interface type. */
MsTy ms_self_variable(MsCheck *c, MsTy contract) {
    const MsStr owner = ms_name(c->names, c->tys.id[contract]);
    const MsStr id = ms_arena_fmt(&c->arena, "%.*s/Self", (int)owner.len, owner.ptr);
    const MsTyDesc desc = {.name = ms_intern_cstr(c->names, "Self"),
                           .id = ms_intern(c->names, id.ptr, id.len),
                           .kind = MS_K_VARIABLE,
                           .builtin = MS_BI_SELF};
    return ms_ty_intern(&c->tys, &desc);
}

static bool mentions_self(const MsTyTable *t, MsTy ty) {
    if (ms_ty_is(t, ty, MS_BI_SELF)) {
        return true;
    }
    for (uint32_t i = 0; i < t->nargs[ty]; i++) {
        if (mentions_self(t, ms_ty_args(t, ty)[i])) {
            return true;
        }
    }
    for (uint32_t i = 0; i < t->nparams[ty]; i++) {
        if (mentions_self(t, ms_ty_params(t, ty)[i].ty)) {
            return true;
        }
    }
    return t->result[ty] != MS_TY_NONE && mentions_self(t, t->result[ty]);
}

/* `Self` is limited to whole parameter and result types, the positions where a call can
 * substitute the implementing type. */
static bool self_misplaced(const MsTyTable *t, MsTy signature) {
    for (uint32_t i = 0; i < t->nparams[signature]; i++) {
        const MsTy param = ms_ty_params(t, signature)[i].ty;
        if (!ms_ty_is(t, param, MS_BI_SELF) && mentions_self(t, param)) {
            return true;
        }
    }
    const MsTy result = t->result[signature];
    return result != MS_TY_NONE && !ms_ty_is(t, result, MS_BI_SELF) && mentions_self(t, result);
}

/* ---- an operation's own type variables ---- */

/* The variables `method` declares for itself, named `Interface/operation/T`. A name the interface
 * or the operation already has is reported, and still declared. */
static MsTy *declare_operation_variables(MsResolver *r, MsTy contract, const MsMethod *method) {
    MsCheck *c = r->c;
    const MsTypeParams *params = &method->func.type_params;
    MsTy *vars = MS_NEW_N(&c->arena, MsTy, params->len);
    const MsStr owner = ms_name(c->names, c->tys.id[contract]);
    const MsStr operation = ms_name(c->names, method->func.name);
    for (uint32_t i = 0; i < params->len; i++) {
        const MsStr name = ms_name(c->names, params->ptr[i]->name);
        if (ms_type_scope_has(r->scope, params->ptr[i]->name)) {
            report_type_error(r, params->ptr[i]->pos,
                              ms_arena_fmt(&c->arena,
                                           "type parameter %.*s shadows a type parameter of the receiver; choose a "
                                           "different name",
                                           (int)name.len, name.ptr));
        }
        const MsStr id = ms_arena_fmt(&c->arena, "%.*s/%.*s/%.*s", (int)owner.len, owner.ptr, (int)operation.len,
                                      operation.ptr, (int)name.len, name.ptr);
        const MsTyDesc desc = {.name = params->ptr[i]->name, .id = ms_intern(c->names, id.ptr, id.len), .kind = MS_K_VARIABLE};
        vars[i] = ms_ty_fresh(&c->tys, &desc);
        MsTypeScope *own = MS_NEW(&c->arena, MsTypeScope);
        MsSym *names = MS_NEW(&c->arena, MsSym);
        *names = params->ptr[i]->name;
        *own = (MsTypeScope){.parent = r->scope, .names = names, .types = &vars[i], .len = 1};
        r->scope = own;
    }
    return vars;
}

/* ---- one interface ---- */

static void check_duplicate_operation(MsResolver *r, const MsDecl *iface, uint32_t index) {
    const MsMethod *method = iface->u.iface.methods.ptr[index];
    for (uint32_t k = 0; k < index; k++) {
        if (iface->u.iface.methods.ptr[k]->func.name == method->func.name) {
            const MsStr name = ms_name(r->c->names, method->func.name);
            report_type_error(r, method->pos,
                              ms_arena_fmt(&r->c->arena, "duplicate operation %.*s; rename or remove one of them",
                                           (int)name.len, name.ptr));
            return;
        }
    }
}

static MsOperation resolve_operation(MsResolver *r, const MsDecl *iface, MsSymId sym, uint32_t index) {
    MsCheck *c = r->c;
    const MsMethod *method = iface->u.iface.methods.ptr[index];
    const MsTy contract = c->syms.ty[sym];
    check_duplicate_operation(r, iface, index);
    uint32_t ninterface = 0;
    const MsTy *interface_vars = ms_sym_vars(c, sym, &ninterface);
    const MsTypeScope *interface_scope = ms_variable_scope(c, interface_vars, ninterface);
    const MsTy self = ms_self_variable(c, contract);
    MsTypeScope self_scope = {.parent = interface_scope, .names = (MsSym[]){c->tys.name[self]}, .types = &self, .len = 1};
    const MsTypeScope *outer = r->scope;
    r->scope = &self_scope;
    const MsTypeScope *without_own = r->scope;
    MsTy *own = declare_operation_variables(r, contract, method);
    ms_resolve_type_bounds(r, &method->func.type_params, own);
    const MsTypeScope *with_own = r->scope;
    r->scope = without_own;
    ms_resolve_type_defaults(r, &method->func.type_params, own);
    r->scope = with_own;
    const MsTy signature = ms_resolve_signature(r, &method->func.params, method->func.result);
    if (self_misplaced(&c->tys, signature)) {
        report_type_error(r, method->pos,
                          ms_arena_fmt(&c->arena,
                                       "Self can only be a whole parameter or result type of an interface operation; "
                                       "write 'other: Self', not 'List[Self]'"));
    }
    r->scope = outer;
    return (MsOperation){.name = method->func.name,
                         .ty = signature,
                         .decl = method,
                         .vars = own,
                         .nvars = method->func.type_params.len};
}

/* The symbol `d` declared in the module, unless a duplicate name took its place. */
static MsSymId own_symbol(const MsCheck *c, MsModId module, const MsDecl *d) {
    const MsSymId sym = ms_map_get(&c->mods[module].names, ms_decl_name(d));
    return sym != MS_NONE && c->syms.decl[sym] == d ? sym : MS_NONE;
}

static void mark_operations_done(MsMethodTable *table, MsModId module) {
    if (module >= table->done_cap) {
        const uint32_t cap = ms_capacity_for(table->done_cap, module + 1);
        table->operations_done = ms_array_resize(table->operations_done, cap, sizeof *table->operations_done);
        memset(table->operations_done + table->done_cap, 0, (size_t)(cap - table->done_cap));
        table->done_cap = cap;
    }
    table->operations_done[module] = 1;
}

void ms_module_ensure_operations(MsCheck *c, MsModId module, MsMethodTable *table) {
    if (module < table->done_cap && table->operations_done[module] != 0) {
        return;
    }
    ms_module_resolve_types(c, module);
    ms_module_resolve_operations(c, module, table);
}

void ms_module_resolve_operations(MsCheck *c, MsModId module, MsMethodTable *table) {
    mark_operations_done(table, module);
    const MsModule *syntax = c->mods[module].syntax;
    MsResolver resolver = {.c = c, .module = module, .refs = c->mods[module].facts->type_ref_ty};
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        const MsSymId sym = d->kind == MS_D_INTERFACE ? own_symbol(c, module, d) : MS_NONE;
        if (sym == MS_NONE) {
            continue;
        }
        for (uint32_t k = 0; k < d->u.iface.methods.len; k++) {
            const MsOperation op = resolve_operation(&resolver, d, sym, k);
            add_operation(operations_of(table, sym), op);
        }
    }
    free(resolver.aliases);
}
