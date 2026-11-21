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
    if (element != MIR_INT && element != MIR_FLOAT && element != MIR_BOOL && element != MIR_STR) {
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
        return lb_unsupported(lb);
    }
    MirValue *values = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)items->len + 1);
    for (uint32_t i = 0; i < items->len && lb->ok; i++) {
        values[i] = mir_ty_data(lb->m, ty)->elem == MIR_STR ? lb_move_argument(lb, items->ptr[i]) : lb_expr(lb, items->ptr[i]).v; // the list owns its Strings
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    return (LbVal){mir_b_emit(&lb->b, MOP_ListLit, values, items->len, (MirImm){0}, ty), true};
}

/* `list[index]`: the list is borrowed for the read, and dropped after it when it is a temporary. */
LbVal lst_index(Lb *lb, const MsExpr *e) {
    const MsExpr *left = NULL;
    const MsExpr *at = NULL;
    if (!ms_expr_index(e, &left, &at)) {
        return lb_unsupported(lb);
    }
    const LbVal list = lb_expr(lb, left);
    if (lb->ok && lb_is_map(lb, mir_b_ty(&lb->b, list.v))) {
        return lm_index(lb, list, at);
    }
    if (!lb->ok || !lb_is_list(lb, mir_b_ty(&lb->b, list.v))) {
        return lb_unsupported(lb);
    }
    const LbVal index = lb_expr(lb, at);
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirValue args[2] = {list.v, index.v};
    const MirTy element = mir_ty_data(lb->m, mir_b_ty(&lb->b, list.v))->elem;
    const MirValue item = mir_b_emit(&lb->b, MOP_ListGet, args, 2, (MirImm){0}, element);
    if (list.owned) {
        lb_drop(lb, list.v);
    }
    return (LbVal){item, false};
}

/* `for x in list`: a counter from 0 below the list's length, which is read once before the loop, and
 * the element read in place at each step. The loop holds the list in a variable; a list the loop
 * made (a literal, a call result) is owned by a scope around the whole loop. */
