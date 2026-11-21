/* Lists in the lowering: a `List[T]` of a scalar element is the MIR `list<T>`, a literal is
 * `list.lit` and `xs[i]` is `list.get`. A list is an owned object: a local made from a literal or
 * a call owns it (its scope drops it), a parameter borrows it. Lists of owned elements, `var`
 * lists and the list methods wait for the ownership side of the checker. */
#include "ms/lower_internal.h"

/* The MIR type of a list of scalars, else MIR_NONE. */
MirTy lst_type(Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    if (!ms_ty_is(tys, ty, MS_BI_LIST) || tys->nargs[ty] != 1) {
        return MIR_NONE;
    }
    const MirTy element = lb_mir_ty(lb, ms_ty_args(tys, ty)[0]);
    if (element != MIR_INT && element != MIR_FLOAT && element != MIR_BOOL && element != MIR_STR && !lb_is_list(lb, element)) {
        return MIR_NONE;
    }
    return mir_ty_list(lb->m, element);
}

bool lb_is_list(const Lb *lb, MirTy ty) {
    return ty != MIR_NONE && mir_ty_data(lb->m, ty)->kind == MK_LIST;
}

/* `[a, b, c]`: every entry is a scalar, so the list owns plain values only. */
LbVal lst_literal(Lb *lb, const MsExpr *e) {
    const MirTy ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    const MsExprs *items = &e->u.list;
    if (!lb_is_list(lb, ty)) {
        return LB_UNSUPPORTED(lb);
    }
    MirValue *values = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)items->len + 1);
    for (uint32_t i = 0; i < items->len && lb->ok; i++) {
        values[i] = lb_owns(lb, mir_ty_data(lb->m, ty)->elem) ? lb_move_argument(lb, items->ptr[i]) : lb_expr(lb, items->ptr[i]).v; // the list owns its Strings
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    return (LbVal){mir_b_emit(&lb->b, MOP_ListLit, values, items->len, (MirImm){0}, ty), true};
}

/* `List[T]()`: a list literal of no items. */
LbVal lst_empty(Lb *lb, MirTy ty) {
    return (LbVal){mir_b_emit(&lb->b, MOP_ListLit, NULL, 0, (MirImm){0}, ty), true};
}

/* `list[index]`: the list is borrowed for the read, and dropped after it when it is a temporary. */
LbVal lst_index(Lb *lb, const MsExpr *e) {
    MsExpr *left = NULL;
    MsExpr *at = NULL;
    if (!ms_expr_index(e, &left, &at)) {
        return LB_UNSUPPORTED(lb);
    }
    return lst_get(lb, left, at);
}

/* `list[at]`: one element read in place. */
LbVal lst_get(Lb *lb, const MsExpr *left, const MsExpr *at) {
    const LbVal list = lb_expr(lb, left);
    if (lb->ok && lb_is_map(lb, mir_b_ty(&lb->b, list.v))) {
        return lm_index(lb, list, at);
    }
    const bool bytes = lb->ok && mir_b_ty(&lb->b, list.v) == MIR_BYTES;
    if (!lb->ok || !(bytes || lb_is_list(lb, mir_b_ty(&lb->b, list.v)))) {
        return LB_UNSUPPORTED(lb);
    }
    const LbVal index = lb_expr(lb, at);
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirValue args[2] = {list.v, index.v};
    const MirTy element = bytes ? MIR_UINT8 : mir_ty_data(lb->m, mir_b_ty(&lb->b, list.v))->elem;
    const MirValue item = mir_b_emit(&lb->b, MOP_ListGet, args, 2, (MirImm){0}, element);
    if (list.owned) {
        lb_drop(lb, list.v);
    }
    return (LbVal){item, false};
}

/* The element type of a list or of Bytes (a list of bytes), or MIR_NONE. */
static MirTy lst_element_ty(const Lb *lb, MirTy ty) {
    if (ty == MIR_BYTES) {
        return MIR_UINT8;
    }
    return lb_is_list(lb, ty) ? mir_ty_data(lb->m, ty)->elem : MIR_NONE;
}

