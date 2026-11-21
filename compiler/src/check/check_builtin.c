/* The built-in cases of `Result` and `Optional` called like functions: `ok(v)` and `error(e)` where
 * the context expects a `Result[T, E]`, whose payload is a value of an admitted type checked against T or E,
 * and `some(v)`, which is always an error (a plain value converts where an Optional is expected),
 * reported here.
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
        // The arguments are not checked; the call is invalid, which silences what uses it.
        ms_body_report(b, e->pos,
                       ms_arena_fmt(&b->c->arena, "there is no some(...); a plain value converts where a T? is expected, so pass it "
                                                  "directly, or annotate the binding, e.g. x: Int? := 5"));
        return b->invalid_ty;
    }
    const MsTyTable *tys = &b->c->tys;
    const uint32_t nargs = e->u.call.args.len;
    if (expected == MS_TY_NONE || !ms_ty_is(tys, expected, MS_BI_RESULT) || tys->nargs[expected] != 2 || nargs > 1) {
        return ms_body_unsupported(b);
    }
    const bool success = ms_name_is(b->c->names, callee->u.sym, "ok");
    // A label must be the payload field's own name (`ok(value: v)`, `error(cause: e)`), as core.ms declares it.
    if (nargs == 1 && e->u.call.args.ptr[0].has_name &&
        !ms_body_result_label(b, expected, success, e->u.call.args.ptr[0].name)) {
        return ms_body_unsupported(b);
    }
    const MsTy payload = ms_ty_args(tys, expected)[success ? 0 : 1];
    // `ok()` stands for `ok(void)`: a Void payload may be left out.
    const bool omitted = nargs == 0 && payload == b->void_ty;
    if (nargs == 0 ? !omitted
                   : ((payload != b->void_ty && !ms_body_is_admitted(b, payload)) || ms_body_expr(b, e->u.call.args.ptr[0].value, payload) == MS_TY_NONE)) {
        return ms_body_unsupported(b);
    }
    b->facts->res_kind[callee->id] = MS_RES_CASE;
    b->facts->res_ref[callee->id] = success ? 0 : 1;
    return expected;
}
