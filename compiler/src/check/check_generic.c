/* Calls of generic functions of the module: `identity(3)`, `larger(a, b)`. The type arguments are
 * inferred from the argument types (infer.h), every bound must hold (implements.h), and the call
 * has the result type with them applied. Handled: positional arguments of a type the body pass admits, each
 * variable bound to one, bounds that are certainly met. Explicit type arguments, defaults
 * that are needed, bounds whose answer is unknown and every other form leave the function to the
 * Rust checker. Records `call_callee` and the type arguments (`call_type_args_*`). */
#include <string.h>

#include "check_body.h"

#include "ms/implements.h"
#include "ms/infer.h"
#include "ms/ty_algebra.h"

/* Whether `ty` mentions the type variable `var` (variables are the same by their id, as in infer.c). */
static bool ty_mentions(const MsTyTable *tys, MsTy ty, MsTy var) {
    if (ty == var || (ms_ty_kind(tys, ty) == MS_K_VARIABLE && tys->id[ty] == tys->id[var])) {
        return true;
    }
    for (uint32_t i = 0; i < tys->nargs[ty]; i++) {
        if (ty_mentions(tys, ms_ty_args(tys, ty)[i], var)) {
            return true;
        }
    }
    if (ms_ty_kind(tys, ty) != MS_K_FUNCTION) {
        return false;
    }
    for (uint32_t i = 0; i < tys->nparams[ty]; i++) {
        if (ty_mentions(tys, ms_ty_params(tys, ty)[i].ty, var)) {
            return true;
        }
    }
    return ty_mentions(tys, tys->result[ty], var);
}

/* Whether `ty` mentions a variable of the open row that no argument has bound yet. */
bool ms_body_mentions_unbound(const MsBody *b, const MsInfer *in, MsTy ty) {
    for (uint32_t k = 0; k < in->nvars; k++) {
        if (in->bound[k] == MS_TY_NONE && ty_mentions(&b->c->tys, ty, in->vars[k])) {
            return true;
        }
    }
    return false;
}

/* One argument of an open row: against its parameter when that is settled, else its type binds the
 * parameter's variables. A function literal whose parameters are settled gets them and takes its
 * result from its body, which binds the variables of the parameter's result. */
bool ms_body_open_argument(MsBody *b, const MsExpr *value, const MsTyParam *param, MsInfer *in) {
    const MsTyTable *tys = &b->c->tys;
    const MsTy want = ms_infer_apply(in, param->ty);
    if (!ms_body_mentions_unbound(b, in, want)) {
        return ms_body_is_admitted(b, want) && ms_body_expr(b, value, want) != MS_TY_NONE;
    }
    MsTy actual = MS_TY_NONE;
    if (value->kind == MS_E_LAMBDA) {
        bool settled = ms_ty_kind(tys, want) == MS_K_FUNCTION;
        for (uint32_t i = 0; settled && i < tys->nparams[want]; i++) {
            settled = !ms_body_mentions_unbound(b, in, ms_ty_params(tys, want)[i].ty);
        }
        actual = settled ? ms_body_lambda_inferred(b, value, want) : MS_TY_NONE;
        if (actual != MS_TY_NONE) {
            (void)ms_body_record(b, value->id, actual);
        }
    } else {
        actual = ms_body_expr(b, value, MS_TY_NONE);
    }
    return actual != MS_TY_NONE && ms_body_is_admitted(b, actual) && ms_infer_match(in, param->ty, actual) == MS_MATCH_OK;
}

/* A function passed for a parameter has the parameter's type (`fn(move T) U`), as the Rust checker
 * records it, whatever ownership mode the function's own type spells. `slot[i]` is the parameter
 * of argument i. */
void ms_body_record_function_arguments(MsBody *b, const MsExpr *call, MsTy sig, const uint32_t *slot) {
    const MsTyTable *tys = &b->c->tys;
    const MsTyParam *params = ms_ty_params(tys, sig);
    for (uint32_t i = 0; i < call->u.call.args.len; i++) {
        const MsTy want = params[slot[i]].ty;
        if (ms_ty_kind(tys, want) == MS_K_FUNCTION) {
            (void)ms_body_record(b, call->u.call.args.ptr[i].value->id, want);
        }
    }
}

/* Matches each argument against its parameter, binding the variables. Arguments pair with
 * parameters by label or position; a parameter left out must have a default in `func`, the callee's
 * declaration. */
