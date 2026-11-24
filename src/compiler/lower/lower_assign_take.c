/* compiler/lower/lower_assign_take.c: `cur = n.next` where `n` views the payload of the owning optional `cur`: the field
 * moves out of the old payload instead of being copied. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

/* Whether `view` is the result of a call that borrows `owner` (`n := cur.get()` views the payload of `cur`). */
static bool is_load_of(const LowerFn *fn, MirValue value, MirValue slot) {
  for (size_t block = 0; block < fn->b.func.blocks.len; block++) {
    const MirInstList *insts = &fn->b.func.blocks.ptr[block].insts;
    for (size_t at = 0; at < insts->len; at++) {
      if (insts->ptr[at].res == value) {
        return insts->ptr[at].op == MOP_Load && insts->ptr[at].nargs == 1 && insts->ptr[at].args[0] == slot;
      }
    }
  }
  return false;
}

/* `owner` is the value itself, or (`slot` set) any load of the slot that holds it. */
static bool views_payload_in(const LowerFn *fn, MirValue view, MirValue owner, MirValue slot) {
  for (size_t block = 0; block < fn->b.func.blocks.len; block++) {
    const MirInstList *insts = &fn->b.func.blocks.ptr[block].insts;
    for (size_t at = 0; at < insts->len; at++) {
      const MirInst *inst = &insts->ptr[at];
      if (inst->res == view) {
        MirMode mode = MM_MOVE;
        return inst->nargs != 0 && (inst->args[0] == owner || (slot != MIR_NONE && is_load_of(fn, inst->args[0], slot))) &&
               mir_result_mode(fn->cx->module, &fn->b.func, inst, &mode) && mode == MM_BORROW;
      }
    }
  }
  return false;
}

static bool views_payload_of(const LowerFn *fn, MirValue view, MirValue owner) {
  return views_payload_in(fn, view, owner, MIR_NONE);
}

/* `cur = n.next` where `n` views the payload of the owning Optional `cur`: the old payload leaves `cur`, its field
 * moves into the new value and the rest of it is released, so a walk along a list does not copy what is left of it.
 * `value` is the new value, or MIR_NONE when the assignment is not that shape. */
MirValue fn_take_field_of_old(LowerFn *fn, const MsStmt *stmt, MirVar var) {
  const MsExpr *member = stmt->u.assign.value;
  const MsRef *ref = member->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, member->id) : NULL;
  if (ref == NULL || ref->kind != MS_REF_FIELD || ms_facts_use(fn->facts, member->id) != MS_USE_MOVE || fn->b.vars.ptr[var].mode != MM_MOVE) {
    return MIR_NONE;
  }
  const MirValue old = mir_b_use_var(&fn->b, var);
  const MirTyData *old_data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, old));
  if (old_data->kind != MK_OPT || !mir_needs_drop(fn->cx->module, old_data->elem)) {
    return MIR_NONE;
  }
  fn->or_view = member->u.member.left; /* a probe: `(x or d).field` keeps its payload a view */
  const MirValue view = fn_expr(fn, member->u.member.left, LW_BORROW);
  fn->or_view = NULL;
  if (view == MIR_NONE || !views_payload_of(fn, view, old)) {
    return MIR_NONE;
  }
  const MirTy elem = old_data->elem;
  const MirTyData *record = mir_ty_data(fn->cx->module, elem);
  if (record->kind != MK_TYPE) {
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_FIELD, .a = record->id, .b = ref->index};
  const MirValue item = mir_b_emit(&fn->b, MOP_OptUnbox, &old, 1, (MirImm){0}, elem);
  const MirTy field_ty = fn_type(fn, ms_facts_type(fn->facts, member->id));
  const MirValue field = mir_b_emit(&fn->b, MOP_TypeGet, &item, 1, imm, field_ty);
  const MirValue taken = mir_b_emit(&fn->b, MOP_MoveOut, &field, 1, (MirImm){0}, field_ty);
  const MirImm mask = {.tag = MI_TYPEMASK, .a = record->id, .b = ref->index < 32 ? UINT32_C(1) << ref->index : 0};
  (void)mir_b_emit(&fn->b, MOP_TypeRelease, &item, 1, mask, MIR_NONE);
  return taken;
}

/* `cur = n.next` where `cur` lives in a closing slot: as `take_field_of_old`, the payload leaves the slot, its field
 * is the new value and the rest of it is released. Returns whether the assignment was lowered. */
bool fn_take_field_into_slot(LowerFn *fn, const MsStmt *stmt, const MsRef *ref, MsName name, bool *done) {
  *done = false;
  const uint32_t at = fn_closing_at(fn, ref, name);
  const MsExpr *member = stmt->u.assign.value;
  const MsRef *field = member->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, member->id) : NULL;
  if (at == UINT32_MAX || field == NULL || field->kind != MS_REF_FIELD || stmt->u.assign.has_compound ||
      ms_facts_use(fn->facts, member->id) != MS_USE_MOVE ||
      (fn->shared != NULL && ref->kind == MS_REF_LOCAL && fn->shared[ref->local] != 0)) {
    return true;
  }
  const MirValue slot = fn->closing[at];
  const MirTy old_ty = fn->closing_types[at];
  const MirTyData *old_data = mir_ty_data(fn->cx->module, old_ty);
  if (old_data->kind != MK_OPT || !mir_needs_drop(fn->cx->module, old_data->elem) ||
      mir_ty_data(fn->cx->module, old_data->elem)->kind != MK_TYPE) {
    return true;
  }
  fn->or_view = member->u.member.left; /* a probe: `(x or d).field` keeps its payload a view */
  const MirValue view = fn_expr(fn, member->u.member.left, LW_BORROW);
  fn->or_view = NULL;
  if (view == MIR_NONE || !views_payload_in(fn, view, MIR_NONE, slot)) {
    return !fn->failed;
  }
  const MirTy elem = old_data->elem;
  const MirTyData *record = mir_ty_data(fn->cx->module, elem);
  const MirImm imm = {.tag = MI_FIELD, .a = record->id, .b = field->index};
  const MirValue old = mir_b_emit(&fn->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = old_ty}, old_ty);
  const MirValue item = mir_b_emit(&fn->b, MOP_OptUnbox, &old, 1, (MirImm){0}, elem);
  const MirTy field_ty = fn_type(fn, ms_facts_type(fn->facts, member->id));
  const MirValue got = mir_b_emit(&fn->b, MOP_TypeGet, &item, 1, imm, field_ty);
  const MirValue taken = mir_b_emit(&fn->b, MOP_MoveOut, &got, 1, (MirImm){0}, field_ty);
  const MirImm mask = {.tag = MI_TYPEMASK, .a = record->id, .b = field->index < 32 ? UINT32_C(1) << field->index : 0};
  (void)mir_b_emit(&fn->b, MOP_TypeRelease, &item, 1, mask, MIR_NONE);
  const MirValue stored[2] = {slot, taken};
  (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
  *done = !fn->failed;
  return !fn->failed;
}
