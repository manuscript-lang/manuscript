/* Optional and Result in the lowering (crates/ms-lower: `lower_ty` for `Kind::Alternative`,
 * `call.rs` cases, `stmt.rs` unwrapping, `expr.rs` `?`). An `Optional[T]` is the MIR `opt<T>`; a
 * `Result[T, E]` is an alternative whose cases come from its declaration in the core library.
 * Payloads that need a drop (a String, a list, an owner) stay with the Rust lowering until the
 * ownership side lands. */
#include <string.h>

#include "ms/lower_internal.h"

enum { LA_OK = 0, LA_ERROR = 1 }; /* the order of the cases of `Result` in core.ms */

/* The cases of `Result[T, E]`, as `enum Result` declares them in core.ms (the checker's tables do not
 * carry the cases of a core enum): `ok(value: T)` and `error(cause: E)`. */
static MirTy la_result(Lb *lb, MsTy ty) {
    const MsTy *args = ms_ty_args(&lb->c->tys, ty);
    static const char *const case_names[2] = {"ok", "error"};
    static const char *const field_names[2] = {"value", "cause"};
    MirCaseDef *cases = MS_NEW_N(&lb->m->arena, MirCaseDef, 2);
    for (uint32_t i = 0; i < 2; i++) {
        const MirTy payload = lb_mir_ty(lb, args[i]);
        if (payload == MIR_NONE) {
            return MIR_NONE;
        }
        MirField *field = MS_NEW(&lb->m->arena, MirField);
        *field = (MirField){mir_name(lb->m, field_names[i], strlen(field_names[i])), payload};
        cases[i] = (MirCaseDef){mir_name(lb->m, case_names[i], strlen(case_names[i])), field, 1};
    }
    MsBuf text = {0};
    ms_ty_show(&text, lb->c->names, &lb->c->tys, ty);
    const uint32_t id = mir_add_alt(lb->m, mir_name(lb->m, text.data, text.len));
    ms_buf_free(&text);
    lb->m->alts[id].cases = cases;
    lb->m->alts[id].ncases = 2;
    lb->m->alts[id].std = MSTD_RESULT;
    return mir_ty_alt(lb->m, id);
}

/* The MIR type of `Optional[T]` and `Result[T, E]` over payloads that need no drop, else MIR_NONE. */
MirTy la_type(Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    if (lb->type_of[ty] == LB_TYPE_PENDING) {
        return MIR_NONE; // a record whose fields are being lowered
    }
    if (lb->type_of[ty] != MIR_NONE) {
        return lb->type_of[ty];
    }
    MirTy mir = MIR_NONE;
    if (ms_ty_is(tys, ty, MS_BI_OPTIONAL) && tys->nargs[ty] == 1) {
        const MirTy payload = lb_mir_ty(lb, ms_ty_args(tys, ty)[0]);
        mir = payload == MIR_NONE ? MIR_NONE : mir_ty_opt(lb->m, payload);
    } else if (ms_ty_is(tys, ty, MS_BI_RESULT) && tys->nargs[ty] == 2) {
        mir = la_result(lb, ty);
    }
    lb->type_of[ty] = mir;
    return mir;
}

/* `none` where an Optional is expected. */
LbVal la_none(Lb *lb, const MsExpr *e) {
    const MirTy ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    if (ty == MIR_NONE || mir_ty_data(lb->m, ty)->kind != MK_OPT) {
        return lb_unsupported(lb);
    }
    return (LbVal){mir_b_emit(&lb->b, MOP_OptNone, NULL, 0, (MirImm){0}, ty), false};
}

/* `none` handed out as an owned value (a result, a moved argument): the Optional that owns nothing. */
LbVal la_none_owned(Lb *lb, const MsExpr *e) {
    const MirTy ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    return (LbVal){mir_b_emit(&lb->b, MOP_OptNoneOwned, NULL, 0, (MirImm){0}, ty), true};
}

/* `ok(value)`, `error(cause)` and `Case(args)` of an enum: the checker resolved the callee to the
 * case, and every argument fills one field of it; a field that owns something is handed over. */
LbVal la_case(Lb *lb, const MsExpr *call) {
    const MsExpr *callee = call->u.call.callee;
    const MirTy ty = lb_mir_ty(lb, lb->facts->expr_ty[call->id]);
    const uint32_t count = call->u.call.args.len;
    if (ty == MIR_NONE || mir_ty_data(lb->m, ty)->kind != MK_ALT) {
        return lb_unsupported(lb);
    }
    const MirCaseDef *def = &lb->m->alts[mir_ty_data(lb->m, ty)->id].cases[lb->facts->res_ref[callee->id]];
    if (def->nfields != count) {
        return lb_unsupported(lb); // `ok()`: the Void payload is left out
    }
    MirValue *payload = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 1);
    for (uint32_t i = 0; i < count && lb->ok; i++) {
        const MsExpr *arg = call->u.call.args.ptr[i].value;
        payload[i] = lb_owns(lb, def->fields[i].ty) ? lb_move_argument(lb, arg) : lb_expr(lb, arg).v;
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirImm imm = {.tag = MI_CASE, .a = mir_ty_data(lb->m, ty)->id, .b = lb->facts->res_ref[callee->id]};
    return (LbVal){mir_b_emit(&lb->b, MOP_AltNew, payload, count, imm, ty), lb_owns(lb, ty)};
}