/* `list.get_or(index, fallback)`: the element when `index` (counted from the end when negative) is in range, else
 * the fallback. The result is the caller's own value, so an owning element is copied out of the list. */
static LbVal lst_get_or(Lb *lb, MirValue list, MirValue index, LbVal fallback, MirTy element) {
    MirBuilder *b = &lb->b;
    const bool owns = lb_owns(lb, element);
    const MirValue length = mir_b_emit(b, MOP_ListLen, &list, 1, (MirImm){0}, MIR_INT);
    const MirValue zero = mir_b_iconst(b, 0);
    const MirValue is_negative = mir_b_icmp(b, MCC_LT, index, zero);
    const MirValue from_end = mir_b_binop(b, MOP_IAdd, index, length);
    const MirValue at = mir_b_select(b, is_negative, from_end, index);
    const MirValue above = mir_b_icmp(b, MCC_GE, at, zero);
    const MirValue below = mir_b_icmp(b, MCC_LT, at, length);
    const MirValue in_range = mir_b_binop(b, MOP_And, above, below);
    const MirBlock hit = mir_b_new_block(b);
    const MirBlock miss = mir_b_new_block(b);
    mir_b_br_if(b, in_range, hit, NULL, 0, miss, NULL, 0);
    mir_b_seal_block(b, hit);
    mir_b_seal_block(b, miss);
    const MirBlock join = mir_b_new_block(b);
    const MirValue result = mir_b_add_block_param(b, join, element, owns ? MM_MOVE : MM_BORROW);

    mir_b_switch_to(b, hit);
    const MirValue operands[2] = {list, at};
    MirValue item = mir_b_emit(b, MOP_ListGet, operands, 2, (MirImm){0}, element);
    if (owns) {
        item = lb_copy(lb, item);
    }
    if (fallback.owned) {
        lb_drop(lb, fallback.v); // the fallback was evaluated and is not used on this path
    }
    mir_b_br(b, join, &item, 1);

    mir_b_switch_to(b, miss);
    const MirValue other = owns && !fallback.owned ? lb_copy(lb, fallback.v) : fallback.v;
    mir_b_br(b, join, &other, 1);

    mir_b_seal_block(b, join);
    mir_b_switch_to(b, join);
    return (LbVal){result, owns};
}

bool lst_read_method(Lb *lb, const MsExpr *e, MsTy receiver_ty, LbVal *out) {
    const MirTy element = lst_element_ty(lb, lb_mir_ty(lb, receiver_ty));
    const MsExpr *callee = e->u.call.callee;
    const MsArg *args = e->u.call.args.ptr;
    const uint32_t nargs = e->u.call.args.len;
    const bool has_fallback = nargs == 2 && ms_name_is(lb->c->names, callee->u.member.name, "get_or");
    const bool is_get = nargs == 1 && (ms_name_is(lb->c->names, callee->u.member.name, "get") ||
                                           ms_name_is(lb->c->names, callee->u.member.name, "get_or"));
    if (element == MIR_NONE || !(is_get || has_fallback)) {
        return false;
    }
    *out = LB_FAIL;
    if (args[0].has_name || (has_fallback && !lb->facts->some_wrap[args[1].value->id])) {
        *out = LB_UNSUPPORTED(lb); // arguments out of order, or a fallback that is itself an Optional
        return true;
    }
    LbVal list = lb_expr(lb, callee->u.member.left);
    const LbVal index = lb->ok ? lb_expr(lb, args[0].value) : LB_FAIL;
    const LbVal fallback = lb->ok && has_fallback ? lb_expr_plain(lb, args[1].value) : LB_FAIL;
    list = lb_refresh(lb, callee->u.member.left, list);
    if (!lb->ok) {
        return true;
    }
    if (list.owned) {
        lb_hold_temp(lb, list.v); // the element is read in place: a temporary list lives to the end of the statement
    }
    if (has_fallback) {
        *out = lst_get_or(lb, list.v, index.v, fallback, element);
    } else {
        const MirValue operands[2] = {list.v, index.v};
        *out = (LbVal){mir_b_emit(&lb->b, MOP_ListGet, operands, 2, (MirImm){0}, element), false};
    }
    return true;
}

