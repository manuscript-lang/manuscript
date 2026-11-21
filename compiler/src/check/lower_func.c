/* The per-function driver of the lowering: the signature of a function or method, its stub in the
 * module, starting and finishing a body, and the pass over a module (`ms_lower_module`) that repeats
 * without the functions that failed. Expressions and statements are lower_body.c's. */
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/lower.h"
#include "ms/mir_analysis.h"
#include "ms/mir_builder.h"
#include "ms/lower_scope.h"

static LbCallable lb_function_callable(Lb *lb, const MsDecl *d, MsSymId sym) {
    const MsStr name = ms_name(lb->c->names, d->u.fn.name);
    return (LbCallable){.fn = &d->u.fn,
                        .node = d->id,
                        .pos = d->pos,
                        .name = mir_name(lb->m, name.ptr, name.len),
                        .sig = lb->c->syms.ty[sym],
                        .self_ty = MS_TY_NONE};
}

/* The function's MIR signature into `params` (one per source parameter) and `ret`; false when a
 * parameter or the result is not a type this pass handles. */
static bool lb_signature(Lb *lb, const LbCallable *c, MirParam *params, MirTy *ret) {
    const MsTyParam *sig_params = ms_ty_params(&lb->c->tys, c->sig);
    const MsTy result = lb->c->tys.result[c->sig];
    *ret = result == lb->void_ty ? MIR_VOID : lb_mir_ty(lb, result);
    for (uint32_t i = 0; i < lb_slots(c); i++) {
        const uint32_t first = lb_has_self(c) ? 1u : 0u;
        const MsTy source = i < first ? c->self_ty : sig_params[i - first].ty;
        const MirTy ty = lb_mir_ty(lb, source);
        const bool moving = lb_param_moves(lb, c, i);
        const bool mutable_slot = lb_slot_mutable(c, i);
        if (ty == MIR_NONE || (moving && !lb_owns(lb, ty)) || (mutable_slot && lb_is_fn(lb, ty))) { // only a String is handed over so far
            return false;
        }
        params[i] = (MirParam){mutable_slot ? MIR_PTR : ty, moving ? MM_MOVE : MM_BORROW};
    }
    return *ret != MIR_NONE;
}

/* The indexes of the `var` parameters, which no other memory overlaps (the text form's `noalias`). */
static void lb_mark_noalias(Lb *lb, const LbCallable *c) {
    uint32_t count = 0;
    for (uint32_t i = 0; i < lb_slots(c); i++) {
        count += lb_slot_mutable(c, i) ? 1 : 0;
    }
    if (count == 0) {
        return;
    }
    uint32_t *indexes = MS_NEW_N(&lb->m->arena, uint32_t, count);
    uint32_t next = 0;
    for (uint32_t i = 0; i < lb_slots(c); i++) {
        if (lb_slot_mutable(c, i)) {
            indexes[next++] = i;
        }
    }
    lb->b.f.noalias = indexes;
    lb->b.f.nnoalias = count;
}

static MsSym lb_slot_name(const Lb *lb, const LbCallable *c, uint32_t slot) {
    const MsParam *param = lb_slot_param(c, slot);
    return param == NULL ? ms_intern_cstr(lb->c->names, "self") : param->name;
}

