/* The built-in cases of `Result` and `Optional` called like functions: `ok(v)` and `error(e)` where
 * the context expects a `Result[T, E]`, whose payload is a value of an admitted type checked against T or E,
 * and `some(v)`, which is always an error (a plain value converts where an Optional is expected),
 * reported here.
 * With no expected Result, a payload that is not a primitive, or a call that is not one positional
 * argument, the function is left to the Rust checker. Records only the type: no function is
 * called, so `call_callee` stays unset and the callee name resolves to a case (0 for ok, 1 for error). */
#include <string.h>

#include "check_body.h"

static bool builtin_is(const MsBody *b, MsSym name, const char *text) {
    const MsStr s = ms_name(b->c->names, name);
    return s.len == strlen(text) && memcmp(s.ptr, text, s.len) == 0;
}

bool ms_body_is_builtin_case(const MsBody *b, MsSym name) {
    return builtin_is(b, name, "ok") || builtin_is(b, name, "error") || builtin_is(b, name, "some");
}

MsTy ms_body_builtin_call(MsBody *b, const MsExpr *e, MsTy expected) {
    const MsExpr *callee = e->u.call.callee;
    if (builtin_is(b, callee->u.sym, "some")) {
        // The arguments are not checked; the call is invalid, which silences what uses it.
        ms_body_report(b, e->pos,
                       ms_arena_fmt(&b->c->arena, "there is no some(...); a plain value converts where a T? is expected, so pass it "
                                                  "directly, or annotate the binding, e.g. x: Int? := 5"));
        return b->invalid_ty;
    }
    const MsTyTable *tys = &b->c->tys;
    if (expected == MS_TY_NONE || !ms_ty_is(tys, expected, MS_BI_RESULT) || tys->nargs[expected] != 2 ||
        e->u.call.args.len != 1 || e->u.call.args.ptr[0].has_name) {
        return ms_body_unsupported(b);
    }
    const bool success = builtin_is(b, callee->u.sym, "ok");
    const MsTy payload = ms_ty_args(tys, expected)[success ? 0 : 1];
    if (!ms_body_is_admitted(b, payload) ||
        ms_body_expr(b, e->u.call.args.ptr[0].value, payload) == MS_TY_NONE) {
        return ms_body_unsupported(b);
    }
    b->facts->res_kind[callee->id] = MS_RES_CASE;
    b->facts->res_ref[callee->id] = success ? 0 : 1;
    return expected;
}
