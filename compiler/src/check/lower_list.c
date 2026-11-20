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
    const LbVal list = lb_expr(lb, e->u.bin.left);
    if (!lb->ok || !lb_is_list(lb, mir_b_ty(&lb->b, list.v))) {
        return lb_unsupported(lb);
    }
    const LbVal index = lb_expr(lb, e->u.bin.right);
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