/* Starts the function and binds its parameters; false when its signature is not handled. */
static bool lb_begin(Lb *lb, const LbCallable *c) {
    const uint32_t slots = lb_slots(c);
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, slots + 1);
    MirTy ret = MIR_NONE;
    if (!lb_signature(lb, c, params, &ret)) {
        return false;
    }
    mir_b_init(&lb->b, lb->m, lb->has_override ? lb->name_override : c->name, params, slots, ret);
    lb->b.f.loc = lb_loc(lb, c->pos);
    lb->b.f.ret_borrowed = lb->facts->ret_borrowed[c->node]; // every result is a reference into the arguments
    lb_mark_noalias(lb, c);
    MirValue *values = MS_NEW_N(&lb->m->arena, MirValue, slots + 1);
    mir_b_params(&lb->b, values, slots);
    for (uint32_t i = 0; i < slots; i++) {
        const uint32_t binding = lb->binding_at[lb_slot_node(c, i)];
        lb->value_of[binding] = values[i];
        if (!lb_slot_mutable(c, i)) { // Rust names no `var` parameter: its value is a pointer
            lb_name_value(lb, values[i], lb_slot_name(lb, c, i), true);
        }
    }
    lb_depth(lb, MOP_DepthEnter);
    for (uint32_t i = 0; i < slots; i++) {
        if (lb_slot_mutable(c, i)) {
            const uint32_t binding = lb->binding_at[lb_slot_node(c, i)];
            const MirTy ty = lb_mir_ty(lb, lb->facts->bindings.ty[binding]);
            lb->var_of[binding] = mir_b_declare_var(&lb->b, ty, MM_BORROW);
            mir_b_def_var(&lb->b, lb->var_of[binding], lb_load(lb, values[i], ty));
        }
    }
    return true;
}

/* The state of a body about to be lowered: its builder is started and `lb->decl` is set. */
void lb_reset_state(Lb *lb) {
    lb->dead = false;
    lb->loop = NULL;
    lb->stmt = NULL;
    lscope_init(&lb->scopes, &lb->b);
    lb->vars = NULL; // the arena they live in is freed between passes
    lb->nvars = lb->cvars = 0;
    lb->temps = NULL;
    lb->ntemps = lb->ctemps = lb->stmt_mark = lb->branching = 0;
    (void)lscope_push(&lb->scopes); // the body's own scope: depth 0
}

/* Lowers one checked function over its stub `slot` in the module; false when it is not handled. */
bool lb_function(Lb *lb, const LbCallable *c, uint32_t slot) {
    lb->cur = *c;
    lb->closure = false;
    lb->jobs = NULL; // the arena they live in is freed between passes
    lb->njobs = lb->cjobs = 0;
    lb->ok = lb_begin(lb, c);
    if (!lb->ok) {
        return false;
    }
    lb_reset_state(lb);
    for (uint32_t i = 0; i < lb_slots(c); i++) {
        if (lb_param_moves(lb, c, i)) { // the function owns what it was handed
            lscope_own(&lb->scopes, lb->value_of[lb->binding_at[lb_slot_node(c, i)]], 0);
        }
    }
    lb_statements(lb, &c->fn->body);
    if (lb->ok && !lb->dead && lb->b.f.ret == MIR_VOID) {
        lb_return_void(lb); // the end of a function that returns nothing
    }
    lb->ok = lb->ok && lb->dead;
    MirFunc f = {0};
    if (lb->ok) {
        mir_func_compact_blocks(&lb->b.f); // unreachable blocks go; the rest in reverse post-order
        const MsStr name = ms_name(lb->c->names, c->fn->name);
        const bool is_main = !lb_has_self(c) && name.len == 4 && memcmp(name.ptr, "main", 4) == 0;
        if (is_main && lb->b.f.ret == MIR_INT) { // any other `main` gets a wrapper, which is the export
            lb->b.f.linkage = ML_EXPORT;
        }
    }
    // Finishing also frees the builder's scratch tables, which a failed function needs too.
    const bool built = mir_b_into_func(&lb->b, &f);
    if (lb->ok && built) {
        lb->m->funcs[slot] = f;
    }
    return lb_closures(lb, lb->ok && built); // the lambdas it made are lowered after it
}