static bool generic_arguments(MsBody *b, const MsExpr *e, MsTy sig, const MsFunc *func, MsInfer *in, uint32_t *slot) {
    const MsTyTable *tys = &b->c->tys;
    const uint32_t given = e->u.call.args.len;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION) {
        return false;
    }
    const uint32_t nparams = tys->nparams[sig];
    if (given > nparams || nparams > 16 || func->params.len != nparams) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    MsSym names[16] = {0};
    bool positional[16] = {false}, covered[16] = {false};
    for (uint32_t i = 0; i < nparams; i++) {
        names[i] = params[i].name;
        positional[i] = (params[i].flags & MS_PARAM_POSITIONAL) != 0;
    }
    if (!ms_body_bind_arguments(e, names, positional, nparams, slot, covered)) {
        return false;
    }
    for (uint32_t i = 0; i < nparams; i++) {
        if (!covered[i] && func->params.ptr[i]->def == NULL) {
            return false;
        }
    }
    for (uint32_t i = 0; i < given; i++) {
        const MsTyParam *param = &params[slot[i]];
        if ((param->flags & ~MS_PARAM_POSITIONAL) != 0 ||
            !ms_body_open_argument(b, e->u.call.args.ptr[i].value, param, in)) {
            return false;
        }
    }
    b->facts->call_reordered[e->id] = ms_body_reordered(e, slot);
    return true;
}

/* Every variable is bound to a primitive and each of its bounds, with the bindings applied, is met. */
static bool generic_bounds(MsBody *b, MsInfer *in) {
    if (b->methods == NULL) {
        return false;
    }
    for (uint32_t i = 0; i < in->nvars; i++) {
        if (in->bound[i] == MS_TY_NONE || !ms_body_is_admitted(b, in->bound[i])) {
            return false;
        }
        const MsVarInfo *info = ms_var_info(b->c, in->vars[i]);
        for (uint32_t k = 0; k < info->nbounds; k++) {
            const MsTy bound = ms_infer_apply(in, info->bounds[k]);
            if (ms_implements(b->c, b->methods, in->bound[i], bound) != MS_FIT_YES) {
                return false;
            }
        }
    }
    return true;
}

/* The type arguments the call was inferred at, in the order of the callee's variables: the lowering
 * makes one copy of the callee per list. */
static void generic_record_type_args(MsBody *b, const MsExpr *e, const MsInfer *in) {
    MsFacts *facts = b->facts;
    if (facts->ntype_args + in->nvars > facts->ctype_args) {
        uint32_t cap = facts->ctype_args == 0 ? 16 : facts->ctype_args * 2;
        while (cap < facts->ntype_args + in->nvars) {
            cap *= 2;
        }
        MsTy *grown = MS_NEW_N(&b->c->arena, MsTy, cap);
        if (facts->ntype_args != 0) {
            memcpy(grown, facts->type_args, facts->ntype_args * sizeof *grown);
        }
        facts->type_args = grown;
        facts->ctype_args = cap;
    }
    facts->call_type_args_at[e->id] = facts->ntype_args;
    facts->call_type_args_len[e->id] = in->nvars;
    for (uint32_t i = 0; i < in->nvars; i++) {
        facts->type_args[facts->ntype_args++] = in->bound[i];
    }
}

MsTy ms_body_generic_call(MsBody *b, const MsExpr *e, MsSymId sym, const MsTypeRefs *written) {
    const MsDef *def = ms_def(b->c, sym);
    const MsTy sig = b->c->syms.ty[sym];
    MsInfer in;
    ms_infer_init(&in, b->c, &b->c->arena, def->vars, def->nvars);
    if (written != NULL) {
        // `f[Int](x)`: the written arguments bind the first variables, the rest are inferred.
        MsTy given[16];
        if (written->len == 0 || written->len > 16 || written->len > def->nvars) {
            return ms_body_unsupported(b);
        }
        for (uint32_t i = 0; i < written->len; i++) {
            given[i] = ms_body_annotation(b, written->ptr[i]);
            if (given[i] == MS_TY_NONE) {
                return MS_TY_NONE;
            }
        }
        if (!ms_infer_give(&in, given, written->len)) {
            return ms_body_unsupported(b);
        }
    }
    uint32_t first = 0;
    uint32_t slot[16];
    if (!generic_arguments(b, e, sig, &b->c->syms.decl[sym]->u.fn, &in, slot) || ms_infer_defaults(&in, &first) != 0 || !generic_bounds(b, &in)) {
        return ms_body_unsupported(b);
    }
    const MsTy result = ms_infer_apply(&in, b->c->tys.result[sig]);
    if (!ms_body_is_admitted(b, result)) {
        return ms_body_unsupported(b);
    }
    b->facts->call_callee[e->id] = sym;
    ms_body_record_function_arguments(b, e, ms_infer_apply(&in, sig), slot);
    generic_record_type_args(b, e, &in);
    return result;
}

