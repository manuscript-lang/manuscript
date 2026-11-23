/* compiler/lower/lower_place.c: places a statement reads or writes: owning locals and parameters, record field paths,
 * list elements and map entries. */
#include "compiler/lower/lower_fn.h"
#include "compiler/own/closers.h"
#include "compiler/mir/mir_analysis.h"

/* A resource parameter lives in a slot its scope owns, and its variable is a view of that slot: the slot and
 * variable of the parameter `place` names, or false. */
static bool closing_param(const LowerFn *fn, const MsExpr *place, MirValue *slot, MirVar *var) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (ref == NULL || ref->kind != MS_REF_PARAM || fn->closing == NULL ||
      fn->nvars + ref->local >= fn->nvars + LOWER_MAX_CLOSING_PARAMS || fn->closing[fn->nvars + ref->local] == MIR_NONE) {
    return false;
  }
  *slot = fn->closing[fn->nvars + ref->local];
  *var = fn->param_vars[ref->local];
  return true;
}

/* The slot of the `var` resource local a name place assigns in, or false. */
static bool closing_local(const LowerFn *fn, const MsExpr *place, MirValue *slot, MirTy *ty) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  const uint32_t at = fn_closing_at(fn, ref, place->u.sym);
  if (at == UINT32_MAX) {
    return false;
  }
  *slot = fn->closing[at];
  *ty = fn->closing_types[at];
  return true;
}

