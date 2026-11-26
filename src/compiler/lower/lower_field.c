/* compiler/lower/lower_field.c: a field of an owning local taken out and stored back for a native that changes it in place. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_layout.h"
#include "compiler/mir/mir_analysis.h"

/* A field of an owning local or parameter, taken without a copy for a native that changes it in place: `record` is the
 * record, taken out of its variable, and `field` the field's value, which shares its storage with the record until
 * `fn_put_field` stores the changed one. False when `place` is not such a field. */
enum { FIELD_PATH_MAX = 6 };

/* The record fields from the owning root to `place`, outermost first (`holder.reader.names` is `reader`, `names`),
 * and the root's place. False when `place` is not a field path rooted in an owning local or parameter. */
static bool field_path(LowerFn *fn, const MsExpr *place, const MsExpr **fields, uint32_t *count, const MsExpr **root) {
  const MsExpr *chain[FIELD_PATH_MAX];
  uint32_t length = 0;
  const MsExpr *at = place;
  for (;;) {
    const MsRef *ref = at->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, at->id) : NULL;
    if (ref == NULL || ref->kind != MS_REF_FIELD || length == FIELD_PATH_MAX) {
      return false;
    }
    chain[length++] = at;
    const MsExpr *base = at->u.member.left;
    MirVar var;
    MirValue slot;
    MirTy slot_ty;
    if (fn_owned_local(fn, base, &var) || fn_closing_local(fn, base, &slot, &slot_ty) || fn_closing_param(fn, base, &slot, &var)) {
      *root = base;
      break;
    }
    at = base;
  }
  for (uint32_t index = 0; index < length; index++) {
    fields[index] = chain[length - 1 - index];
  }
  *count = length;
  return true;
}

/* The value of each field of the path, read from the root record `record`; values[0] is `record` itself. */
static bool read_path(LowerFn *fn, const MsExpr **fields, uint32_t count, MirValue record, MirValue *values) {
  values[0] = record;
  for (uint32_t index = 0; index < count; index++) {
    const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, values[index]));
    if (data->kind != MK_TYPE) {
      return false;
    }
    const MsRef *ref = ms_facts_ref(fn->facts, fields[index]->id);
    const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
    values[index + 1] = mir_b_emit(&fn->b, MOP_TypeGet, &values[index], 1, imm, fn_type(fn, ms_facts_type(fn->facts, fields[index]->id)));
  }
  return true;
}

/* A field of an owning local or parameter, or a field path below it, taken without a copy for a native that changes
 * it in place: `record` is the root record, taken out of its variable, and `field` the field's value, which shares its
 * storage with the record until `fn_put_field` stores the changed one. False when `place` is not such a field. */
bool fn_take_field(LowerFn *fn, const MsExpr *place, MirValue *record, MirValue *field) {
  const MsExpr *fields[FIELD_PATH_MAX];
  const MsExpr *root = NULL;
  uint32_t count = 0;
  if (!field_path(fn, place, fields, &count, &root)) {
    return false;
  }
  if (!fn_take_place(fn, root, record)) {
    return false;
  }
  MirValue values[FIELD_PATH_MAX + 1];
  if (!read_path(fn, fields, count, *record, values)) {
    return false;
  }
  *field = values[count];
  if (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, *field))) {
    /* The field leaves its record for the change, which owns it; `fn_put_field_chain` fills it again. */
    *field = mir_b_emit(&fn->b, MOP_MoveOut, field, 1, (MirImm){0}, mir_b_ty(&fn->b, *field));
  }
  return true;
}

/* Whether every leaf of `ty` is a whole word, whatever the layout later decides: a bool, a small number, an optional's
 * tag, an alternative's tag and a value object each have a smaller leaf. */
static bool word_leaves(const MirModule *module, MirTy ty, uint32_t depth) {
  const MirTyData *data = mir_ty_data(module, ty);
  switch ((MirTyKind)data->kind) {
  case MK_INT: case MK_FLOAT: case MK_UINT64: case MK_STR: case MK_BYTES: case MK_PTR: case MK_LIST: case MK_FN: case MK_IFACE:
    return true;
  case MK_OBJ:
    return data->obj_class != MIR_OBJ_VALUE; /* a handle is a word, a collection is words */
  case MK_OPT:
    return mir_ty_opt_boxed(module, data->elem); /* a boxed optional is its block's pointer, null when absent */
  case MK_TYPE: {
    const MirTypeDef *def = &module->type_defs.ptr[data->id];
    for (uint32_t index = 0; index < def->nfields; index++) {
      if (depth == 0 || !word_leaves(module, def->fields[index].ty, depth - 1)) {
        return false;
      }
    }
    return true;
  }
  default:
    return false;
  }
}

