/* compiler/lower/lower_var_slot.c: the slots a `var` place is lent from to a call that changes it, and the stores that put
 * the changed values back. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

void fn_presolve_keys(LowerFn *fn, const MsExpr *place) {
  while (place->kind == MS_E_MEMBER || (place->kind == MS_E_UNARY && place->op == MS_U_TRY)) {
    place = place->kind == MS_E_MEMBER ? place->u.member.left : place->u.bin.left;
  }
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (!ms_expr_index(place, &container, &key)) {
    return;
  }
  fn_presolve_keys(fn, container);
  const MsTy ty = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, key->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  if (ty == MS_TY_NONE || fn->npresolved == MS_COUNT_OF(fn->presolved)) {
    return;
  }
  const MirValue value = fn_expr(fn, key, LW_BORROW);
  if (value == MIR_NONE) {
    return;
  }
  fn->presolved[fn->npresolved].expr = key;
  fn->presolved[fn->npresolved++].value = value;
  MirValue element = MIR_NONE; /* a list element that is not there faults now, before a later argument runs */
  (void)fn_list_element_addr(fn, place, &element);
}

/* A `var` argument of a source function: the place it names, and the slot the callee changes it in. */
/* Moves the value of `place` into a new slot and returns the slot's address. */
MirValue fn_var_slot(LowerFn *fn, const MsExpr *place, VarSlot *out, const VarSlot *earlier, uint32_t nearlier) {
  MirValue owned;
  if (place->kind == MS_E_UNARY && place->op == MS_U_TRY && fn_try_place_changeable(fn, place->u.bin.left)) {
    return fn_try_var_slot(fn, place, out);
  }
  MirValue element;
  const MsRef *named = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (named != NULL && named->kind == MS_REF_PARAM && fn->param_vars == NULL && fn->default_base != MIR_NONE &&
      fn->default_call == NULL) {
    /* A field default passes an earlier field of the record under construction on as `var`: the callee changes it in place. */
    const MirTyData *data = mir_ty_data(fn->cx->module, fn->default_record_ty);
    if (data->kind != MK_TYPE || named->local >= fn->cx->module->type_defs.ptr[data->id].nfields) {
      (void)fn_fail(fn, "a field default reads a field its record does not have");
      return MIR_NONE;
    }
    const MirImm field = {.tag = MI_FIELD, .a = data->id, .b = named->local};
    element = mir_b_emit(&fn->b, MOP_PtrField, &fn->default_base, 1, field, MIR_PTR);
    *out = (VarSlot){NULL, element, MIR_VOID, MIR_NONE, true, MIR_NONE, MIR_NONE, NULL};
    return element;
  }
  if (fn_default_var_slot(fn, place, &element)) { /* a default passing on a `var` parameter of its own call */
    *out = (VarSlot){NULL, element, MIR_VOID, MIR_NONE, true, MIR_NONE, MIR_NONE, NULL};
    return element;
  }
  if (fn_list_element_addr(fn, place, &element)) {
    *out = (VarSlot){place, element, MIR_NONE, MIR_NONE, true, MIR_NONE, MIR_NONE, NULL};
    return element;
  }
  MirTy local_ty = MIR_VOID;
  if (place->kind == MS_E_NAME && fn_closing_local(fn, place, &element, &local_ty)) {
    /* A `var` resource local is lent in place, as one of its fields is: its slot keeps closing it if the callee faults. */
    *out = (VarSlot){place, element, MIR_NONE, MIR_NONE, true, MIR_NONE, MIR_NONE, NULL};
    return element;
  }
  if (place->kind == MS_E_MEMBER && fn_field_address(fn, place, &element)) { /* a field of a closing local changes where it lies */
    *out = (VarSlot){place, element, MIR_NONE, MIR_NONE, true, MIR_NONE, MIR_NONE, NULL};
    return element;
  }
  MsExpr *indexed = NULL;
  MsExpr *index_key = NULL;
  /* `xs[i]` with a name for `i` parses as a type application, so ask for the index form, not the node kind. */
  const bool is_place = place->kind == MS_E_NAME || place->kind == MS_E_MEMBER || ms_expr_index(place, &indexed, &index_key);
  MirValue record = MIR_NONE;
  bool shared = false;
  if (is_place) {
    /* A field of an owning record is taken out of it, not copied; `fn_put_field` stores it back. */
    /* Another field of a variable an earlier argument already took: it is read from that record, which goes back once. */
    for (uint32_t at = 0; at < nearlier && !shared; at++) {
      if (earlier[at].record != MIR_NONE && earlier[at].place != NULL && fn_same_field_root(fn, earlier[at].place, place) &&
          fn_read_field(fn, place, earlier[at].record, &owned)) {
        record = earlier[at].record;
        shared = true;
      }
    }
    if (!shared && !fn_take_field(fn, place, &record, &owned) && !fn_take_place(fn, place, &owned)) {
      return MIR_NONE;
    }
  } else {
    /* A temporary: the callee changes it and what is left is dropped after the call. */
    owned = fn_expr(fn, place, LW_MOVE);
    /* A resource: it waits in a closing slot the callee changes in place, and the slot closes what is left. */
    const MsTy checked = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, place->id), fn->subst.vars,
                                     fn->subst.args, fn->subst.count);
    if (owned != MIR_NONE && fn->temps && checked != MS_TY_NONE) {
      const MirValue kept = fn_pending_own(fn, checked, owned);
      if (kept != MIR_NONE) {
        *out = (VarSlot){NULL, kept, mir_b_ty(&fn->b, owned), MIR_NONE, true, MIR_NONE, MIR_NONE, NULL};
        return kept;
      }
    }
    if (owned != MIR_NONE && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, owned))) {
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &owned, 1, (MirImm){0}, MIR_NONE);
    }
  }
  if (owned == MIR_NONE) {
    return MIR_NONE;
  }
  if (shared && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, owned))) {
    /* The field leaves the record an earlier argument took; `fn_put_field_chain` fills it again. */
    owned = mir_b_emit(&fn->b, MOP_MoveOut, &owned, 1, (MirImm){0}, mir_b_ty(&fn->b, owned));
  }
  const MirTy ty = mir_b_ty(&fn->b, owned);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue stored[2] = {slot, owned};
  (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, ty) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  *out = (VarSlot){is_place ? place : NULL, slot, ty, record, false, MIR_NONE, MIR_NONE, NULL};
  return slot;
}

