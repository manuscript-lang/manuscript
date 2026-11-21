/* Function values and closures in function bodies: a parameter or local of function type called
 * through its name, a named function used as a value, and an anonymous `fn` that captures what it
 * reads. Handled: function types whose parameters are plain primitives and whose result is a
 * primitive or `Void`; anonymous functions whose parameters and result are annotated with
 * primitives or come from the expected function type; captures that are only read (a lambda that
 * assigns a captured name is left to the Rust checker). Every other form, and every diagnostic
 * case, leaves the function to the Rust checker. */
#include <stdio.h>
#include <string.h>

#include "check/check_body.h"

/* What a function value may take or give: any type a binding can hold. */
static bool closure_value(const MsBody *b, MsTy ty) {
    return ms_body_is_bindable(b, ty);
}

bool ms_body_is_function_value(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    if (ty == MS_TY_NONE || ms_ty_kind(tys, ty) != MS_K_FUNCTION || tys->nparams[ty] > 16) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, ty);
    for (uint32_t i = 0; i < tys->nparams[ty]; i++) {
        if ((params[i].flags & ~(MS_PARAM_POSITIONAL | MS_PARAM_MOVE)) != 0 || !closure_value(b, params[i].ty)) {
            return false;
        }
    }
    return closure_value(b, tys->result[ty]) || tys->result[ty] == b->void_ty;
}

/* A function value whose parameters are plain values and whose result is any bindable type: the only ones a
 * lambda is checked for. A parameter of another type is owned or borrowed by the function type's mode, which the
 * ownership walk does not model for a lambda's own parameters yet. */
static bool closure_plain(const MsBody *b, MsTy fn) {
    const MsTyTable *tys = &b->c->tys;
    if (!ms_body_is_function_value(b, fn)) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, fn);
    for (uint32_t i = 0; i < tys->nparams[fn]; i++) {
        if ((params[i].flags & ~MS_PARAM_POSITIONAL) != 0 || !ms_body_is_plain_value(b, params[i].ty)) {
            return false;
        }
    }
    return ms_body_is_bindable(b, tys->result[fn]) || tys->result[fn] == b->void_ty;
}

/* The name a function type's parameter `index` carries: `_0`, `_1`, as the parser spells them. */
static MsSym closure_slot_name(MsBody *b, uint32_t index) {
    char text[16];
    (void)snprintf(text, sizeof text, "_%u", index);
    return ms_intern_cstr(b->c->names, text);
}

/* The function type with every parameter positional: the type of a function used as a value. */
static MsTy closure_positional(MsBody *b, MsTy sig) {
    MsTyTable *tys = &b->c->tys;
    const uint32_t count = tys->nparams[sig];
    MsTyParam *params = MS_NEW_N(&b->c->arena, MsTyParam, count == 0 ? 1 : count);
    memcpy(params, ms_ty_params(tys, sig), (size_t)count * sizeof *params);
    for (uint32_t i = 0; i < count; i++) {
        params[i].flags |= MS_PARAM_POSITIONAL;
        params[i].name = closure_slot_name(b, i);
    }
    const MsTyDesc desc = {.name = tys->name[sig],
                           .id = tys->id[sig],
                           .kind = MS_K_FUNCTION,
                           .params = params,
                           .nparams = count,
                           .result = tys->result[sig]};
    return ms_ty_intern(tys, &desc);
}

/* `callee(args)` where `callee` names a binding of function type: positional arguments of the
 * parameter types. */
MsTy ms_body_call_value(MsBody *b, const MsExpr *e, uint32_t binding) {
    const MsTy fn = b->facts->bindings.ty[binding];
    const MsExpr *callee = e->u.call.callee;
    const MsTyTable *tys = &b->c->tys;
    if (!ms_body_is_function_value(b, fn) || tys->nparams[fn] != e->u.call.args.len ||
        ms_body_expr(b, callee, fn) == MS_TY_NONE) {
        return ms_body_unsupported(b);
    }
    const MsTyParam *params = ms_ty_params(tys, fn);
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsArg *arg = &e->u.call.args.ptr[i];
        if (arg->has_name || ms_body_expr(b, arg->value, params[i].ty) == MS_TY_NONE) {
            return ms_body_unsupported(b);
        }
    }
    return ms_body_has_invalid(b, tys->result[fn]) ? b->invalid_ty : tys->result[fn];
}