/* A case without payload, named: `Empty`. */
LbVal la_nullary(Lb *lb, const MsExpr *e) {
    const MirTy ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    if (ty == MIR_NONE || mir_ty_data(lb->m, ty)->kind != MK_ALT) {
        return lb_unsupported(lb);
    }
    const MirImm imm = {.tag = MI_CASE, .a = mir_ty_data(lb->m, ty)->id, .b = lb->facts->res_ref[e->id]};
    return (LbVal){mir_b_emit(&lb->b, MOP_AltNew, NULL, 0, imm, ty), false};
}

/* Whether `subject` holds a value: `opt.is_some`, or a Result's tag is `ok`. */
MirValue la_test(Lb *lb, MirValue subject) {
    const MirTy ty = mir_b_ty(&lb->b, subject);
    if (mir_ty_data(lb->m, ty)->kind == MK_OPT) {
        return mir_b_emit(&lb->b, MOP_OptIsSome, &subject, 1, (MirImm){0}, MIR_BOOL);
    }
    const MirValue tag = mir_b_emit(&lb->b, MOP_AltTag, &subject, 1, (MirImm){0}, MIR_INT);
    return mir_b_icmp(&lb->b, MCC_EQ, tag, mir_b_iconst(&lb->b, LA_OK));
}

/* The payload of `subject` (a Result held by value) in case `index`: read in place when the holder
 * needs no drop; otherwise it moves out (read, take, then release what is left of the holder), the
 * way the Rust lowering writes it. */
static MirValue la_field(Lb *lb, MirValue subject, uint32_t alt, uint32_t index, MirTy ty) {
    const MirImm field = {.tag = MI_ALTFIELD, .a = alt, .b = index, .c = 0};
    const MirValue read = mir_b_emit(&lb->b, MOP_AltGet, &subject, 1, field, ty);
    if (!lb_owns(lb, mir_b_ty(&lb->b, subject))) {
        return read; // the holder needs no release
    }
    const MirValue taken = mir_b_emit(&lb->b, MOP_AltTake, &subject, 1, field, ty);
    const MirImm mask = {.tag = MI_ALTMASK, .a = alt, .b = index, .c = 1};
    (void)mir_b_emit(&lb->b, MOP_AltRelease, &subject, 1, mask, MIR_NONE);
    return taken;
}

/* The value `subject` holds, once `la_test` found it present. */
MirValue la_payload(Lb *lb, MirValue subject) {
    const MirTy ty = mir_b_ty(&lb->b, subject);
    const MirTyData *data = mir_ty_data(lb->m, ty);
    const MirTy held = data->kind == MK_OPT ? data->elem : lb->m->alts[data->id].cases[LA_OK].fields[0].ty;
    if (data->kind == MK_OPT) {
        if (lb_owns(lb, held)) {
            (void)lb_unsupported(lb); // taking an owned payload out of an Optional is not lowered yet
            return subject;
        }
        return mir_b_emit(&lb->b, MOP_OptGet, &subject, 1, (MirImm){0}, data->elem);
    }
    return la_field(lb, subject, data->id, LA_OK, held);
}

/* `call()?` on a Result inside a function that returns a Result with the same error type: the
 * success value; an error leaves the function with it. */
LbVal la_try(Lb *lb, const MsExpr *e) {
    const LbVal result = lb_expr(lb, e->u.bin.left);
    const MirTy ret = lb->b.f.ret;
    if (!lb->ok || mir_ty_data(lb->m, mir_b_ty(&lb->b, result.v))->kind != MK_ALT ||
        mir_ty_data(lb->m, ret)->kind != MK_ALT) {
        return lb_unsupported(lb);
    }
    const MirTyData *held = mir_ty_data(lb->m, mir_b_ty(&lb->b, result.v));
    const MirTyData *back = mir_ty_data(lb->m, ret);
    const MirTy cause = lb->m->alts[held->id].cases[LA_ERROR].fields[0].ty;
    if (lb->m->alts[back->id].std != MSTD_RESULT || lb->m->alts[back->id].cases[LA_ERROR].fields[0].ty != cause) {
        return lb_unsupported(lb);
    }
    const MirValue tag = mir_b_emit(&lb->b, MOP_AltTag, &result.v, 1, (MirImm){0}, MIR_INT);
    const MirValue failed = mir_b_icmp(&lb->b, MCC_EQ, tag, mir_b_iconst(&lb->b, LA_ERROR));
    const MirBlock fail_block = mir_b_new_block(&lb->b);
    const MirBlock go_on = mir_b_new_block(&lb->b);
    mir_b_br_if(&lb->b, failed, fail_block, NULL, 0, go_on, NULL, 0);
    mir_b_seal_block(&lb->b, fail_block);
    mir_b_seal_block(&lb->b, go_on);
    lb_enter(lb, fail_block);
    const MirValue error = la_field(lb, result.v, held->id, LA_ERROR, cause);
    const MirImm error_case = {.tag = MI_CASE, .a = back->id, .b = LA_ERROR};
    const MirValue handed = mir_b_emit(&lb->b, MOP_AltNew, &error, 1, error_case, ret);
    lb_own_vars(lb, 0, MIR_NONE);
    lscope_exit_to(&lb->scopes, 0);
    lb_write_back(lb);
    lb_emit_plain(lb, MOP_DepthLeave);
    mir_b_ret(&lb->b, handed);
    lb_enter(lb, go_on);
    const MirValue value = la_payload(lb, result.v);
    return (LbVal){value, lb_owns(lb, mir_b_ty(&lb->b, value))}; // an owned value moves out of the result
}