/* Whether a field is laid out in its record as it is alone: the record keeps all its leaves in one run, so a field of
 * several leaves that follows a smaller leaf (after a bool) starts off its own alignment and its leaves lie at other
 * offsets than the field's own cell has. A single leaf, or a field after whole words only, is the same either way. */
static bool field_cell_exact(const MirModule *module, uint32_t record, uint32_t field) {
  const MirTypeDef *def = &module->type_defs.ptr[record];
  const MirTyData *own = mir_ty_data(module, def->fields[field].ty);
  if (mir_is_scalar(module, def->fields[field].ty) || own->kind == MK_LIST || own->kind == MK_PTR ||
      (own->kind == MK_OBJ && own->obj_class == MIR_OBJ_HANDLE)) {
    return true; /* one leaf */
  }
  if (word_leaves(module, def->fields[field].ty, 4)) {
    return true; /* whole words stay whole words: their offsets from the field's first leaf do not depend on what precedes it */
  }
  for (uint32_t index = 0; index < field; index++) {
    if (!word_leaves(module, def->fields[index].ty, 4)) {
      return false;
    }
  }
  return true;
}

/* The address of the field `place` names inside a resource local that lives in its closing slot, for a callee that
 * changes it where it lies: the record stays in its slot, so the local's cleanup stays registered through a fault in
 * the call. False when `place` is not a field path rooted in such a local. */
bool fn_field_address(LowerFn *fn, const MsExpr *place, MirValue *addr) {
  const MsExpr *fields[FIELD_PATH_MAX];
  const MsExpr *root = NULL;
  uint32_t count = 0;
  MirValue cell;
  MirTy record_ty;
  MirVar var;
  if (!field_path(fn, place, fields, &count, &root)) {
    return false;
  }
  if (fn_closing_param(fn, root, &cell, &var)) {
    record_ty = fn->b.vars.ptr[var].ty;
  } else if (!fn_closing_local(fn, root, &cell, &record_ty)) {
    return false;
  }
  MirValue at = cell;
  for (uint32_t index = 0; index < count; index++) {
    const MirTyData *data = mir_ty_data(fn->cx->module, record_ty);
    if (data->kind != MK_TYPE) {
      return false;
    }
    const MsRef *ref = ms_facts_ref(fn->facts, fields[index]->id);
    if (!field_cell_exact(fn->cx->module, data->id, ref->index)) {
      return false;
    }
    const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
    at = mir_b_emit(&fn->b, MOP_PtrField, &at, 1, imm, MIR_PTR);
    record_ty = fn_type(fn, ms_facts_type(fn->facts, fields[index]->id));
  }
  *addr = at;
  return true;
}

/* The address of the field `place` names inside an element of a list or map held in place (`items[i].n`, `m[k].inner.n`),
 * for a store where the record lies: the element stays in its container, so nothing is copied or put back. False, with
 * nothing emitted, when `place` is not a field path below such an element or some record on it lays its field out
 * differently in a cell of its own. */
bool fn_element_field_address(LowerFn *fn, const MsExpr *place, MirValue *addr) {
  const MsExpr *chain[FIELD_PATH_MAX];
  uint32_t length = 0;
  const MsExpr *base = place;
  while (base->kind == MS_E_MEMBER) {
    const MsRef *ref = ms_facts_ref(fn->facts, base->id);
    if (ref == NULL || ref->kind != MS_REF_FIELD || length == FIELD_PATH_MAX) {
      return false;
    }
    chain[length++] = base;
    base = base->u.member.left;
  }
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (length == 0 || !ms_expr_index(base, &container, &key) || !fn_place_changeable(fn, container)) {
    return false;
  }
  MirTy record_ty = fn_type(fn, ms_facts_type(fn->facts, base->id));
  for (uint32_t index = length; index-- > 0;) { /* outermost field first: judge every layout before emitting anything */
    const MirTyData *data = mir_ty_data(fn->cx->module, record_ty);
    const MsRef *ref = ms_facts_ref(fn->facts, chain[index]->id);
    if (data->kind != MK_TYPE || !field_cell_exact(fn->cx->module, data->id, ref->index)) {
      return false;
    }
    record_ty = fn_type(fn, ms_facts_type(fn->facts, chain[index]->id));
  }
  MirTy element_ty = MIR_VOID;
  MirValue at = MIR_NONE;
  if (!fn_place_address(fn, base, &at, &element_ty)) {
    return false;
  }
  record_ty = element_ty;
  for (uint32_t index = length; index-- > 0;) {
    const MirTyData *data = mir_ty_data(fn->cx->module, record_ty);
    const MsRef *ref = ms_facts_ref(fn->facts, chain[index]->id);
    const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
    at = mir_b_emit(&fn->b, MOP_PtrField, &at, 1, imm, MIR_PTR);
    record_ty = fn_type(fn, ms_facts_type(fn->facts, chain[index]->id));
  }
  *addr = at;
  return true;
}