/* A module function named as a value. */
MsTy ms_body_function_name(MsBody *b, const MsExpr *e) {
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, e->u.sym);
    const MsSyms *syms = &b->c->syms;
    if (sym == MS_NONE || syms->kind[sym] != MS_SYM_FN || syms->module[sym] != b->module ||
        syms->decl[sym] == NULL || syms->nvars[sym] != 0 || syms->decl[sym]->kind != MS_D_FN ||
        syms->decl[sym]->u.fn.external || !ms_body_is_function_value(b, syms->ty[sym])) {
        return ms_body_unsupported(b);
    }
    const MsFunc *fn = &syms->decl[sym]->u.fn;
    for (uint32_t i = 0; i < fn->params.len; i++) {
        if (fn->params.ptr[i]->def != NULL) {
            return ms_body_unsupported(b); /* a copy keeps the defaults: not modeled yet */
        }
    }
    b->facts->res_kind[e->id] = MS_RES_SYMBOL;
    b->facts->res_ref[e->id] = sym;
    return closure_positional(b, syms->ty[sym]);
}

/* The type a written primitive annotation names, else the expected one; MS_TY_NONE and giving up
 * when neither exists or they differ. */
static MsTy closure_declared(MsBody *b, const MsTypeRef *written, MsTy expected) {
    if (written == NULL) {
        return expected != MS_TY_NONE ? expected : ms_body_unsupported(b);
    }
    const MsTy ty = ms_body_annotation(b, written);
    return ty != MS_TY_NONE && (expected == MS_TY_NONE || expected == ty) ? ty : ms_body_unsupported(b);
}

/* The result a lambda writes: `Void` or any type a parameter may have. */
static MsTy closure_result(MsBody *b, const MsTypeRef *written, MsTy expected) {
    if (written != NULL && written->kind == MS_TYPE_NAMED && written->args.len == 0) {
        const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, written->name);
        if (sym != MS_NONE && b->c->syms.ty[sym] == b->void_ty && (expected == MS_TY_NONE || expected == b->void_ty)) {
            b->facts->type_ref_ty[written->id] = b->void_ty;
            return b->void_ty;
        }
    }
    return closure_declared(b, written, expected);
}

/* `open_result`: the expected result still holds variables a written result decides, so it is not
 * the context the written one is checked against. */
static MsTy closure_signature(MsBody *b, const MsExpr *e, MsTy expected, bool open_result, MsTy *result) {
    const MsTyTable *tys = &b->c->tys;
    const bool context = expected != MS_TY_NONE && ms_ty_kind(tys, expected) == MS_K_FUNCTION &&
                         tys->nparams[expected] == e->u.lambda.params.len;
    if (e->u.lambda.params.len > 16 || (expected != MS_TY_NONE && !context)) {
        return ms_body_unsupported(b);
    }
    MsTyParam *params = MS_NEW_N(&b->c->arena, MsTyParam, e->u.lambda.params.len + 1);
    for (uint32_t i = 0; i < e->u.lambda.params.len && b->supported; i++) {
        const MsParam *p = e->u.lambda.params.ptr[i];
        const MsTy from_context = context ? ms_ty_params(tys, expected)[i].ty : MS_TY_NONE;
        if (p->def != NULL || p->is_mutable || p->moving) {
            return ms_body_unsupported(b);
        }
        params[i] = (MsTyParam){.name = closure_slot_name(b, i), .ty = closure_declared(b, p->ty, from_context), .flags = MS_PARAM_POSITIONAL};
    }
    *result = closure_result(b, e->u.lambda.result, context && !open_result ? tys->result[expected] : MS_TY_NONE);
    if (!b->supported) {
        return MS_TY_NONE;
    }
    const MsSym fn = ms_intern_cstr(b->c->names, "fn");
    const MsTyDesc desc = {.name = fn, .id = fn, .kind = MS_K_FUNCTION, .params = params,
                           .nparams = e->u.lambda.params.len, .result = *result};
    return ms_ty_intern(&b->c->tys, &desc);
}

