/* Records in the lowering (crates/ms-lower: `lower_ty` for `Kind::Type`, `call.rs` construction,
 * `expr.rs` member access): a `type` without type parameters whose fields are scalars or Strings is a MIR
 * `type`; `Name(field: value, ...)` is `type.new` and `value.field` is `type.get`. A record with a
 * field that owns something (a String, a list, another owner) is left to the Rust lowering until
 * the ownership side lands. */
#include "ms/lower_internal.h"

/* The MIR type of record `ty`, declared on first use; MIR_NONE when it is not one this pass lowers. */
MirTy lr_type(Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    if (ms_ty_kind(tys, ty) != MS_K_TYPE || tys->nargs[ty] != 0 || tys->def[ty] == 0 || tys->builtin[ty] != 0) {
        return MIR_NONE;
    }
    const MsSymId sym = tys->def[ty] - 1;
    if (sym >= lb->c->defs_cap || lb->c->syms.kind[sym] != MS_SYM_TYPE) {
        return MIR_NONE;
    }
    if (lb->type_of[ty] != MIR_NONE) {
        return lb->type_of[ty];
    }
    // A record that reaches itself through a field (`next: Node?`) is not lowered: the type being
    // declared is marked while its fields are, so the cycle ends at the second visit.
    if (lb->declaring[ty]) {
        return MIR_NONE;
    }
    const MsDef *def = &lb->c->defs[sym];
    MirField *fields = MS_NEW_N(&lb->m->arena, MirField, (size_t)def->nfields + 1);
    lb->declaring[ty] = true;
    for (uint32_t i = 0; i < def->nfields; i++) {
        const MirTy field = lb_mir_ty(lb, def->fields[i].ty);
        if (field == MIR_NONE || (field != MIR_STR && mir_needs_drop(lb->m, field))) { // a String field only
            lb->declaring[ty] = false;
            return MIR_NONE;
        }
        fields[i] = (MirField){mir_name(lb->m, ms_name(lb->c->names, def->fields[i].name).ptr,
                                        ms_name(lb->c->names, def->fields[i].name).len),
                               field};
    }
    lb->declaring[ty] = false;
    MsBuf text = {0};
    ms_ty_show(&text, lb->c->names, tys, ty);
    const uint32_t id = mir_add_type(lb->m, mir_name(lb->m, text.data, text.len));
    ms_buf_free(&text);
    lb->m->type_defs[id].fields = fields;
    lb->m->type_defs[id].nfields = def->nfields;
    lb->type_of[ty] = mir_ty_type(lb->m, id);
    return lb->type_of[ty];
}

/* `Name(field: value, ...)`: the checker admitted it with every field given in order. */
LbVal lr_construct(Lb *lb, const MsExpr *call) {
    const MirTy ty = lb_mir_ty(lb, lb->facts->expr_ty[call->id]); // through the class check: a resource is not lowered
    const uint32_t count = call->u.call.args.len;
    if (ty == MIR_NONE || count != lb->m->type_defs[mir_ty_data(lb->m, ty)->id].nfields) {
        return lb_unsupported(lb); // a field left to its default is not lowered yet
    }
    MirValue *values = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 1);
    for (uint32_t i = 0; i < count && lb->ok; i++) {
        const MsExpr *arg = call->u.call.args.ptr[i].value;
        const MirTy field_ty = lb->m->type_defs[mir_ty_data(lb->m, ty)->id].fields[i].ty;
        values[i] = field_ty == MIR_STR ? lb_move_argument(lb, arg) : lb_expr(lb, arg).v;
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirImm imm = {.tag = MI_TYPE, .a = mir_ty_data(lb->m, ty)->id};
    return (LbVal){mir_b_emit(&lb->b, MOP_TypeNew, values, count, imm, ty), lb_owns(lb, ty)};
}

/* `record.field` where the checker resolved a field. */
LbVal lr_field(Lb *lb, const MsExpr *e) {
    if (lb->facts->res_kind[e->id] != MS_RES_FIELD) {
        return lb_unsupported(lb);
    }
    const LbVal holder = lb_expr(lb, e->u.member.left);
    if (!lb->ok) {
        return LB_FAIL;
    }
    if (holder.owned) {
        return lb_unsupported(lb); // a field of a temporary: the temporary is released after the read
    }
    const MirTyData *record = mir_ty_data(lb->m, mir_b_ty(&lb->b, holder.v));
    const uint32_t index = lb->facts->res_ref[e->id];
    if (record->kind != MK_TYPE || index >= lb->m->type_defs[record->id].nfields) {
        return lb_unsupported(lb);
    }
    const MirTy field = lb->m->type_defs[record->id].fields[index].ty;
    const MirImm imm = {.tag = MI_FIELD, .a = record->id, .b = index};
    return (LbVal){mir_b_emit(&lb->b, MOP_TypeGet, &holder.v, 1, imm, field), false};
}
