/* A resource field that leaves a local (`return self.source.close()` in a `move fn close`): the ownership pass lets a
 * field move out of a local at the local's last use (`facts->partial_move`). The local lives in a slot as any resource
 * local does, but each such field is an owner of its own, so the move gives it up alone and the scope closes whatever
 * is still held: the fields that did not leave, and then the rest of the record, released without the ones that left
 * (crates/ms-lower/src/close.rs `bind_split`). */
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/walk.h"

typedef struct {
    const Lb *lb;
    uint32_t binding;
    uint32_t *fields;
    uint32_t count;
    bool unsupported;
} LsScan;

static void ls_visit(void *ctx, const MsExpr *e) {
    LsScan *scan = ctx;
    const Lb *lb = scan->lb;
    if (e->kind != MS_E_MEMBER || !lb->facts->partial_move[e->id]) {
        return;
    }
    const MsExpr *holder = e->u.member.left;
    if (holder->kind != MS_E_NAME || lb->facts->res_kind[holder->id] != MS_RES_BINDING || lb->facts->res_ref[holder->id] != scan->binding ||
        lb->facts->res_kind[e->id] != MS_RES_FIELD) {
        return;
    }
    const uint32_t field = lb->facts->res_ref[e->id];
    for (uint32_t i = 0; i < scan->count; i++) {
        if (scan->fields[i] == field) {
            return;
        }
    }
    if (scan->count == LB_MAX_MOVED) {
        scan->unsupported = true;
        return;
    }
    scan->fields[scan->count++] = field;
}

uint32_t ls_moved_fields(Lb *lb, uint32_t binding, uint32_t *fields) {
    LsScan scan = {.lb = lb, .binding = binding, .fields = fields};
    const MsVisitor visitor = {.ctx = &scan, .expr = ls_visit};
    if (lb->cur.fn != NULL) {
        ms_walk_callable(&visitor, lb->cur.fn->params, lb->cur.fn->body);
    }
    return scan.count;
}

/* The function that releases the record at `ptr` except the fields in `mask`, which owners of their own hold. */
static uint32_t ls_rest_thunk(Lb *lb, MirTy ty, uint32_t mask) {
    const MirParam params[1] = {{MIR_PTR, MM_BORROW}};
    MirBuilder b;
    mir_b_init(&b, lb->m, lb_unique_name(lb, (MsStr){"close", 5}), params, 1, MIR_VOID);
    MirValue ptr;
    mir_b_params(&b, &ptr, 1);
    const MirValue value = mir_b_emit(&b, MOP_Take, &ptr, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
    (void)mir_b_emit(&b, MOP_TypeRelease, &value, 1, (MirImm){.tag = MI_TYPEMASK, .a = mir_ty_data(lb->m, ty)->id, .b = mask}, MIR_NONE);
    mir_b_ret(&b, mir_b_unit(&b));
    MirFunc f = {0};
    return mir_b_into_func(&b, &f) ? mir_add_func(lb->m, &f) : MIR_NONE;
}

bool ls_own(Lb *lb, uint32_t binding, MirValue value, const uint32_t *fields, uint32_t nfields) {
    const MirTy ty = mir_b_ty(&lb->b, value);
    const MirTyData *record = mir_ty_data(lb->m, ty);
    if (record->kind != MK_TYPE || !lc_exits_clean(lb) || !mir_needs_drop(lb->m, ty)) {
        return false;
    }
    uint32_t mask = 0;
    uint32_t thunks[LB_MAX_MOVED];
    for (uint32_t i = 0; i < nfields; i++) {
        if (fields[i] >= lb->m->type_defs[record->id].nfields || fields[i] >= 32) {
            return false;
        }
        thunks[i] = lc_field_thunk(lb, lb->m->type_defs[record->id].fields[fields[i]].ty);
        if (thunks[i] == MIR_NONE) {
            return false;
        }
        mask |= 1u << fields[i];
    }
    const uint32_t rest = ls_rest_thunk(lb, ty, mask);
    if (rest == MIR_NONE) {
        return false;
    }
    const MirValue slot = mir_b_emit(&lb->b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = ty}, MIR_PTR);
    const MirValue put[2] = {slot, value};
    (void)mir_b_emit(&lb->b, MOP_Put, put, 2, (MirImm){0}, MIR_NONE);
    LbSlotLocal local = {.view = lb->view, .binding = binding, .slot = slot, .ty = ty, .nmoved = nfields};
    for (uint32_t i = 0; i < nfields; i++) {
        const MirImm field = {.tag = MI_FIELD, .a = record->id, .b = fields[i]};
        local.moved[i] = fields[i];
        local.owner[i] = mir_b_emit(&lb->b, MOP_PtrField, &slot, 1, field, MIR_PTR);
    }
    lscope_own(&lb->scopes, slot, rest + 2); // the rest of the record, released after the fields that did not leave
    for (uint32_t i = 0; i < nfields; i++) {
        lscope_own(&lb->scopes, local.owner[i], thunks[i] + 2);
    }
    (void)lc_push_slot(lb, local);
    return true;
}

bool ls_has_resource_part(Lb *lb, MirTy record) {
    const MirTyData *data = mir_ty_data(lb->m, record);
    if (data->kind != MK_TYPE) {
        return false;
    }
    for (uint32_t i = 0; i < lb->m->type_defs[data->id].nfields; i++) {
        if (lc_is_resource(lb, lb->m->type_defs[data->id].fields[i].ty)) {
            return true;
        }
    }
    return false;
}

bool ls_owner_of(const Lb *lb, const MsExpr *member, MirValue *owner) {
    const MsExpr *holder = member->u.member.left;
    if (holder->kind != MS_E_NAME || lb->facts->res_kind[holder->id] != MS_RES_BINDING) {
        return false;
    }
    for (uint32_t i = 0; i < lb->nslots; i++) {
        const LbSlotLocal *local = &lb->slots[i];
        if (local->view != lb->view || local->binding != lb->facts->res_ref[holder->id]) {
            continue;
        }
        for (uint32_t k = 0; k < local->nmoved; k++) {
            if (local->moved[k] == lb->facts->res_ref[member->id]) {
                *owner = local->owner[k];
                return true;
            }
        }
    }
    return false;
}
