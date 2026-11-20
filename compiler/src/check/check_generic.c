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

/* Matches each argument against its parameter, binding the variables. */
static bool generic_arguments(MsBody *b, const MsExpr *e, MsTy sig, MsInfer *in) {
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION || tys->nparams[sig] != e->u.call.args.len || e->u.call.args.len > 16) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsArg *arg = &e->u.call.args.ptr[i];
        // Explicit type arguments already fix some variables: the argument is checked against that.
        const MsTy want = ms_infer_apply(in, params[i].ty);
        const bool fixed = !ms_ty_has_variable(tys, &b->c->arena, want);
        if (arg->has_name || params[i].flags != 0 || (fixed && !ms_body_is_admitted(b, want))) {
            return false;
        }
        const MsTy actual = ms_body_expr(b, arg->value, fixed ? want : MS_TY_NONE);
        if (actual == MS_TY_NONE || !ms_body_is_admitted(b, actual) || ms_infer_match(in, params[i].ty, actual) != MS_MATCH_OK) {
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
    if (b->c->syms.module[sym] != b->module) {
        return ms_body_unsupported(b); /* an imported generic: its declaration ids belong to another module */
    }
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
    if (!generic_arguments(b, e, sig, &in) || ms_infer_defaults(&in, &first) != 0 || !generic_bounds(b, &in)) {
        return ms_body_unsupported(b);
    }
    const MsTy result = ms_infer_apply(&in, b->c->tys.result[sig]);
    if (!ms_body_is_admitted(b, result)) {
        return ms_body_unsupported(b);
    }
    b->facts->call_callee[e->id] = sym;
    generic_record_type_args(b, e, &in);
    return result;
}
