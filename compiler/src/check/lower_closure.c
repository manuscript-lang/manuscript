/* Function values and lambdas: a function type is a closure object, a named function used as a
 * value is a closure with no captures that forwards to it, and a lambda is a closure function
 * whose environment holds the outer locals it reads (copies of scalars only for now). The closure
 * function is added when the lambda is met and lowered after the function that made it. */
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/mir_analysis.h"
#include "ms/walk.h"

#define LB_MAX_FN_PARAMS 16
#define LB_MAX_CAPTURES 32

bool lb_is_fn(const Lb *lb, MirTy ty) {
    return ty != MIR_NONE && mir_ty_data(lb->m, mir_ty_unscoped(ty))->kind == MK_FN;
}

/* The MIR type of a checker function type: parameters that are plain values, and a scalar or
 * nothing as the result. MIR_NONE for anything else. */
MirTy lb_fn_ty(Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    const uint32_t count = tys->nparams[ty];
    const MsTyParam *params = ms_ty_params(tys, ty);
    const MsTy result = tys->result[ty];
    if (count > LB_MAX_FN_PARAMS) {
        return MIR_NONE;
    }
    const bool value = result == lb->int_ty || result == lb->float_ty || result == lb->bool_ty || result == lb->string_ty;
    if (!value && result != lb->void_ty) {
        return MIR_NONE;
    }
    MirTy mir_params[LB_MAX_FN_PARAMS];
    for (uint32_t i = 0; i < count; i++) {
        mir_params[i] = (params[i].flags & ~MS_PARAM_POSITIONAL) == 0 ? lb_mir_ty(lb, params[i].ty) : MIR_NONE;
        if (mir_params[i] == MIR_NONE) {
            return MIR_NONE;
        }
    }
    return mir_ty_fn(lb->m, mir_params, count, value ? lb_mir_ty(lb, result) : MIR_VOID, 0);
}

/* A name no function of the module has: `base`, else `base.1`, `base.2`, ... (what the Rust text
 * form prints for a name two functions share, so the text names one function each). */
MsSym lb_unique_name(Lb *lb, MsStr base) {
    for (uint32_t k = 0;; k++) {
        const MsStr text = k == 0 ? base : ms_arena_fmt(&lb->m->arena, "%.*s.%u", (int)base.len, base.ptr, k);
        const MsSym sym = mir_name(lb->m, text.ptr, text.len);
        bool taken = false;
        for (uint32_t i = 0; i < lb->m->nfuncs && !taken; i++) {
            taken = lb->m->funcs[i].name == sym;
        }
        if (!taken) {
            return sym;
        }
    }
}

/* A function value's closure parameters: the environment pointer, then the visible ones. */
static MirParam *lb_closure_params(Lb *lb, const MirTyData *fn) {
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, (size_t)fn->nargs + 1);
    params[0] = (MirParam){MIR_PTR, MM_BORROW};
    for (uint32_t i = 0; i < fn->nargs; i++) {
        params[i + 1] = (MirParam){fn->args[i], MM_BORROW};
    }
    return params;
}

/* ---- named functions as values ---- */

/* The closure function that forwards its parameters to module function `func`. */
static uint32_t lb_thunk(Lb *lb, uint32_t func) {
    const MirFunc *callee = &lb->m->funcs[func];
    const uint32_t count = callee->nparams;
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, (size_t)count + 1);
    params[0] = (MirParam){MIR_PTR, MM_BORROW};
    memcpy(params + 1, callee->params, (size_t)count * sizeof *params);
    const MirTy ret = callee->ret;
    MirBuilder b;
    mir_b_init(&b, lb->m, lb_unique_name(lb, ms_name(&lb->m->names, callee->name)), params, count + 1, ret);
    b.f.kind = MFK_CLOSURE;
    MirValue *values = MS_NEW_N(&b.scratch, MirValue, (size_t)count + 1);
    mir_b_params(&b, values, count + 1);
    const MirValue result = mir_b_call(&b, func, values + 1, count);
    if (ret == MIR_STR && callee->ret_borrowed) { // the caller of a function value owns its String result
        const MirImm one = {.tag = MI_INT, .i = 1};
        mir_b_ret(&b, mir_b_emit(&b, MOP_Clone, &result, 1, one, ret));
    } else {
        mir_b_ret(&b, ret == MIR_VOID ? mir_b_unit(&b) : result);
    }
    MirFunc f = {0};
    if (!mir_b_into_func(&b, &f)) {
        return MIR_NONE;
    }
    return mir_add_func(lb->m, &f);
}

/* A module function named as a value. */
LbVal lb_function_value(Lb *lb, const MsExpr *e) {
    const uint32_t sym = lb->facts->res_ref[e->id];
    const uint32_t func = sym < lb->c->syms.count ? lb->func_of[sym] : MIR_NONE;
    const MirTy fty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    if (func == MIR_NONE || !lb_is_fn(lb, fty)) {
        return lb_unsupported(lb);
    }
    if (lb->thunk_of[sym] == MIR_NONE) {
        lb->thunk_of[sym] = lb_thunk(lb, func);
    }
    if (lb->thunk_of[sym] == MIR_NONE) {
        return lb_unsupported(lb);
    }
    const MirImm target = {.tag = MI_FUNC, .a = lb->thunk_of[sym]};
    return (LbVal){mir_b_emit(&lb->b, MOP_ClosureNew, NULL, 0, target, fty), true};
}