/* `for x in list`: a counter from 0 below the list's length, which is read once before the loop, and
 * the element read in place at each step. The loop holds the list in a variable; a list the loop
 * made (a literal, a call result) is owned by a scope around the whole loop. */
void lst_for(Lb *lb, const MsStmt *s) {
    const uint32_t binding = lb->binding_at[s->id];
    if (binding == MS_NONE) {
        (void)LB_UNSUPPORTED(lb);
        return;
    }
    const uint32_t outer = lscope_push(&lb->scopes);
    lb->iterable = s->u.each.iter;
    const LbVal list = lb_expr(lb, s->u.each.iter);
    lb->iterable = NULL;
    if (!lb->ok || !lb_is_list(lb, mir_b_ty(&lb->b, list.v))) {
        (void)LB_UNSUPPORTED(lb);
        return;
    }
    if (list.owned) {
        lscope_own(&lb->scopes, list.v, 0);
    }
    const MirTy list_ty = mir_b_ty(&lb->b, list.v);
    const MirVar held = mir_b_declare_var(&lb->b, list_ty, MM_BORROW);
    mir_b_def_var(&lb->b, held, list.v);
    const MirValue start = mir_b_iconst(&lb->b, 0);
    const MirValue current_list = mir_b_use_var(&lb->b, held);
    const MirValue length = mir_b_emit(&lb->b, MOP_ListLen, &current_list, 1, (MirImm){0}, MIR_INT);
    const MirValue one = mir_b_iconst(&lb->b, 1);
    const MirVar counter = mir_b_declare_var(&lb->b, MIR_INT, MM_BORROW);
    mir_b_def_var(&lb->b, counter, start);
    const MirBlock header = mir_b_new_block(&lb->b);
    const MirBlock body = mir_b_new_block(&lb->b);
    const MirBlock exit = mir_b_new_block(&lb->b);
    mir_b_br(&lb->b, header, NULL, 0);
    lb_enter(lb, header);
    const MirValue below = mir_b_icmp(&lb->b, MCC_LT, mir_b_use_var(&lb->b, counter), length);
    mir_b_br_if(&lb->b, below, body, NULL, 0, exit, NULL, 0);
    mir_b_seal_block(&lb->b, body);
    lb_enter(lb, body);
    const MirValue at = mir_b_use_var(&lb->b, counter);
    const MirValue items = mir_b_use_var(&lb->b, held);
    const MirValue args[2] = {items, at};
    lb->value_of[binding] = mir_b_emit(&lb->b, MOP_ListGet, args, 2, (MirImm){0}, mir_ty_data(lb->m, list_ty)->elem);
    LbLoop here = {.exit = exit, .outer = lb->loop, .scope = lb->scopes.depth};
    lb->loop = &here;
    (void)lb_scoped(lb, &s->u.each.body);
    lb->loop = here.outer;
    if (!lb->dead) {
        mir_b_br(&lb->b, lb_step_block(lb, &here), NULL, 0);
    }
    if (here.stepped) {
        mir_b_seal_block(&lb->b, here.next);
        lb_enter(lb, here.next);
        mir_b_def_var(&lb->b, counter, mir_b_binop(&lb->b, MOP_IAdd, mir_b_use_var(&lb->b, counter), one));
        mir_b_br(&lb->b, header, NULL, 0);
    }
    mir_b_seal_block(&lb->b, header);
    mir_b_seal_block(&lb->b, exit);
    lb_enter(lb, exit);
    lscope_pop(&lb->scopes, true);
    (void)outer;
}
