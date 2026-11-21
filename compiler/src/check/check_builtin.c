/* The built-in cases of `Result` and `Optional` called like functions: `ok(v)` and `error(e)` where
 * the context expects a `Result[T, E]`, whose payload is a value of an admitted type checked against T or E,
 * and `some(v)`, which is always an error (a plain value converts where an Optional is expected).
 * With no expected Result, a payload that is not a primitive, or a call that is not one positional
 * argument, the function is left to the Rust checker. Records only the type: no function is
 * called, so `call_callee` stays unset and the callee name resolves to a case (0 for ok, 1 for error). */
#include <string.h>

#include "check_body.h"

bool ms_body_is_builtin_case(const MsBody *b, MsSym name) {
    return ms_name_is(b->c->names, name, "ok") || ms_name_is(b->c->names, name, "error") || ms_name_is(b->c->names, name, "some");
}

MsTy ms_body_builtin_call(MsBody *b, const MsExpr *e, MsTy expected) {
    const MsExpr *callee = e->u.call.callee;
    if (ms_name_is(b->c->names, callee->u.sym, "some")) {
        return ms_body_unsupported(b); /* the diagnostic is the Rust checker's for now */
    }
    const MsTyTable *tys = &b->c->tys;
    if (expected == MS_TY_NONE || !ms_ty_is(tys, expected, MS_BI_RESULT) || tys->nargs[expected] != 2 ||
        e->u.call.args.len != 1 || e->u.call.args.ptr[0].has_name) {
        return ms_body_unsupported(b);
    }
    const bool success = ms_name_is(b->c->names, callee->u.sym, "ok");
    const MsTy payload = ms_ty_args(tys, expected)[success ? 0 : 1];
    if (!ms_body_is_admitted(b, payload) ||
        ms_body_expr(b, e->u.call.args.ptr[0].value, payload) == MS_TY_NONE) {
        return ms_body_unsupported(b);
    }
    b->facts->res_kind[callee->id] = MS_RES_CASE;
    b->facts->res_ref[callee->id] = success ? 0 : 1;
    return expected;
}