/* Stores slot `at`'s value into its place. A field's record carries the change on to the later fields of the same root. */
static bool put_back(LowerFn *fn, VarSlot *slots, uint32_t count, uint32_t at, MirValue value) {
  if (slots[at].record == MIR_NONE) {
    return fn_put_place(fn, slots[at].place, value);
  }
  const MirValue old = slots[at].record;
  MirValue record = old;
  bool shared = false; /* a later field of the same record changes it again: the record is stored once, by the last */
  for (uint32_t later = at + 1; later < count; later++) {
    shared = shared || slots[later].record == old;
  }
  if (!fn_put_field_chain(fn, slots[at].place, old, value, &record, !shared)) {
    return false;
  }
  for (uint32_t later = at + 1; later < count; later++) {
    if (slots[later].record == old) {
      slots[later].record = record;
    }
  }
  return true;
}

/* After the call: slot `at`'s value goes back into the place it came from. */
static bool slot_back(LowerFn *fn, VarSlot *slots, uint32_t count, uint32_t at) {
  if (slots[at].in_place) {
    return true;
  }
  const MirImm of_type = {.tag = MI_TY, .a = slots[at].ty};
  const MirValue updated = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slots[at].ty) ? MOP_Take : MOP_Load,
                                      &slots[at].slot, 1, of_type, slots[at].ty);
  if (slots[at].optional != MIR_NONE) {
    const MirValue wrapped = fn_emit(fn, MOP_OptSome, &updated, 1, (MirImm){0}, slots[at].optional);
    if (slots[at].home != MIR_NONE) {
      const MirValue stored[2] = {slots[at].home, wrapped};
      (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slots[at].optional) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
      return true;
    }
    return put_back(fn, slots, count, at, wrapped);
  }
  if (slots[at].place == NULL) {
    if (mir_needs_drop(fn->cx->module, slots[at].ty)) {
      (void)mir_b_emit(&fn->b, MOP_Drop, &updated, 1, (MirImm){0}, MIR_NONE);
    }
    return true;
  }
  return put_back(fn, slots, count, at, updated);
}

bool fn_var_slots_back(LowerFn *fn, VarSlot *slots, uint32_t count) {
  for (uint32_t at = 0; at < count; at++) {
    if (!slot_back(fn, slots, count, at)) {
      return false;
    }
    if (slots[at].outer != NULL && !fn_var_slots_back(fn, slots[at].outer, 1)) { /* `a?.b?.f()`: `a` takes its changed payload back */
      return false;
    }
  }
  return true;
}

