/* Records in the lowering (crates/ms-lower: `lower_ty` for `Kind::Type`, `call.rs` construction,
 * `expr.rs` member access): a `type` whose fields all have MIR types is a
 * MIR `type` (one per instance of a generic record, its fields at the instance's arguments); `Name(field: value, ...)` is `type.new` (a field left out takes its default) and
 * `value.field` is `type.get`. */
#include "check_body.h"
#include "ms/lower_internal.h"

#define LR_STORE_DEPTH 8 /* the longest field chain of a store that is lowered */

/* The MIR type of record `ty`, declared on first use; MIR_NONE when it is not one this pass lowers. */
MirTy lr_type(Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    if (ms_ty_kind(tys, ty) != MS_K_TYPE || tys->def[ty] == 0) {
        return MIR_NONE;
    }
    const MsSymId sym = tys->def[ty] - 1;
    if (sym >= lb->c->defs_cap || lb->c->syms.kind[sym] != MS_SYM_TYPE || tys->nargs[ty] != lb->c->defs[sym].nvars) {
        return MIR_NONE;
    }
    if (lb->type_of[ty] == LB_TYPE_PENDING) {
        return MIR_NONE; // a record that holds itself (`next: Node?`) is not lowered
    }
    if (lb->type_of[ty] != MIR_NONE) {
        return lb->type_of[ty];
    }
    const MsDef *def = &lb->c->defs[sym];
    MirField *fields = MS_NEW_N(&lb->m->arena, MirField, (size_t)def->nfields + 1);
    lb->type_of[ty] = LB_TYPE_PENDING;
    for (uint32_t i = 0; i < def->nfields; i++) {
        const MirTy field = lb_mir_ty(lb, le_field_ty(lb, def, ty, def->fields[i].ty)); // a generic record: at its arguments
        if (field == MIR_NONE) {
            lb->type_of[ty] = MIR_NONE;
            return MIR_NONE;
        }
        fields[i] = (MirField){mir_name(lb->m, ms_name(lb->c->names, def->fields[i].name).ptr,
                                        ms_name(lb->c->names, def->fields[i].name).len),
                               field};
    }
    MsBuf text = {0};
    ms_ty_show(&text, lb->c->names, tys, ty);
    const uint32_t id = mir_add_type(lb->m, mir_name(lb->m, text.data, text.len));
    ms_buf_free(&text);
    lb->m->type_defs[id].fields = fields;
    lb->m->type_defs[id].nfields = def->nfields;
    lb->type_of[ty] = mir_ty_type(lb->m, id);
    return lb->type_of[ty];
}

/* A field left out of a construction: its default, lowered under the facts of the module that
 * declares the record (the default's nodes belong to that module). */
static MirValue lr_default(Lb *lb, const MsDecl *decl, MsSymId sym, uint32_t index, MirTy field_ty) {
    const MsExpr *def = decl->u.type.fields.ptr[index]->def;
    const MsFacts *own = lb->facts;
    const MsFacts *home = lb->c->mods[lb->c->syms.module[sym]].facts;
    if (home == NULL || home->expr_ty == NULL || home->expr_ty[def->id] == MS_TY_NONE) { // this run did not check the default (the library): nothing to lower from
        (void)LB_UNSUPPORTED(lb);
        return MIR_NONE;
    }
    lb->facts = home;
    if (lb->c->syms.module[sym] == lb->module) { // a default of another file has no position here
        lb->b.loc = lb_loc(lb, def->pos); // the rest of the statement stays at the default's position, as the Rust lowering leaves it
    }
    const MirValue value = lb_owns(lb, field_ty) ? lb_move_argument(lb, def) : lb_expr(lb, def).v;
    lb->facts = own;
    return value;
}

