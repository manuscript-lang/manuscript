/* Calls of generic functions of the module: `identity(3)`, `larger(a, b)`. The type arguments are
 * inferred from the argument types (infer.h), every bound must hold (implements.h), and the call
 * has the result type with them applied. Handled: positional arguments of primitive type, each
 * variable bound to a primitive, bounds that are certainly met. Explicit type arguments, defaults
 * that are needed, bounds whose answer is unknown and every other form leave the function to the
 * Rust checker. Records `call_callee`; the type
 * arguments are recomputed from the argument types by whoever lowers the call. */
#include "check_body.h"

#include "ms/implements.h"
#include "ms/infer.h"
#include "ms/ty_algebra.h"

/* Matches each argument against its parameter, binding the variables. */
static bool generic_arguments(MsBody *b, const MsExpr *e, MsTy sig, MsInfer *in) {
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION || tys->nparams[sig] != e->u.call.args.len || e->u.call.args.len > 16) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsArg *arg = &e->u.call.args.ptr[i];
        const bool fixed = !ms_ty_has_variable(tys, &b->c->arena, params[i].ty);
        if (arg->has_name || params[i].flags != 0 || (fixed && !ms_body_is_plain_value(b, params[i].ty))) {
            return false;
        }
        const MsTy actual = ms_body_expr(b, arg->value, fixed ? params[i].ty : MS_TY_NONE);
        if (actual == MS_TY_NONE || !ms_body_is_plain_value(b, actual) || ms_infer_match(in, params[i].ty, actual) != MS_MATCH_OK) {
            return false;
        }
    }
    return true;
}

/* Every variable is bound to a primitive and each of its bounds, with the bindings applied, is met. */
static bool generic_bounds(MsBody *b, MsInfer *in) {
    if (b->methods == NULL) {
        return false;
    }
    for (uint32_t i = 0; i < in->nvars; i++) {
        if (in->bound[i] == MS_TY_NONE || !ms_body_is_plain_value(b, in->bound[i])) {
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

MsTy ms_body_generic_call(MsBody *b, const MsExpr *e, MsSymId sym) {
    if (b->c->syms.module[sym] != b->module) {
        return ms_body_unsupported(b); /* an imported generic: its declaration ids belong to another module */
    }
    const MsDef *def = ms_def(b->c, sym);
    const MsTy sig = b->c->syms.ty[sym];
    MsInfer in;
    ms_infer_init(&in, b->c, &b->c->arena, def->vars, def->nvars);
    uint32_t first = 0;
    if (!generic_arguments(b, e, sig, &in) || ms_infer_defaults(&in, &first) != 0 || !generic_bounds(b, &in)) {
        return ms_body_unsupported(b);
    }
    const MsTy result = ms_infer_apply(&in, b->c->tys.result[sig]);
    if (!ms_body_is_plain_value(b, result)) {
        return ms_body_unsupported(b);
    }
    b->facts->call_callee[e->id] = sym;
    return result;
}
