/* List methods that call a function value on elements. `map` and `filter` are each a loop over the receiver that
 * builds the result list, as the Rust lowering emits (crates/ms-lower native/mutate.rs `list_higher_order`); `sorted`
 * hands the runtime's sort a function that compares two element slots (native/list.rs `list_sorted`). */
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

/* The function the runtime's sort calls on two element slots: loads both and asks the source comparison, whose
 * type is `comparison`. One per call, internal to the module. */
static uint32_t le_sort_compare(Lb *lb, MirTy comparison, MirTy element) {
    MirBuilder outer = lb->b;
    const MirParam params[3] = {{comparison, MM_BORROW}, {MIR_PTR, MM_BORROW}, {MIR_PTR, MM_BORROW}};
    mir_b_init(&lb->b, lb->m, lb_unique_name(lb, (MsStr){"sort.cmp", 8}), params, 3, MIR_INT);
    MirValue args[3];
    mir_b_params(&lb->b, args, 3);
    const MirValue operands[3] = {args[0], lb_load(lb, args[1], element), lb_load(lb, args[2], element)};
    mir_b_ret(&lb->b, mir_b_emit(&lb->b, MOP_CallInd, operands, 3, (MirImm){0}, MIR_INT));
    MirFunc f = {0};
    const bool built = mir_b_into_func(&lb->b, &f);
    lb->b = outer;
    f.linkage = ML_INTERNAL;
    f.sort = MSORT_GENERIC;
    return built ? mir_add_func(lb->m, &f) : MIR_NONE;
}

/* `list.sorted(comparison)`: the runtime's stable sort of a copy, ordered by the sign the comparison returns. */
static LbVal le_sorted(Lb *lb, LbVal list, LbVal comparison, MirTy element) {
    MirBuilder *b = &lb->b;
    const MirTy list_ty = mir_b_ty(b, list.v);
    const MirTy comparison_ty = mir_b_ty(b, comparison.v);
    const uint32_t compare = le_sort_compare(lb, comparison_ty, element);
    if (compare == MIR_NONE) {
        return LB_UNSUPPORTED(lb);
    }
    const MirValue address = mir_b_emit(b, MOP_FuncAddr, NULL, 0, (MirImm){.tag = MI_FUNC, .a = compare}, MIR_PTR);
    const MirValue descriptor = mir_b_emit(b, MOP_TypeDesc, NULL, 0, (MirImm){.tag = MI_TY, .a = element}, MIR_PTR);
    const MirTy params[4] = {list_ty, MIR_PTR, MIR_PTR, comparison_ty};
    const uint32_t sort = lb_runtime_extern(lb, "msrt_list_sorted", params, 4, list_ty, MR_LIST_SORTED, false);
    const MirValue operands[4] = {list.v, descriptor, address, comparison.v};
    const MirValue sorted = mir_b_call_rt(b, sort, operands, 4);
    if (list.owned) {
        lb_drop(lb, list.v); // the sort copied what it kept
    }
    if (comparison.owned) {
        (void)mir_b_emit(b, MOP_Drop, &comparison.v, 1, (MirImm){0}, MIR_NONE);
    }
    return (LbVal){sorted, true};
}

bool lb_each_method(Lb *lb, const MsExpr *e, MsTy receiver_ty, LbVal *out) {
    const MsExpr *callee = e->u.call.callee;
    const bool is_map = ms_name_is(lb->c->names, callee->u.member.name, "map");
    const bool is_sorted = ms_name_is(lb->c->names, callee->u.member.name, "sorted");
    const MirTy list_ty = lb_mir_ty(lb, receiver_ty);
    if (!lb_is_list(lb, list_ty) || e->u.call.args.len != 1 ||
        !(is_map || is_sorted || ms_name_is(lb->c->names, callee->u.member.name, "filter"))) {
        return false;
    }
    *out = LB_FAIL;
    const MirTy result_ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    const MirTy element = mir_ty_data(lb->m, list_ty)->elem;
    const LbVal list = lb_expr(lb, callee->u.member.left);
    const LbVal function = lb->ok ? lb_expr(lb, e->u.call.args.ptr[0].value) : LB_FAIL;
    if (!lb->ok) {
        return true;
    }
    const MirTy function_ty = mir_b_ty(&lb->b, function.v);
    const uint32_t takes = is_sorted ? 2 : 1;
    if (!lb_is_list(lb, result_ty) || !lb_is_fn(lb, function_ty) ||
        mir_ty_data(lb->m, mir_ty_unscoped(function_ty))->nargs != takes) {
        *out = LB_UNSUPPORTED(lb);
        return true;
    }
    if (is_sorted) {
        *out = le_sorted(lb, list, function, element);
        return true;
    }
    if (list.owned) {
        lb_hold_temp(lb, list.v); // read in place by the loop: a temporary receiver lives to the end of the statement
    }
    LeLoop loop = {.list = list.v, .function = function.v, .element = element, .result_ty = result_ty, .is_map = is_map};
    *out = (LbVal){le_loop(lb, &loop), true};
    if (function.owned) {
        lb_drop(lb, function.v);
    }
    return true;
}
