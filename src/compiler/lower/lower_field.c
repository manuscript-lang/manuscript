/* compiler/lower/lower_field.c: a field of an owning local taken out and stored back for a native that changes it in place. */
#include "compiler/lower/lower_fn.h"
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