/* Stores `field`, the changed value of the field `fn_take_field` took, back: the old ones share its storage, so they
 * are not dropped. */
bool fn_put_field(LowerFn *fn, const MsExpr *place, MirValue record, MirValue field) {
  return fn_put_field_chain(fn, place, record, field, NULL, true);
}

/* The same, and `*updated_record` is the root record with the field changed: a later field of the same root is put
 * into that, not into the record the first one replaced; only the last of them stores the record (`store`). */
bool fn_put_field_chain(LowerFn *fn, const MsExpr *place, MirValue record, MirValue field, MirValue *updated_record, bool store) {
  const MsExpr *fields[FIELD_PATH_MAX];
  const MsExpr *root = NULL;
  uint32_t count = 0;
  MirValue values[FIELD_PATH_MAX + 1];
  if (!field_path(fn, place, fields, &count, &root) || !read_path(fn, fields, count, record, values)) {
    return fn_fail(fn, "a changed field is not a field path");
  }
  MirValue updated = field;
  for (uint32_t index = count; index-- > 0;) {
    if (index > 0) { /* an inner record leaves the one above it and goes back into it with the field filled */
      values[index] = mir_b_emit(&fn->b, MOP_MoveOut, &values[index], 1, (MirImm){0}, mir_b_ty(&fn->b, values[index]));
    }
    const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, values[index]));
    const MsRef *ref = ms_facts_ref(fn->facts, fields[index]->id);
    const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
    const MirValue operands[2] = {values[index], updated};
    updated = mir_b_emit(&fn->b, MOP_TypeSet, operands, 2, imm, mir_b_ty(&fn->b, values[index]));
  }
  if (updated_record != NULL) {
    *updated_record = updated;
  }
  return !store || fn_put_place(fn, root, updated);
}

/* The field `place` of the root record `record`, which an earlier field of the same root already took out of its variable. */
bool fn_read_field(LowerFn *fn, const MsExpr *place, MirValue record, MirValue *field) {
  const MsExpr *fields[FIELD_PATH_MAX];
  const MsExpr *root = NULL;
  uint32_t count = 0;
  MirValue values[FIELD_PATH_MAX + 1];
  if (!field_path(fn, place, fields, &count, &root) || !read_path(fn, fields, count, record, values)) {
    return false;
  }
  *field = values[count];
  return true;
}

/* Whether the field paths `a` and `b` start at the same variable. */
bool fn_same_field_root(LowerFn *fn, const MsExpr *a, const MsExpr *b) {
  const MsExpr *fields[FIELD_PATH_MAX];
  const MsExpr *root_a = NULL;
  const MsExpr *root_b = NULL;
  uint32_t count = 0;
  if (!field_path(fn, a, fields, &count, &root_a) || !field_path(fn, b, fields, &count, &root_b)) {
    return false;
  }
  const MsRef *ref_a = ms_facts_ref(fn->facts, root_a->id);
  const MsRef *ref_b = ms_facts_ref(fn->facts, root_b->id);
  return ref_a != NULL && ref_b != NULL && ref_a->kind == ref_b->kind && ref_a->local == ref_b->local;
}

/* Whether two member paths name the same field of the same variable. */
bool fn_same_member_path(LowerFn *fn, const MsExpr *a, const MsExpr *b) {
  while (a->kind == MS_E_MEMBER && b->kind == MS_E_MEMBER) {
    const MsRef *ra = ms_facts_ref(fn->facts, a->id);
    const MsRef *rb = ms_facts_ref(fn->facts, b->id);
    if (ra == NULL || rb == NULL || ra->kind != MS_REF_FIELD || rb->kind != MS_REF_FIELD || ra->index != rb->index) {
      return false;
    }
    a = a->u.member.left;
    b = b->u.member.left;
  }
  const MsRef *ra = a->kind == MS_E_NAME ? ms_facts_ref(fn->facts, a->id) : NULL;
  const MsRef *rb = b->kind == MS_E_NAME ? ms_facts_ref(fn->facts, b->id) : NULL;
  return ra != NULL && rb != NULL && ra->kind == rb->kind && ra->local == rb->local;
}

/* A field assigned where it lies, in a record that stays in its cell: the old value leaves the field, is dropped or
 * closed, and the new one is stored over it, with nothing between that can fault. */