/* `fn` with the result `result`: the type of a function literal once its body has decided it. */
static MsTy closure_with_result(MsBody *b, MsTy fn, MsTy result) {
    const MsTyTable *tys = &b->c->tys;
    const MsSym name = ms_intern_cstr(b->c->names, "fn");
    const uint32_t count = tys->nparams[fn];
    MsTyParam *params = MS_NEW_N(&b->c->arena, MsTyParam, count + 1);
    memcpy(params, ms_ty_params(tys, fn), count * sizeof *params); // interning may move the table's own copy
    const MsTyDesc desc = {.name = name, .id = name, .kind = MS_K_FUNCTION, .params = params, .nparams = count, .result = result};
    return ms_ty_intern(&b->c->tys, &desc);
}

/* An anonymous function: its parameters are bound for its body, which is its own boundary for
 * `return`, `break` and `continue`. With `infer`, `expected` fixes only the parameters and the first
 * `return` of the body decides the result. */
static MsTy closure_check(MsBody *b, const MsExpr *e, MsTy expected, bool infer) {
    MsTy result = MS_TY_NONE;
    // A written result is the result: the body is checked against it, and the call binds its variable to it.
    const bool open_result = infer && e->u.lambda.result != NULL;
    infer = infer && !open_result;
    const MsTy fn = closure_signature(b, e, expected, open_result, &result);
    if (!b->supported || !closure_plain(b, fn)) {
        return ms_body_unsupported(b);
    }
    const MsTy outer_result = b->result;
    const bool outer_infer = b->infer_result;
    const uint32_t outer_depth = b->loop_depth, outer_floor = b->lambda_floor;
    const uint32_t outer_breaks = b->breaks;
    const uint32_t first = b->facts->bindings.count;
    b->result = infer ? MS_TY_NONE : result;
    b->infer_result = infer;
    b->loop_depth = 0;
    b->breaks = 0;
    b->lambda_floor = first;
    b->facts->lambda_first[e->id] = first;
    const MsTyParam *params = ms_ty_params(&b->c->tys, fn);
    for (uint32_t i = 0; i < e->u.lambda.params.len && b->supported; i++) {
        (void)ms_body_bind(b, e->u.lambda.params.ptr[i]->name, params[i].ty, e->u.lambda.params.ptr[i]->id, e->u.lambda.params.ptr[i]->pos, 0, MS_ROLE_LAMBDA_PARAM);
    }
    const bool falls = b->supported && ms_body_block(b, &e->u.lambda.body);
    if (infer && b->result == MS_TY_NONE) {
        b->result = b->void_ty; // no value was returned
    }
    result = infer ? b->result : result;
    const bool complete = !falls || result == b->void_ty;
    for (uint32_t i = first; i < b->facts->bindings.count; i++) {
        b->closed[i] = true;
    }
    b->result = outer_result;
    b->infer_result = outer_infer;
    b->loop_depth = outer_depth;
    b->breaks = outer_breaks;
    b->lambda_floor = outer_floor;
    if (!b->supported || !complete) {
        return ms_body_unsupported(b);
    }
    return infer ? closure_with_result(b, fn, result) : fn;
}

MsTy ms_body_lambda(MsBody *b, const MsExpr *e, MsTy expected) {
    return closure_check(b, e, expected, false);
}

MsTy ms_body_lambda_inferred(MsBody *b, const MsExpr *e, MsTy settled) {
    return closure_check(b, e, settled, true);
}
