/* A call of a bodiless `extern fn` (`msstd_math_sqrt` in stdlib/internal/math.ms): the runtime function
 * of the same name, found in the ms-sig table (rt_ops.h) and marshalled as a native method is. The
 * call's arguments are the function's parameters in order. A function the table does not list, or
 * whose signature `lb_native_call` cannot marshal, leaves the caller to the Rust lowering. */
#include "ms/lower_internal.h"
#include "ms/rt_ops.h"

/* The MIR type of an `extern type` the runtime owns (`NativeScope`, `HttpHeaders`): a runtime object named by it, or
 * MIR_NONE for any other type or a generic native. */
MirTy lx_type(Lb *lb, MsTy ty) {
    if (ms_ty_kind(&lb->c->tys, ty) != MS_K_NATIVE || lb->c->tys.nargs[ty] != 0) {
        return MIR_NONE;
    }
    const MsStr name = ms_name(lb->c->names, lb->c->tys.name[ty]);
    return mir_ty_obj(lb->m, mir_name(lb->m, name.ptr, name.len), NULL, 0);
}

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
    const LbVal call = lb_native_call(lb, fn, args, nargs, result_ty);
    if (lb->ok && result_ty != MIR_VOID && mir_b_ty(&lb->b, call.v) != result_ty) {
        return lb_unsupported(lb); // the marshalled call yields something else (a handle written through `out`)
    }
    return call;
}