/* ---- calls through a function value ---- */

LbVal lb_call_value(Lb *lb, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    if (callee->kind != MS_E_NAME || lb->facts->res_kind[callee->id] != MS_RES_BINDING) {
        return lb_unsupported(lb);
    }
    const MirTy fty = lb_mir_ty(lb, lb->facts->bindings.ty[lb->facts->res_ref[callee->id]]);
    const uint32_t count = e->u.call.args.len;
    if (!lb_is_fn(lb, fty) || mir_ty_data(lb->m, mir_ty_unscoped(fty))->nargs != count) {
        return lb_unsupported(lb);
    }
    MirValue *args = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 1);
    MirValue *temps = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 1);
    uint32_t ntemps = 0;
    args[0] = lb_expr(lb, callee).v;
    for (uint32_t i = 0; i < count && lb->ok; i++) {
        if (e->u.call.args.ptr[i].has_name) {
            return lb_unsupported(lb);
        }
        const LbVal value = lb_expr(lb, e->u.call.args.ptr[i].value);
        args[i + 1] = value.v;
        if (value.owned) {
            temps[ntemps++] = value.v;
        }
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirTy ret = mir_ty_data(lb->m, mir_ty_unscoped(fty))->elem;
    const MirValue result = mir_b_emit(&lb->b, MOP_CallInd, args, count + 1, (MirImm){0}, ret);
    for (uint32_t i = 0; i < ntemps; i++) {
        lb_drop(lb, temps[i]);
    }
    return (LbVal){result, ret == MIR_STR}; // a String result is the caller's
}

/* ---- lambdas ---- */

typedef struct LbCaptures {
    const Lb *lb;
    uint32_t first;  /* the bindings below it belong to the code around the lambda */
    uint32_t caps[LB_MAX_CAPTURES];
    uint32_t count;
    bool overflow;
} LbCaptures;

static void lb_note_capture(void *ctx, const MsExpr *e) {
    LbCaptures *found = ctx;
    if (e->kind != MS_E_NAME || found->lb->facts->res_kind[e->id] != MS_RES_BINDING) {
        return;
    }
    const uint32_t binding = found->lb->facts->res_ref[e->id];
    if (binding >= found->first) {
        return;
    }
    for (uint32_t i = 0; i < found->count; i++) {
        if (found->caps[i] == binding) {
            return;
        }
    }
    if (found->count == LB_MAX_CAPTURES) {
        found->overflow = true;
        return;
    }
    found->caps[found->count++] = binding;
}

/* Whether the lambda's own parameters are plain values with no default. */
static bool lb_lambda_params_plain(const MsExpr *e) {
    const MsParams *params = &e->u.lambda.params;
    for (uint32_t i = 0; i < params->len; i++) {
        const MsParam *p = params->ptr[i];
        if (p->def != NULL || p->is_mutable || p->moving) {
            return false;
        }
    }
    return true;
}

/* Adds the closure function with an empty body and queues it. Returns its index, or MIR_NONE. */
static uint32_t lb_add_closure(Lb *lb, const MsExpr *e, const MirTyData *fn, const LbCaptures *found,
                               MirTy *cap_tys, bool *by_ref) {
    const MsStr outer = ms_name(&lb->m->names, lb->b.f.name);
    const MsStr name = ms_arena_fmt(&lb->m->arena, "%.*s.closure", (int)outer.len, outer.ptr);
    MirFunc stub = {0};
    mir_func_init(lb->m, &stub, lb_unique_name(lb, name), lb_closure_params(lb, fn), fn->nargs + 1,
                  fn->elem);
    stub.kind = MFK_CLOSURE;
    stub.captures = cap_tys;
    stub.ncaptures = found->count;
    stub.keeps_scoped = lb->b.f.keeps_scoped; // a closure made inside what keeps scoped closures keeps them
    const uint32_t func = mir_add_func(lb->m, &stub);
    LbJob job = {.lambda = e, .func = func, .ncaps = found->count, .by_ref = by_ref};
    lb->m->funcs[func].scoped = false;
    for (uint32_t i = 0; i < found->count; i++) {
        lb->m->funcs[func].scoped = lb->m->funcs[func].scoped || by_ref[i]; // the environment points into this frame
    }
    job.caps = MS_NEW_N(&lb->m->arena, uint32_t, (size_t)found->count + 1);
    memcpy(job.caps, found->caps, (size_t)found->count * sizeof *job.caps);
    MIR_PUSH(lb->m, lb->jobs, lb->njobs, lb->cjobs, LbJob, job);
    return func;
}

