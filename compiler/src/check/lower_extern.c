/* A call of a bodiless `extern fn` (`msstd_math_sqrt` in stdlib/internal/math.ms): the runtime function
 * of the same name, found in the ms-sig table (rt_ops.h) and marshalled as a native method is. The
 * call's arguments are the function's parameters in order. A function the table does not list, or
 * whose signature `lb_native_call` cannot marshal, leaves the caller to the Rust lowering. */
#include "ms/lower_internal.h"
#include "ms/rt_ops.h"

/* Whether `callee` names an `extern fn`. */
bool lx_is_extern(const Lb *lb, MsSymId callee) {
    const MsDecl *decl = lb->c->syms.decl[callee];
    return lb->c->syms.kind[callee] == MS_SYM_FN && decl != NULL && decl->kind == MS_D_FN && decl->u.fn.external;
}

LbVal lx_call(Lb *lb, const MsExpr *e, MsSymId callee) {
    const MsStr name = ms_name(lb->c->names, lb->c->syms.decl[callee]->u.fn.name);
    const MsRtFn *fn = ms_rt_fn_find(name.ptr, name.len);
    const uint32_t nargs = e->u.call.args.len;
    if (fn == NULL || nargs > MS_RT_MAX_PARAMS) {
        return lb_unsupported(lb);
    }
    MirValue args[MS_RT_MAX_PARAMS];
    for (uint32_t i = 0; i < nargs && lb->ok; i++) {
        const LbVal value = lb_expr(lb, e->u.call.args.ptr[i].value);
        args[i] = value.v;
        if (lb->ok && value.owned) {
            lb_hold_temp(lb, value.v); // a borrowed argument lives to the end of the statement
        }
    }
    const MsTy result = lb->facts->expr_ty[e->id];
    const MirTy result_ty = result == lb->void_ty ? MIR_VOID : lb_mir_ty(lb, result);
    if (!lb->ok || result_ty == MIR_NONE) {
        return lb_unsupported(lb);
    }
    return lb_native_call(lb, fn, args, nargs, result_ty);
}