void lst_for(Lb *lb, const MsStmt *s) {
    const uint32_t binding = lb->binding_at[s->id];
    if (binding == MS_NONE) {
        lb->ok = false;
        return;
    }
    const uint32_t outer = lscope_push(&lb->scopes);
    const LbVal list = lb_expr(lb, s->u.each.iter);
    if (!lb->ok || !lb_is_list(lb, mir_b_ty(&lb->b, list.v))) {
        lb->ok = false;
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

static bool lst_is(MsStr name, const char *text) {
    return strlen(text) == name.len && memcmp(name.ptr, text, name.len) == 0;
}

/* `list.get_or(index, default)`: the element when `index` (negative counts from the end) is in range,
 * else `default`, which is evaluated first. */
static LbVal lst_get_or(Lb *lb, MirValue list, const MsExpr *index_expr, const MsExpr *default_expr) {
    const LbVal index = lb_expr(lb, index_expr);
    const LbVal fallback = lb->ok ? lb_expr_plain(lb, default_expr) : LB_FAIL; // the checker's `some` wrap is the native's own
    const MirTy element = mir_ty_data(lb->m, mir_b_ty(&lb->b, list))->elem;
    if (!lb->ok || fallback.owned || mir_b_ty(&lb->b, fallback.v) != element) { // an Optional default is not the native's plain shape
        return lb_unsupported(lb);
    }
    const MirValue length = mir_b_emit(&lb->b, MOP_ListLen, &list, 1, (MirImm){0}, MIR_INT);
    const MirValue zero = mir_b_iconst(&lb->b, 0);
    const MirValue negative = mir_b_icmp(&lb->b, MCC_LT, index.v, zero);
    const MirValue wrapped = mir_b_binop(&lb->b, MOP_IAdd, index.v, length);
    const MirValue at = mir_b_select(&lb->b, negative, wrapped, index.v);
    const MirValue not_below = mir_b_icmp(&lb->b, MCC_GE, at, zero);
    const MirValue below = mir_b_icmp(&lb->b, MCC_LT, at, length);
    const MirValue inside = mir_b_binop(&lb->b, MOP_And, not_below, below);
    const MirBlock found = mir_b_new_block(&lb->b);
    const MirBlock missing = mir_b_new_block(&lb->b);
    const MirBlock join = mir_b_new_block(&lb->b);
    const MirValue result = mir_b_add_block_param(&lb->b, join, element, MM_BORROW);
    mir_b_br_if(&lb->b, inside, found, NULL, 0, missing, NULL, 0);
    mir_b_seal_block(&lb->b, found);
    mir_b_seal_block(&lb->b, missing);
    lb_enter(lb, found);
    const MirValue args[2] = {list, at};
    const MirValue item = mir_b_emit(&lb->b, MOP_ListGet, args, 2, (MirImm){0}, element);
    mir_b_br(&lb->b, join, &item, 1);
    lb_enter(lb, missing);
    mir_b_br(&lb->b, join, &fallback.v, 1);
    mir_b_seal_block(&lb->b, join);
    lb_enter(lb, join);
    return (LbVal){result, false};
}

/* `xs.append(value)` on a `var` list this function owns: the push yields the updated list, which the variable
 * holds from then on. */
static LbVal lst_append(Lb *lb, const MsExpr *e) {
    const MsExpr *receiver = e->u.call.callee->u.member.left;
    if (receiver->kind != MS_E_NAME || lb->facts->res_kind[receiver->id] != MS_RES_BINDING) {
        return lb_unsupported(lb);
    }
    const uint32_t binding = lb->facts->res_ref[receiver->id];
    if (lb->var_of[binding] == MIR_NONE || !lb_var_owned(lb, binding)) {
        return lb_unsupported(lb);
    }
    const MirValue list = mir_b_use_var(&lb->b, lb->var_of[binding]);
    const MirTy list_ty = mir_b_ty(&lb->b, list);
    const MirTy element = lb_is_list(lb, list_ty) ? mir_ty_data(lb->m, list_ty)->elem : MIR_NONE;
    const LbVal value = lb_expr(lb, e->u.call.args.ptr[0].value);
    if (!lb->ok || element == MIR_NONE || value.owned || mir_b_ty(&lb->b, value.v) != element) {
        return lb_unsupported(lb);
    }
    (void)mir_b_emit(&lb->b, MOP_TypeDesc, NULL, 0, (MirImm){.tag = MI_TY, .a = element}, MIR_PTR);
    const MirValue args[2] = {list, value.v};
    const MirValue pushed = mir_b_emit(&lb->b, MOP_ListPush, args, 2, (MirImm){0}, list_ty);
    mir_b_def_var(&lb->b, lb->var_of[binding], pushed);
    return (LbVal){mir_b_unit(&lb->b), false};
}

/* The natives of a list that read it: `length`, `is_empty`, `get` and `get_or`. The receiver is
 * borrowed; a temporary receiver is dropped after the read (the element needs no drop). Any other
 * method, and a receiver that is not a list, is left to the Rust lowering. */
LbVal lst_method(Lb *lb, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    const MsStr name = ms_name(lb->c->names, callee->u.member.name);
    const uint32_t count = e->u.call.args.len;
    if (lst_is(name, "append") && count == 1) {
        return lst_append(lb, e);
    }
    bool known = false;
    if (lst_is(name, "length") || lst_is(name, "is_empty")) {
        known = count == 0;
    } else if (lst_is(name, "get")) {
        known = count == 1;
    } else if (lst_is(name, "get_or")) {
        known = count == 2;
    }
    if (!known || !lb_is_list(lb, lb_mir_ty(lb, lb->facts->call_receiver[e->id]))) {
        return lb_unsupported(lb);
    }
    const LbVal list = lb_expr(lb, callee->u.member.left);
    if (!lb->ok) {
        return LB_FAIL;
    }
    LbVal result;
    if (lst_is(name, "get_or")) {
        result = lst_get_or(lb, list.v, e->u.call.args.ptr[0].value, e->u.call.args.ptr[1].value);
    } else if (lst_is(name, "get")) {
        const LbVal at = lb_expr(lb, e->u.call.args.ptr[0].value);
        const MirValue args[2] = {list.v, at.v};
        const MirTy element = mir_ty_data(lb->m, mir_b_ty(&lb->b, list.v))->elem;
        result = (LbVal){mir_b_emit(&lb->b, MOP_ListGet, args, 2, (MirImm){0}, element), false};
    } else {
        const MirValue length = mir_b_emit(&lb->b, MOP_ListLen, &list.v, 1, (MirImm){0}, MIR_INT);
        result = (LbVal){length, false};
        if (lst_is(name, "is_empty")) {
            result.v = mir_b_icmp(&lb->b, MCC_EQ, length, mir_b_iconst(&lb->b, 0));
        }
    }
    if (lb->ok && list.owned) {
        lb_hold_temp(lb, list.v); // a temporary receiver lives to the end of the statement
    }
    return lb->ok ? result : LB_FAIL;
}