bool fn_store_field_in_place(LowerFn *fn, const MsExpr *place, MirValue address, MirValue value) {
  const MirTy field_ty = fn_type(fn, ms_facts_type(fn->facts, place->id));
  const bool owns = mir_needs_drop(fn->cx->module, field_ty);
  bool moved_out = false; /* an earlier bind took the field: there is nothing to drop */
  for (uint32_t at = 0; at < fn->nmoved_fields; at++) {
    if (fn_same_member_path(fn, fn->moved_fields[at], place)) {
      moved_out = true;
      fn->moved_fields[at] = fn->moved_fields[--fn->nmoved_fields];
      break;
    }
  }
  if (!moved_out && owns) {
    const MirValue view = mir_b_emit(&fn->b, MOP_Load, &address, 1, (MirImm){.tag = MI_TY, .a = field_ty}, field_ty);
    const MirValue old = mir_b_emit(&fn->b, MOP_MoveOut, &view, 1, (MirImm){0}, field_ty);
    const MsTy checked = ms_facts_type(fn->facts, place->id);
    if (fn_closer_for(fn, ms_facts_closer(fn->facts, place->id), checked)) {
      if (!fn_close_replaced(fn, checked, old)) {
        return false;
      }
    } else {
      (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
    }
  }
  const MirValue stored[2] = {address, value};
  (void)mir_b_emit(&fn->b, owns ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  return !fn->failed;
}

/* An empty value of `ty` stored over the field at `address`: what a field moved out of its record leaves, so the
 * record's later drop releases nothing there. A slot starts zeroed, and the zero of every type drops as nothing. */
static void field_hole(LowerFn *fn, MirValue address, MirTy ty) {
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue zero = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue empty = mir_b_emit(&fn->b, MOP_Take, &zero, 1, of_type, ty);
  const MirValue stored[2] = {address, empty};
  (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
}

/* A field of a record that lies in its cell, read where it lies. A field the read hands on (a move) leaves the cell
 * with a hole, which a later assignment to it fills. False when the field is read some other way. */
bool fn_read_field_in_place(LowerFn *fn, const MsExpr *expr, MirValue *value) {
  MirValue address = MIR_NONE;
  if (!fn_field_address(fn, expr, &address)) {
    return false;
  }
  const MirTy ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  *value = fn_emit(fn, MOP_Load, &address, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
  if (fn->placing_member != expr && ms_facts_use(fn->facts, expr->id) == MS_USE_MOVE && mir_needs_drop(fn->cx->module, ty)) {
    *value = fn_emit(fn, MOP_MoveOut, value, 1, (MirImm){0}, ty);
    field_hole(fn, address, ty);
  }
  return true;
}

/* `self.value` in a method of a type set: `self` is the variable `Self`, so the checker knew no field. Once the call
 * binds `Self` to a member, the field is looked up by name in that member's record. */
bool fn_late_field(LowerFn *fn, const MsExpr *expr, MsRef *out) {
  const MsTy left = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, expr->u.member.left->id), fn->subst.vars,
                                fn->subst.args, fn->subst.count);
  if (left == MS_TY_NONE || fn->subst.count == 0) {
    return false;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, fn_type(fn, left));
  if (data->kind != MK_TYPE) {
    return false;
  }
  const MirTypeDef *def = &fn->cx->module->type_defs.ptr[data->id];
  const MsSpan name = ms_names_span(fn->cx->program->names, expr->u.member.name);
  for (uint32_t index = 0; index < def->nfields; index++) {
    if (ms_span_equal(name, ms_names_span(&fn->cx->module->names, def->fields[index].name))) {
      out->kind = MS_REF_FIELD;
      out->index = index;
      return true;
    }
  }
  return false;
}

bool fn_move_field(LowerFn *fn, const MsExpr *expr, uint32_t index) {
  MirVar owner = 0;
  const MsExpr *left = expr->u.member.left;
  if (fn_owned_local(fn, left, &owner) && fn->b.vars.ptr[owner].mode == MM_MOVE) {
    fn_scope_var_moved(fn, owner, index, ms_facts_type(fn->facts, left->id));
    return true;
  }
  /* `name.field.part`: the part leaves the field, which keeps its other parts until the name's scope ends. */
  const MsRef *outer = left->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, left->id) : NULL;
  return outer != NULL && outer->kind == MS_REF_FIELD && fn_owned_local(fn, left->u.member.left, &owner) &&
         fn->b.vars.ptr[owner].mode == MM_MOVE &&
         fn_scope_var_moved_part(fn, owner, outer->index, index, ms_facts_type(fn->facts, left->u.member.left->id),
                                 ms_facts_type(fn->facts, left->id));
}

bool fn_leaves_fields(const LowerFn *fn, uint32_t local, MirTy ty) {
  return fn->holds_value != NULL && local < fn->nvars && fn->holds_value[local] &&
         mir_ty_data(fn->cx->module, ty)->kind == MK_TYPE;
}
