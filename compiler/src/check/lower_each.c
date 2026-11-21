/* List methods that call a function value on each element: `map` and `filter`. Each is a loop over the receiver that
 * builds the result list, as the Rust lowering emits (crates/ms-lower native/mutate.rs `list_higher_order`). */
#include "ms/lower_internal.h"

/* What one loop over a list reads and writes. */
typedef struct LeLoop {
    MirValue list;     /* the receiver, borrowed for the whole loop */
    MirValue function; /* the function value called on each element */
    MirTy element;     /* the receiver's element type */
    MirTy result_ty;   /* the list the loop builds */
    MirVar built;      /* that list so far */
    bool is_map;       /* `map` keeps what the function returns; `filter` keeps the elements it accepts */
} LeLoop;

/* One step: calls the function on `item` and appends to the list being built. */
static void le_step(Lb *lb, const LeLoop *loop, MirValue item) {
    MirBuilder *b = &lb->b;
    const MirTy returned = mir_ty_data(lb->m, mir_ty_unscoped(mir_b_ty(b, loop->function)))->elem;
    const MirValue operands[2] = {loop->function, item};
    const MirValue answer = mir_b_emit(b, MOP_CallInd, operands, 2, (MirImm){0}, returned);
    if (loop->is_map) {
        const MirValue pushed[2] = {mir_b_use_var(b, loop->built), answer};
        mir_b_def_var(b, loop->built, mir_b_emit(b, MOP_ListPush, pushed, 2, (MirImm){0}, loop->result_ty));
        return;
    }
    const MirBlock keep = mir_b_new_block(b);
    const MirBlock skip = mir_b_new_block(b);
    mir_b_br_if(b, answer, keep, NULL, 0, skip, NULL, 0);
    mir_b_seal_block(b, keep);
    lb_enter(lb, keep);
    const MirValue kept = lb_owns(lb, loop->element) ? lb_copy(lb, item) : item; // the new list owns its elements
    const MirValue pushed[2] = {mir_b_use_var(b, loop->built), kept};
    mir_b_def_var(b, loop->built, mir_b_emit(b, MOP_ListPush, pushed, 2, (MirImm){0}, loop->result_ty));
    mir_b_br(b, skip, NULL, 0);
    mir_b_seal_block(b, skip);
    lb_enter(lb, skip);
}

/* The loop: a counter from 0 below the receiver's length, read once before it. Returns the list built. */
static MirValue le_loop(Lb *lb, LeLoop *loop) {
    MirBuilder *b = &lb->b;
    const MirValue length = mir_b_emit(b, MOP_ListLen, &loop->list, 1, (MirImm){0}, MIR_INT);
    const MirValue zero = mir_b_iconst(b, 0);
    const MirValue capacity = loop->is_map ? length : zero; // a map's result is as long as its receiver
    loop->built = mir_b_declare_var(b, loop->result_ty, MM_MOVE);
    mir_b_def_var(b, loop->built, mir_b_emit(b, MOP_ListNew, &capacity, 1, (MirImm){0}, loop->result_ty));
    const MirVar counter = mir_b_declare_var(b, MIR_INT, MM_BORROW);
    mir_b_def_var(b, counter, zero);
    const MirBlock header = mir_b_new_block(b);
    const MirBlock body = mir_b_new_block(b);
    const MirBlock exit = mir_b_new_block(b);
    mir_b_br(b, header, NULL, 0);
    lb_enter(lb, header);
    const MirValue index = mir_b_use_var(b, counter);
    mir_b_br_if(b, mir_b_icmp(b, MCC_LT, index, length), body, NULL, 0, exit, NULL, 0);
    mir_b_seal_block(b, body);
    lb_enter(lb, body);
    const MirValue at[2] = {loop->list, index};
    le_step(lb, loop, mir_b_emit(b, MOP_ListGet, at, 2, (MirImm){0}, loop->element));
    mir_b_def_var(b, counter, mir_b_binop(b, MOP_IAdd, mir_b_use_var(b, counter), mir_b_iconst(b, 1)));
    mir_b_br(b, header, NULL, 0);
    mir_b_seal_block(b, header);
    mir_b_seal_block(b, exit);
    lb_enter(lb, exit);
    return mir_b_use_var(b, loop->built);
}

bool lb_each_method(Lb *lb, const MsExpr *e, MsTy receiver_ty, LbVal *out) {
    const MsExpr *callee = e->u.call.callee;
    const bool is_map = ms_name_is(lb->c->names, callee->u.member.name, "map");
    const MirTy list_ty = lb_mir_ty(lb, receiver_ty);
    if (!lb_is_list(lb, list_ty) || e->u.call.args.len != 1 ||
        !(is_map || ms_name_is(lb->c->names, callee->u.member.name, "filter"))) {
        return false;
    }
    *out = LB_FAIL;
    const MirTy result_ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    const LbVal list = lb_expr(lb, callee->u.member.left);
    const LbVal function = lb->ok ? lb_expr(lb, e->u.call.args.ptr[0].value) : LB_FAIL;
    if (!lb->ok) {
        return true;
    }
    const MirTy function_ty = mir_b_ty(&lb->b, function.v);
    if (!lb_is_list(lb, result_ty) || !lb_is_fn(lb, function_ty) ||
        mir_ty_data(lb->m, mir_ty_unscoped(function_ty))->nargs != 1) {
        *out = LB_UNSUPPORTED(lb);
        return true;
    }
    if (list.owned) {
        lb_hold_temp(lb, list.v); // read in place by the loop: a temporary receiver lives to the end of the statement
    }
    LeLoop loop = {.list = list.v, .function = function.v, .element = mir_ty_data(lb->m, list_ty)->elem,
                   .result_ty = result_ty, .is_map = is_map};
    const MirValue built = le_loop(lb, &loop);
    if (function.owned) {
        lb_drop(lb, function.v);
    }
    *out = (LbVal){built, true};
    return true;
}