/* `Name(field: value, ...)`: the arguments in source order, then the default of each field left out. */
LbVal lr_construct(Lb *lb, const MsExpr *call) {
    // A construction passed as an interface has the interface type; what it builds is the concrete one.
    MsTy built = lb->facts->coerce_iface[call->id];
    if (built == MS_TY_NONE) {
        built = lb->facts->expr_ty[call->id];
    }
    const MirTy ty = lb_mir_ty(lb, built); // through the class check: a resource is not lowered
    const MsSymId sym = lb->facts->call_callee[call->id];
    if ((lb_is_map(lb, ty) || lb_is_set(lb, ty)) && call->u.call.args.len == 0) {
        return lm_empty(lb, ty); // `Map[K, V]()`, `Set[T]()`
    }
    if (lb_is_list(lb, ty) && call->u.call.args.len == 0) {
        return lst_empty(lb, ty); // `List[T]()`
    }
    if (lbd_is_builder(lb, built) && call->u.call.args.len == 0) {
        return lbd_new(lb); // `StringBuilder()`
    }
    if (ty == MIR_NONE || mir_ty_data(lb->m, ty)->kind != MK_TYPE || sym == MS_NONE) {
        return LB_UNSUPPORTED(lb);
    }
    const MsDef *def = &lb->c->defs[sym];
    const MsDecl *decl = lb->c->syms.decl[sym];
    const uint32_t nfields = lb->m->type_defs[mir_ty_data(lb->m, ty)->id].nfields;
    const uint32_t count = call->u.call.args.len;
    MsSym *names = MS_NEW_N(&lb->b.scratch, MsSym, (size_t)nfields + 1);
    bool *covered = MS_NEW_N(&lb->b.scratch, bool, (size_t)nfields + 1);
    uint32_t *slot = MS_NEW_N(&lb->b.scratch, uint32_t, (size_t)count + 1);
    for (uint32_t i = 0; i < nfields; i++) {
        names[i] = def->fields[i].name;
    }
    if (decl == NULL || def->nfields != nfields || !ms_body_bind_arguments(call, names, NULL, nfields, slot, covered)) {
        return LB_UNSUPPORTED(lb);
    }
    MirValue *values = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)nfields + 1);
    for (uint32_t i = 0; i < count && lb->ok; i++) {
        const MsExpr *arg = call->u.call.args.ptr[i].value;
        const MirTy field_ty = lb->m->type_defs[mir_ty_data(lb->m, ty)->id].fields[slot[i]].ty;
        values[slot[i]] = lb_owns(lb, field_ty) ? lb_move_argument(lb, arg) : lb_expr(lb, arg).v;
    }
    for (uint32_t i = 0; i < nfields && lb->ok; i++) {
        if (!covered[i]) {
            values[i] = lr_default(lb, decl, sym, i, lb->m->type_defs[mir_ty_data(lb->m, ty)->id].fields[i].ty);
        }
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirImm imm = {.tag = MI_TYPE, .a = mir_ty_data(lb->m, ty)->id};
    return (LbVal){mir_b_emit(&lb->b, MOP_TypeNew, values, nfields, imm, ty), lb_owns(lb, ty)};
}

/* `record.field` where the checker resolved a field. */
LbVal lr_field(Lb *lb, const MsExpr *e) {
    if (lb->facts->res_kind[e->id] != MS_RES_FIELD) {
        return LB_UNSUPPORTED(lb);
    }
    const LbVal holder = lb_expr(lb, e->u.member.left);
    if (!lb->ok) {
        return LB_FAIL;
    }
    if (holder.owned) {
        return LB_UNSUPPORTED(lb); // a field of a temporary: the temporary is released after the read
    }
    const MirTyData *record = mir_ty_data(lb->m, mir_b_ty(&lb->b, holder.v));
    const uint32_t index = lb->facts->res_ref[e->id];
    if (record->kind != MK_TYPE || index >= lb->m->type_defs[record->id].nfields) {
        return LB_UNSUPPORTED(lb);
    }
    const MirTy field = lb->m->type_defs[record->id].fields[index].ty;
    const MirImm imm = {.tag = MI_FIELD, .a = record->id, .b = index};
    return (LbVal){mir_b_emit(&lb->b, MOP_TypeGet, &holder.v, 1, imm, field), false};
}

/* The fields a store `a.b.c = v` selects, outermost first, down to the name `a`; false when a link is not a field the
 * checker resolved. */
static bool lr_store_path(const Lb *lb, const MsExpr *target, const MsExpr **path, uint32_t *length) {
    uint32_t n = 0;
    const MsExpr *cur = target;
    while (cur->kind == MS_E_MEMBER && n < LR_STORE_DEPTH) {
        if (lb->facts->res_kind[cur->id] != MS_RES_FIELD) {
            return false;
        }
        path[n++] = cur;
        cur = cur->u.member.left;
    }
    *length = n;
    return cur->kind == MS_E_NAME && n > 0;
}