static void lb_index_bindings(Lb *lb, MsArena *arena) {
    const MsBindings *bindings = &lb->facts->bindings;
    const size_t nodes = (size_t)lb->facts->node_count + 1;
    lb->binding_at = MS_NEW_N(arena, uint32_t, nodes);
    memset(lb->binding_at, 0xff, nodes * sizeof *lb->binding_at);
    for (uint32_t i = 0; i < bindings->count; i++) {
        lb->binding_at[bindings->decl_node[i]] = i;
    }
    lb->type_of = MS_NEW_N(arena, MirTy, lb->c->tys.count + 1);
    memset(lb->type_of, 0xff, (lb->c->tys.count + 1) * sizeof *lb->type_of);
    lb->value_of = MS_NEW_N(arena, MirValue, bindings->count + 1);
    lb->var_of = MS_NEW_N(arena, MirVar, bindings->count + 1);
    memset(lb->var_of, 0xff, (bindings->count + 1) * sizeof *lb->var_of);
    memset(lb->value_of, 0xff, (bindings->count + 1) * sizeof *lb->value_of);
}

/* Adds a function with the declared signature and an empty body, so calls can name it before its
 * body is lowered (recursion and any order of declarations). */
uint32_t lb_add_stub(Lb *lb, const LbCallable *c) {
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, lb_slots(c) + 1);
    MirTy ret = MIR_NONE;
    if (!lb_signature(lb, c, params, &ret)) {
        return MIR_NONE;
    }
    MirFunc stub = {0};
    mir_func_init(lb->m, &stub, lb->has_override ? lb->name_override : c->name, params, lb_slots(c), ret);
    stub.ret_borrowed = lb->facts->ret_borrowed[c->node]; // callers read it before the body is lowered
    return mir_add_func(lb->m, &stub);
}

/* ---- generic instances ---- */

static LbInst *lb_find_inst(LbInst *list, uint32_t n, MsSymId sym, const MsTy *args, uint32_t nargs) {
    for (uint32_t i = 0; i < n; i++) {
        if (list[i].sym == sym && list[i].nargs == nargs && memcmp(list[i].args, args, nargs * sizeof *args) == 0) {
            return &list[i];
        }
    }
    return NULL;
}

static bool lb_push_inst(LbInst **list, uint32_t *n, uint32_t *cap, const LbInst *inst) {
    if (*n == *cap) {
        const uint32_t grown = *cap == 0 ? 8 : *cap * 2;
        LbInst *bigger = realloc(*list, (size_t)grown * sizeof **list);
        if (bigger == NULL) {
            return false;
        }
        *list = bigger;
        *cap = grown;
    }
    (*list)[(*n)++] = *inst;
    return true;
}

/* The copy of the generic function `sym` for `args`, created (with its signature and an empty body)
 * on first use; MIR_NONE when its signature is not handled or it failed before. Copies are named
 * `name`, `name.1`, `name.2`, ... in the order they are created. Their bodies are lowered by
 * `lb_drain_instances` once the module's own functions are. */
