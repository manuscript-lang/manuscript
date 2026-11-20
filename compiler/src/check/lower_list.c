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
    if (element != MIR_INT && element != MIR_FLOAT && element != MIR_BOOL) {
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
        values[i] = lb_expr(lb, items->ptr[i]).v;
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