/* `record` with the field chain `path[depth - 1]` (innermost last) replaced by `value`. A field that needs dropping is
 * moved out, its old value dropped and the slot refilled; any other is read and set. */
static MirValue lr_set_path(Lb *lb, MirValue record, const MsExpr *const *path, uint32_t depth, MirValue value) {
    const MsExpr *link = path[depth - 1];
    const MirTyData *type = mir_ty_data(lb->m, mir_b_ty(&lb->b, record));
    const uint32_t index = lb->facts->res_ref[link->id];
    if (type->kind != MK_TYPE || index >= lb->m->type_defs[type->id].nfields) {
        (void)LB_UNSUPPORTED(lb);
        return record;
    }
    const MirTy field_ty = lb->m->type_defs[type->id].fields[index].ty;
    const MirImm imm = {.tag = MI_FIELD, .a = type->id, .b = index};
    const MirValue current = mir_b_emit(&lb->b, MOP_TypeGet, &record, 1, imm, field_ty);
    const bool moved = lb_owns(lb, field_ty);
    const MirValue held = moved ? mir_b_emit(&lb->b, MOP_MoveOut, &current, 1, (MirImm){0}, field_ty) : current;
    MirValue inner = value;
    if (depth > 1) {
        inner = lr_set_path(lb, held, path, depth - 1, value);
    } else if (moved) {
        lb_drop(lb, held);
    }
    const MirValue args[2] = {record, inner};
    return mir_b_emit(&lb->b, moved ? MOP_TypeFill : MOP_TypeSet, args, 2, imm, mir_b_ty(&lb->b, record));
}

/* `local.a.b = value`: the record chain rebuilt with `type.set` / `type.fill` and stored back into the local. */
void lr_assign_field(Lb *lb, const MsStmt *s) {
    const uint32_t binding = lb->facts->field_store_root[s->id];
    const MsExpr *path[LR_STORE_DEPTH];
    uint32_t depth = 0;
    if (binding == MS_NONE || !lr_store_path(lb, s->u.assign.target, path, &depth)) {
        (void)LB_UNSUPPORTED(lb);
        return;
    }
    // A record reached by address: a `var` parameter's pointer, or the slot a resource local lives in.
    const MirValue slot = lc_slot_of(lb, binding);
    const MirValue address = slot != MIR_NONE ? slot : lb->value_of[binding];
    const bool through_pointer = slot != MIR_NONE || lb_is_pointer_param(lb, binding);
    if (lb->var_of[binding] == MIR_NONE && !through_pointer) {
        (void)LB_UNSUPPORTED(lb);
        return;
    }
    const MirTy root_ty = lb_mir_ty(lb, lb->facts->bindings.ty[binding]);
    if (!through_pointer && lb_owns(lb, root_ty) && !lb_var_owned(lb, binding)) {
        (void)LB_UNSUPPORTED(lb); // a `var` parameter that is not a record lives in the caller's memory
        return;
    }
    LbVal value = lb_expr(lb, s->u.assign.value);
    if (!lb->ok) {
        return;
    }
    const MirTy field_ty = lb_mir_ty(lb, lb->facts->expr_ty[s->u.assign.target->id]);
    if (lb_owns(lb, field_ty) && !value.owned) {
        if (field_ty != MIR_STR) {
            (void)LB_UNSUPPORTED(lb); // a list taken from a name: copy or move is not known yet
            return;
        }
        value = (LbVal){lb_copy(lb, value.v), true};
    }
    const bool takes = through_pointer && lb_owns(lb, root_ty); // a record that needs dropping is taken out of its slot and put back
    MirValue root = MIR_NONE;
    if (takes) {
        root = mir_b_emit(&lb->b, MOP_Take, &address, 1, (MirImm){.tag = MI_TY, .a = root_ty}, root_ty);
    } else if (through_pointer) {
        root = lb_load(lb, address, root_ty);
    } else {
        root = mir_b_use_var(&lb->b, lb->var_of[binding]);
    }
    const MirValue updated = lr_set_path(lb, root, path, depth, value.v);
    if (!lb->ok) {
        return;
    }
    if (takes) {
        const MirValue args[2] = {address, updated};
        (void)mir_b_emit(&lb->b, MOP_Put, args, 2, (MirImm){0}, MIR_NONE);
    } else if (through_pointer) {
        lb_store(lb, address, updated);
    } else {
        mir_b_def_var(&lb->b, lb->var_of[binding], updated);
    }
}