static bool generic_is_native(const MsBody *b, MsSymId sym) {
    return ms_ty_kind(&b->c->tys, b->c->syms.ty[sym]) == MS_K_NATIVE;
}

static bool generic_is_nominal(const MsBody *b, MsSymId sym) {
    const MsKind kind = ms_ty_kind(&b->c->tys, b->c->syms.ty[sym]);
    return kind == MS_K_TYPE || kind == MS_K_NATIVE;
}

/* `Name[Args](fields)` or `Name(fields)` for a generic type: the written arguments give the first
 * variables, each field argument binds the rest, bounds must hold, and the call has the type
 * applied to them. Arguments pair with fields by label or position (ms_body_bind_arguments);
 * fields left out take their default. Natives (`Map[K, V]()`) have no fields to give. */
MsTy ms_body_generic_construct(MsBody *b, const MsExpr *e, MsSymId sym, const MsTypeRefs *written) {
    const MsSyms *syms = &b->c->syms;
    ms_module_resolve_types(b->c, syms->module[sym]); // the declaring module's fields and variables
    const MsDef *def = ms_def(b->c, sym);
    const MsDecl *decl = syms->decl[sym];
    const uint32_t nargs = e->u.call.args.len;
    if (decl == NULL || decl->kind != MS_D_TYPE || (syms->module[sym] != b->module && decl->u.type.opaque) ||
        !generic_is_nominal(b, sym) || (generic_is_native(b, sym) && nargs != 0) || def->nvars == 0 || nargs > def->nfields ||
        def->nfields != decl->u.type.fields.len || nargs > 16) {
        return ms_body_unsupported(b);
    }
    MsInfer in;
    ms_infer_init(&in, b->c, &b->c->arena, def->vars, def->nvars);
    if (written != NULL) {
        MsTy given[16];
        if (written->len == 0 || written->len > 16 || written->len > def->nvars) {
            return ms_body_unsupported(b);
        }
        for (uint32_t i = 0; i < written->len; i++) {
            given[i] = ms_body_annotation(b, written->ptr[i]);
            if (given[i] == MS_TY_NONE) {
                return MS_TY_NONE;
            }
        }
        if (!ms_infer_give(&in, given, written->len)) {
            return ms_body_unsupported(b);
        }
    }
    MsSym *names = MS_NEW_N(&b->c->arena, MsSym, def->nfields + 1);
    bool *covered = MS_NEW_N(&b->c->arena, bool, def->nfields + 1);
    uint32_t slot[16] = {0};
    for (uint32_t i = 0; i < def->nfields; i++) {
        names[i] = def->fields[i].name;
    }
    if (!ms_body_bind_arguments(e, names, NULL, def->nfields, slot, covered)) {
        return ms_body_unsupported(b);
    }
    for (uint32_t i = 0; i < def->nfields; i++) {
        if (!covered[i] && decl->u.type.fields.ptr[i]->def == NULL) {
            return ms_body_unsupported(b);
        }
    }
    for (uint32_t i = 0; i < nargs; i++) {
        const MsTyParam *field = &def->fields[slot[i]];
        const MsExpr *value = e->u.call.args.ptr[i].value;
        const MsTy want = ms_infer_apply(&in, field->ty);
        if (field->flags != 0) {
            return ms_body_unsupported(b);
        }
        if (!ms_body_mentions_unbound(b, &in, want)) {
            if (!ms_body_is_bindable(b, want) || ms_body_expr(b, value, want) == MS_TY_NONE) {
                return ms_body_unsupported(b);
            }
            continue;
        }
        const MsTy actual = ms_body_expr(b, value, MS_TY_NONE);
        if (actual == MS_TY_NONE || !ms_body_is_bindable(b, actual) || ms_infer_match(&in, field->ty, actual) != MS_MATCH_OK) {
            return ms_body_unsupported(b);
        }
    }
    uint32_t first = 0;
    if (ms_infer_defaults(&in, &first) != 0 || !generic_bounds(b, &in)) {
        return ms_body_unsupported(b);
    }
    const MsTy result = ms_ty_apply(b->c, syms->ty[sym], in.bound, def->nvars);
    // A type applied to the caller's own variables may be a cycle of applications that never ends,
    // which the Rust checker reports (recursion.rs); the graph is not built here yet.
    if (result == MS_TY_NONE || !ms_body_is_bindable(b, result) || ms_ty_has_variable(&b->c->tys, &b->c->arena, result)) {
        return ms_body_unsupported(b);
    }
    b->facts->call_reordered[e->id] = ms_body_reordered(e, slot);
    b->facts->call_callee[e->id] = sym;
    return result;
}
