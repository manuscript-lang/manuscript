/* Methods that are instructions and that no runtime declaration describes: an Optional's payload or a default, and
 * `clone` (crates/ms-lower native/optional.rs `optional_method`, native/method.rs). */

#include "ms/lower_internal.h"

/* The payload of `optional` as a value the caller owns: an owned Optional hands it over, a borrowed one is copied. */
static MirValue lop_payload(Lb *lb, LbVal optional, MirTy payload_ty) {
    if (optional.owned) {
        return mir_b_emit(&lb->b, MOP_OptUnbox, &optional.v, 1, (MirImm){0}, payload_ty);
    }
    const MirValue payload = mir_b_emit(&lb->b, MOP_OptGet, &optional.v, 1, (MirImm){0}, payload_ty);
    return lb_owns(lb, payload_ty) ? lb_copy(lb, payload) : payload;
}

/* `value.get_or(fallback)`: the payload when there is one, else the fallback. The fallback is evaluated first, as
 * any argument is, and the branch that does not use an owned operand releases it. */
static LbVal lop_get_or(Lb *lb, const MsExpr *receiver, const MsExpr *argument, MirTy payload_ty) {
    const bool owns = lb_owns(lb, payload_ty);
    const bool is_plain = lb->facts->some_wrap[argument->id]; // a plain value where the parameter is `T?`
    if (!is_plain && owns) {
        return LB_UNSUPPORTED(lb); // an Optional fallback that owns its payload is not unwrapped here yet
    }
    LbVal optional = lb_expr(lb, receiver);
    LbVal fallback = LB_FAIL;
    if (lb->ok) {
        fallback = is_plain ? lb_expr_plain(lb, argument) : lb_expr(lb, argument);
    }
    optional = lb_refresh(lb, receiver, optional);
    if (!lb->ok) {
        return LB_FAIL;
    }
    MirBuilder *b = &lb->b;
    const MirValue present = mir_b_emit(b, MOP_OptIsSome, &optional.v, 1, (MirImm){0}, MIR_BOOL);
    const MirBlock yes = mir_b_new_block(b);
    const MirBlock no = mir_b_new_block(b);
    mir_b_br_if(b, present, yes, NULL, 0, no, NULL, 0);
    mir_b_seal_block(b, yes);
    mir_b_seal_block(b, no);
    const MirBlock join = mir_b_new_block(b);
    const MirValue result = mir_b_add_block_param(b, join, payload_ty, owns ? MM_MOVE : MM_BORROW);

    mir_b_switch_to(b, yes);
    const MirValue payload = lop_payload(lb, optional, payload_ty);
    if (fallback.owned) {
        lb_drop(lb, fallback.v);
    }
    mir_b_br(b, join, &payload, 1);

    mir_b_switch_to(b, no);
    MirValue other = fallback.v;
    if (!is_plain) {
        other = mir_b_emit(b, MOP_OptUnwrap, &fallback.v, 1, (MirImm){0}, payload_ty);
    } else if (owns && !fallback.owned) {
        other = lb_copy(lb, fallback.v);
    }
    if (optional.owned) {
        lb_drop(lb, optional.v);
    }
    mir_b_br(b, join, &other, 1);

    mir_b_seal_block(b, join);
    mir_b_switch_to(b, join);
    return (LbVal){result, owns};
}

bool lb_optional_method(Lb *lb, const MsExpr *e, MsTy receiver_ty, LbVal *out) {
    const MirTy optional_ty = lb_mir_ty(lb, receiver_ty);
    if (optional_ty == MIR_NONE || mir_ty_data(lb->m, optional_ty)->kind != MK_OPT) {
        return false;
    }
    const MsExpr *callee = e->u.call.callee;
    if (e->u.call.args.len != 1 || !ms_name_is(lb->c->names, callee->u.member.name, "get_or")) {
        return false;
    }
    const MirTy payload_ty = mir_ty_data(lb->m, optional_ty)->elem;
    *out = lop_get_or(lb, callee->u.member.left, e->u.call.args.ptr[0].value, payload_ty);
    return true;
}

bool lb_clone_method(Lb *lb, const MsExpr *e, LbVal *out) {
    const MsExpr *callee = e->u.call.callee;
    if (e->u.call.args.len != 0 || !ms_name_is(lb->c->names, callee->u.member.name, "clone")) {
        return false;
    }
    const LbVal value = lb_expr(lb, callee->u.member.left);
    if (!lb->ok) {
        *out = LB_FAIL;
        return true;
    }
    const MirValue copy = lb_copy(lb, value.v);
    if (value.owned) {
        lb_drop(lb, value.v);
    }
    *out = (LbVal){copy, true};
    return true;
}