/* Whether `expr` is a List (an index into one is an element place; a Map's entry is read out as a copy). */
bool fn_is_list(LowerFn *fn, const MsExpr *expr) {
  MsTyTable *types = &fn->cx->program->types;
  const MsTy owner = ms_ty_subst(types, ms_facts_type(fn->facts, expr->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  return ms_ty_is(types, owner, MS_BUILTIN_List);
}

/* Whether `place` is a `var` local, a `var` parameter or a member path rooted in one: the places `fn_put_place` stores into. */
bool fn_place_changeable(LowerFn *fn, const MsExpr *place) {
  MirVar var;
  MirValue slot;
  MirTy ty;
  if (place == NULL) {
    return false;
  }
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (ms_expr_index(place, &container, &key)) { /* an element of a changeable place changes with it */
    return fn_place_changeable(fn, container);
  }
  return fn_owned_local(fn, place, &var) || closing_local(fn, place, &slot, &ty) || closing_param(fn, place, &slot, &var) ||
         (place->kind == MS_E_MEMBER && fn_place_changeable(fn, place->u.member.left));
}

bool fn_try_place_changeable(LowerFn *fn, const MsExpr *place) {
  if (fn_place_changeable(fn, place)) {
    return true;
  }
  const MsExpr *base = place != NULL && place->kind == MS_E_MEMBER ? place->u.member.left : NULL;
  return base != NULL && base->kind == MS_E_UNARY && base->op == MS_U_TRY && fn_try_place_changeable(fn, base->u.bin.left);
}

bool fn_place_owns(LowerFn *fn, const MsExpr *place) {
  MirVar var;
  MirValue slot;
  MirTy ty;
  if (place->kind == MS_E_MEMBER) {
    return fn_place_owns(fn, place->u.member.left);
  }
  return closing_local(fn, place, &slot, &ty) ? mir_needs_drop(fn->cx->module, ty) : fn_owned_local(fn, place, &var) && fn_var_owns(fn, var);
}

/* The owned value of `base`, a place a part of it is assigned in: an owning local's value is taken out (stored
 * back by `fn_put_place`), a member or element path's value is copied. */
bool fn_take_place(LowerFn *fn, const MsExpr *base, MirValue *out) {
  MirVar var;
  if (fn_owned_local(fn, base, &var)) {
    *out = mir_b_use_var(&fn->b, var);
    return true;
  }
  MirValue slot;
  MirTy slot_ty;
  if (closing_local(fn, base, &slot, &slot_ty)) {
    *out = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slot_ty) ? MOP_Take : MOP_Load, &slot, 1,
                      (MirImm){.tag = MI_TY, .a = slot_ty}, slot_ty);
    return true;
  }
  if (closing_param(fn, base, &slot, &var)) {
    const MirTy ty = mir_b_ty(&fn->b, mir_b_use_var(&fn->b, var));
    *out = mir_b_emit(&fn->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
    return true;
  }
  MsExpr *index_left = NULL;
  MsExpr *index_key = NULL;
  if (base->kind != MS_E_MEMBER && !ms_expr_index(base, &index_left, &index_key)) {
    return fn_fail(fn, "assignment into this place is not lowered yet (expression kind %d at %u:%u)", (int)base->kind, base->pos.line, base->pos.column);
  }
  const MirValue inner = fn_expr(fn, base, LW_BORROW);
  if (inner == MIR_NONE) {
    return false;
  }
  *out = fn_implicit_clone(fn, inner, true);
  fn_disown(fn, *out);
  return true;
}

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
    if (fn_owned_local(fn, base, &var) || closing_local(fn, base, &slot, &slot_ty) || closing_param(fn, base, &slot, &var)) {
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

/* Stores `field`, the changed value of the field `fn_take_field` took, back: the old ones share its storage, so they
 * are not dropped. */
bool fn_put_field(LowerFn *fn, const MsExpr *place, MirValue record, MirValue field) {
  return fn_put_field_chain(fn, place, record, field, NULL);
}

/* The same, and `*updated_record` is the root record with the field changed: a later field of the same root is put
 * into that, not into the record the first one replaced. */
bool fn_put_field_chain(LowerFn *fn, const MsExpr *place, MirValue record, MirValue field, MirValue *updated_record) {
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
  return fn_put_place(fn, root, updated);
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
static bool fn_same_member_path(LowerFn *fn, const MsExpr *a, const MsExpr *b) {
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

/* `base.field = value` where `base` is an owning local or a member path: the record is taken out of its place
 * (a path's inner record is copied), the old field is dropped, `type.set` makes the updated record and that is
 * stored back into the place of `base`. `value` is owned and held by no scope. */
static bool set_member(LowerFn *fn, const MsExpr *place, MirValue value) {
  const MsRef *ref = ms_facts_ref(fn->facts, place->id);
  const MsExpr *base = place->u.member.left;
  if (ref == NULL || ref->kind != MS_REF_FIELD) {
    return fn_fail(fn, "this member is not a record field");
  }
  MirValue record = MIR_NONE;
  if (!fn_take_place(fn, base, &record)) {
    return false;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, record));
  if (data->kind != MK_TYPE) {
    return fn_fail(fn, "a field is assigned in a record (found MIR kind %d)", (int)data->kind);
  }
  const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
  const MirTy field_ty = fn_type(fn, ms_facts_type(fn->facts, place->id));
  bool moved_out = false; /* an earlier bind took the field: there is nothing to drop */
  for (uint32_t at = 0; at < fn->nmoved_fields; at++) {
    if (fn_same_member_path(fn, fn->moved_fields[at], place)) {
      moved_out = true;
      fn->moved_fields[at] = fn->moved_fields[--fn->nmoved_fields];
      break;
    }
  }
  if (!moved_out && mir_needs_drop(fn->cx->module, field_ty)) {
    const MirValue old = mir_b_emit(&fn->b, MOP_TypeGet, &record, 1, imm, field_ty);
    const MsTy checked = ms_facts_type(fn->facts, place->id);
    if (fn_closer_for(fn, ms_facts_closer(fn->facts, place->id), checked)) {
      if (!fn_close_replaced(fn, checked, old)) { /* a resource the assignment replaces closes, it is not dropped */
        return false;
      }
    } else {
      (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
    }
  }
  const MirValue operands[2] = {record, value};
  const MirValue updated = mir_b_emit(&fn->b, MOP_TypeSet, operands, 2, imm, mir_b_ty(&fn->b, record));
  return fn_put_place(fn, base, updated);
}

/* `container[key] = value` for an element of a list or map the enclosing assignment took a copy of: the container's
 * own `set` (a list) or `add` (a map) stores it. */
static bool set_element(LowerFn *fn, const MsExpr *container, const MsExpr *key, MirValue value) {
  MsTyTable *types = &fn->cx->program->types;
  const MsTy owner = ms_ty_subst(types, ms_facts_type(fn->facts, container->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  const MirValue receiver = fn_expr(fn, container, LW_BORROW);
  const MirValue at = receiver == MIR_NONE ? MIR_NONE : fn_expr(fn, key, LW_BORROW);
  if (at == MIR_NONE) {
    return false;
  }
  const MirValue args[3] = {receiver, at, value};
  MirValue out = MIR_NONE;
  const MsSpan operation = ms_span_of_text(ms_ty_is(types, owner, MS_BUILTIN_Map) ? "add" : "set");
  if (!fn_native_on(fn, container, owner, operation, 3, args, MIR_VOID, &out)) {
    return fn_fail(fn, "an element of this container cannot be assigned yet");
  }
  return !fn->failed;
}

/* Stores the owned `value` (held by no scope) into `place`, the place of an earlier `fn_take_place`. */
bool fn_put_place(LowerFn *fn, const MsExpr *place, MirValue value) {
  MirVar var;
  if (place->kind == MS_E_MEMBER) {
    return set_member(fn, place, value);
  }
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (ms_expr_index(place, &container, &key)) {
    return set_element(fn, container, key, value);
  }
  MirValue slot;
  MirTy slot_ty;
  if (closing_local(fn, place, &slot, &slot_ty)) {
    const MirValue stored[2] = {slot, value};
    (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slot_ty) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
    return !fn->failed;
  }
  if (closing_param(fn, place, &slot, &var)) {
    const MirTy ty = mir_b_ty(&fn->b, value);
    const MirValue stored[2] = {slot, value};
    (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
    mir_b_def_var(&fn->b, var, mir_b_emit(&fn->b, MOP_Load, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty));
    return !fn->failed;
  }
  if (!fn_owned_local(fn, place, &var)) {
    return fn_fail(fn, "an assignment does not name an owning local");
  }
  mir_b_def_var(&fn->b, var, value);
  return !fn->failed;
}