LbVal lb_lambda(Lb *lb, const MsExpr *e) {
    const MirTy fty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    if (!lb_is_fn(lb, fty) || !lb_lambda_params_plain(e)) {
        return lb_unsupported(lb);
    }
    const MirTyData *fn = mir_ty_data(lb->m, mir_ty_unscoped(fty));
    LbCaptures found = {.lb = lb, .first = lb->facts->lambda_first[e->id]};
    const MsVisitor visitor = {.ctx = &found, .expr = lb_note_capture};
    ms_walk_callable(&visitor, e->u.lambda.params, e->u.lambda.body);
    // the environment lists the captures in the order the locals were declared
    for (uint32_t i = 1; i < found.count; i++) {
        for (uint32_t j = i; j > 0 && found.caps[j - 1] > found.caps[j]; j--) {
            const uint32_t held = found.caps[j];
            found.caps[j] = found.caps[j - 1];
            found.caps[j - 1] = held;
        }
    }
    MirTy *cap_tys = MS_NEW_N(&lb->m->arena, MirTy, (size_t)found.count + 1);
    bool *by_ref = MS_NEW_N(&lb->m->arena, bool, (size_t)found.count + 1);
    MirValue *values = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)found.count + 1);
    for (uint32_t i = 0; i < found.count && !found.overflow; i++) {
        const uint32_t binding = found.caps[i];
        const MirTy ty = lb_mir_ty(lb, lb->facts->bindings.ty[binding]);
        values[i] = lb->value_of[binding];
        // a `var` is shared with its maker; a value that is dropped stays where it lives
        by_ref[i] = ty != MIR_NONE && lb_owns(lb, ty);
        cap_tys[i] = by_ref[i] ? MIR_PTR : ty;
        found.overflow = !(by_ref[i] || lb_is_scalar(ty)) || lb->var_of[binding] != MIR_NONE || values[i] == MIR_NONE;
        if (by_ref[i] && !found.overflow) {
            const MirImm slot_ty = {.tag = MI_TY, .a = ty};
            const MirValue slot = mir_b_emit(&lb->b, MOP_Slot, NULL, 0, slot_ty, MIR_PTR);
            lb_store(lb, slot, values[i]);
            values[i] = slot;
        }
    }
    if (found.overflow || fn->nargs != e->u.lambda.params.len) {
        return lb_unsupported(lb);
    }
    const uint32_t func = lb_add_closure(lb, e, fn, &found, cap_tys, by_ref);
    const MirImm target = {.tag = MI_FUNC, .a = func};
    return (LbVal){mir_b_emit(&lb->b, MOP_ClosureNew, values, found.count, target, fty), true};
}

/* Lowers the body of a queued lambda over its stub. */
static bool lb_lambda_body(Lb *lb, const LbJob job) {
    const MsExpr *e = job.lambda;
    const MirFunc stub = lb->m->funcs[job.func];
    mir_b_init(&lb->b, lb->m, stub.name, stub.params, stub.nparams, stub.ret);
    lb->b.f.loc = lb_loc(lb, e->pos);
    lb->b.f.kind = MFK_CLOSURE;
    lb->b.f.captures = stub.captures;
    lb->b.f.ncaptures = stub.ncaptures;
    lb->b.f.keeps_scoped = stub.keeps_scoped;
    lb->b.f.scoped = stub.scoped;
    MirValue *values = MS_NEW_N(&lb->m->arena, MirValue, (size_t)stub.nparams + 1);
    mir_b_params(&lb->b, values, stub.nparams);
    MirValue *caps = MS_NEW_N(&lb->m->arena, MirValue, (size_t)job.ncaps + 1);
    for (uint32_t i = 0; i < job.ncaps; i++) {
        const MirImm index = {.tag = MI_IDX, .a = i};
        caps[i] = mir_b_emit(&lb->b, MOP_ClosureCap, &values[0], 1, index, stub.captures[i]);
    }
    for (uint32_t i = 0; i < job.ncaps; i++) { // a pointer capture is read where the body starts
        const MirTy ty = lb_mir_ty(lb, lb->facts->bindings.ty[job.caps[i]]);
        lb->value_of[job.caps[i]] = job.by_ref[i] ? lb_load(lb, caps[i], ty) : caps[i];
    }
    for (uint32_t i = 0; i < e->u.lambda.params.len; i++) {
        lb->value_of[lb->binding_at[e->u.lambda.params.ptr[i]->id]] = values[i + 1];
    }
    lb->closure = true;
    lb->ok = true;
    lb_reset_state(lb);
    lb_statements(lb, &e->u.lambda.body);
    if (lb->ok && !lb->dead && lb->b.f.ret == MIR_VOID) {
        lb_return_void(lb);
    }
    lb->ok = lb->ok && lb->dead;
    if (lb->ok) {
        lc_check(lb);
    }
    MirFunc f = {0};
    if (lb->ok) {
        mir_func_compact_blocks(&lb->b.f);
    }
    const bool built = mir_b_into_func(&lb->b, &f);
    if (lb->ok && built) {
        lb->m->funcs[job.func] = f;
    }
    return lb->ok && built;
}

bool lb_closures(Lb *lb, bool ok) {
    for (uint32_t i = 0; i < lb->njobs && ok; i++) { // a closure body may queue more
        ok = lb_lambda_body(lb, lb->jobs[i]);
    }
    lb->njobs = 0;
    lb->closure = false;
    return ok;
}