static uint32_t lb_instance(Lb *lb, MsSymId sym, const MsTy *args, uint32_t nargs) {
    if (lb_find_inst(lb->dead_insts, lb->ndead_insts, sym, args, nargs) != NULL) {
        return MIR_NONE;
    }
    const LbInst *known = lb_find_inst(lb->insts, lb->ninsts, sym, args, nargs);
    if (known != NULL) {
        return known->func;
    }
    LbInst inst = {.sym = sym, .nargs = nargs, .func = MIR_NONE};
    memcpy(inst.args, args, nargs * sizeof *args);
    const MsDecl *d = lb->c->syms.decl[sym];
    const MsDef *def = ms_def(lb->mut, sym);
    if (d == NULL || d->kind != MS_D_FN || def == NULL || def->nvars != nargs || !lb->facts->body_checked[d->id]) {
        (void)lb_push_inst(&lb->dead_insts, &lb->ndead_insts, &lb->cdead_insts, &inst);
        return MIR_NONE;
    }
    uint32_t serial = 0;
    for (uint32_t i = 0; i < lb->ninsts; i++) {
        serial += lb->insts[i].sym == sym ? 1 : 0;
    }
    const MsStr base = ms_name(lb->c->names, d->u.fn.name);
    char *text = MS_NEW_N(&lb->m->arena, char, base.len + 16);
    const int len = serial == 0 ? snprintf(text, base.len + 16, "%.*s", (int)base.len, base.ptr)
                                : snprintf(text, base.len + 16, "%.*s.%u", (int)base.len, base.ptr, serial);
    const MsTy *saved_vars = lb->sub_vars, *saved_args = lb->sub_args;
    const uint32_t saved_n = lb->nsub;
    const bool saved_override = lb->has_override;
    const MsSym saved_name = lb->name_override;
    lb->sub_vars = def->vars;
    lb->sub_args = inst.args;
    lb->nsub = nargs;
    lb->has_override = true;
    lb->name_override = mir_name(lb->m, text, (size_t)len);
    const LbCallable callable = lb_function_callable(lb, d, sym);
    inst.func = lb_add_stub(lb, &callable);
    lb->sub_vars = saved_vars;
    lb->sub_args = saved_args;
    lb->nsub = saved_n;
    lb->has_override = saved_override;
    lb->name_override = saved_name;
    if (inst.func == MIR_NONE) {
        (void)lb_push_inst(&lb->dead_insts, &lb->ndead_insts, &lb->cdead_insts, &inst);
        return MIR_NONE;
    }
    if (!lb_push_inst(&lb->insts, &lb->ninsts, &lb->cinsts, &inst)) {
        lb->ok = false;
        return MIR_NONE;
    }
    return inst.func;
}

/* Lowers the body of every copy created so far, and those the bodies create in turn. A copy that
 * does not lower is remembered as dead: the next pass makes its callers fail. True when one died. */
static bool lb_drain_instances(Lb *lb, uint32_t *lowered) {
    bool died = false;
    for (uint32_t i = 0; i < lb->ninsts; i++) {
        const LbInst inst = lb->insts[i]; // the list may grow while the body is lowered
        lb->sub_vars = ms_def(lb->mut, inst.sym)->vars;
        lb->sub_args = inst.args;
        lb->nsub = inst.nargs;
        lb->has_override = true;
        lb->name_override = lb->m->funcs[inst.func].name;
        const LbCallable callable = lb_function_callable(lb, lb->c->syms.decl[inst.sym], inst.sym);
        const bool done = lb_function(lb, &callable, inst.func);
        *lowered += done ? 1 : 0;
        if (!done) {
            died = lb_push_inst(&lb->dead_insts, &lb->ndead_insts, &lb->cdead_insts, &inst) || died;
        }
    }
    lb->nsub = 0;
    lb->has_override = false;
    return died;
}

/* Whether the checker reported anything on the lines [first, end). A program with a diagnostic
 * does not build, so a function holding one is not lowered (its body may be ill-typed). */
bool lb_lines_have_diagnostic(const MsModuleRow *row, uint32_t first, uint32_t end) {
    for (uint32_t k = 0; k < row->ndiags; k++) {
        const uint32_t line = row->diags[k].diag.pos.line;
        if (line >= first && line < end) {
            return true;
        }
    }
    return false;
}

/* Whether the checker reported anything inside declaration `index`: on lines from its own to the
 * next declaration's. */
static bool lb_has_diagnostic(const MsModuleRow *row, uint32_t index) {
    const uint32_t end = index + 1 < row->syntax->ndecls ? row->syntax->decls[index + 1]->pos.line : UINT32_MAX;
    return lb_lines_have_diagnostic(row, row->syntax->decls[index]->pos.line, end);
}

/* One pass over the module's checked functions: stub each one not in `failed`, then lower them.
 * A function that does not lower is marked in `failed`; true when any new one was. */
static bool lb_pass(Lb *lb, MsModId module, uint32_t nrows, bool *failed, uint32_t *lowered) {
    const MsModuleRow *row = &lb->c->mods[module];
    const uint32_t ndecls = row->syntax->ndecls;
    memset(lb->func_of, 0xff, (size_t)lb->c->syms.count * sizeof *lb->func_of);
    memset(lb->thunk_of, 0xff, (size_t)lb->c->syms.count * sizeof *lb->thunk_of);
    MsSymId *syms = MS_NEW_N(&lb->m->arena, MsSymId, (size_t)ndecls + 1);
    for (uint32_t i = 0; i < ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        const bool checked = d->kind == MS_D_FN && lb->facts->body_checked[d->id] && !failed[i] && !lb_has_diagnostic(row, i);
        syms[i] = checked ? ms_decl_own_symbol(lb->c, module, d) : MS_NONE;
        if (syms[i] != MS_NONE && lb->c->syms.nvars[syms[i]] != 0) {
            syms[i] = MS_NONE; // a generic function is checked here but not lowered: it needs one copy per type argument
        }
        if (syms[i] != MS_NONE) {
            const LbCallable callable = lb_function_callable(lb, d, syms[i]);
            lb->func_of[syms[i]] = lb_add_stub(lb, &callable);
        }
    }
    bool *method_failed = failed + ndecls; // the methods follow the declarations
    lm_stubs(lb, module, nrows, method_failed);
    bool changed = false;
    *lowered = 0;
    lb->ninsts = 0;
    for (uint32_t i = 0; i < ndecls; i++) {
        if (syms[i] == MS_NONE) {
            continue;
        }
        const bool unlowerable = lb->func_of[syms[i]] == MIR_NONE;
        const LbCallable callable = lb_function_callable(lb, row->syntax->decls[i], syms[i]);
        const bool done = !unlowerable && lb_function(lb, &callable, lb->func_of[syms[i]]);
        failed[i] = !done;
        changed = changed || !done;
        *lowered += done ? 1 : 0;
    }
    changed = lm_lower(lb, nrows, method_failed, lowered) || changed;
    return lb_drain_instances(lb, lowered) || changed;
}

/* A failed function leaves a stub, and calls to it were lowered against it, so the pass repeats
 * without it (its callers then fail too) until a pass loses nothing. That is at most one pass per
 * function; programs lose a function or two. */
uint32_t ms_lower_module(MsCheck *c, MsModId module, MirModule *out) {
    const MsModuleRow *row = &c->mods[module];
    const MsFacts *facts = row->facts;
    if (facts == NULL || facts->body_checked == NULL) {
        return 0;
    }
    Lb lb = {.c = c,
             .mut = c,
             .facts = facts,
             .m = out,
             .int_ty = ms_check_primitive(c, "Int"),
             .float_ty = ms_check_primitive(c, "Float"),
             .bool_ty = ms_check_primitive(c, "Bool"),
             .string_ty = ms_check_primitive(c, "String"),
             .void_ty = ms_check_primitive(c, "Void")};
    lb.classifier = ms_classifier_new(c);
    ms_classifier_mark_methods(lb.classifier, facts->methods);
    const uint32_t nrows = lm_prepare(&lb, module);
    bool *failed = calloc((size_t)row->syntax->ndecls + nrows + 1, sizeof *failed);
    lb.func_of = calloc((size_t)c->syms.count + 1, sizeof *lb.func_of);
    lb.thunk_of = calloc((size_t)c->syms.count + 1, sizeof *lb.thunk_of);
    uint32_t lowered = 0;
    while (failed != NULL && lb.func_of != NULL && lb.thunk_of != NULL) {
        mir_module_free(out);
        mir_module_init(out);
        lb_index_bindings(&lb, &out->arena);
        if (!lb_pass(&lb, module, nrows, failed, &lowered)) {
            break;
        }
    }
    ms_classifier_free(lb.classifier);
    free(lb.func_of);
    free(lb.rows);
    free(lb.method_func);
    free(lb.insts);
    free(lb.dead_insts);
    free(lb.thunk_of);
    free(failed);
    return lowered;
}
