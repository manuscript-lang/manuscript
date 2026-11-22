/* compiler/check/match.c: `match` expressions: arm patterns bind a case's payload; the result is the first
 * typed arm value (or the expected type). */
#include "compiler/check/body.h"

/* The case an arm path names (`Case` or `Type.Case`) in the scrutinee's enum. */
static const MsTyCase *arm_case(Body *body, const MsExpr *path, MsTy scrutinee, uint32_t *index) {
  if (path == NULL) {
    return NULL;
  }
  const MsName name = path->kind == MS_E_MEMBER ? path->u.member.name : path->u.sym;
  if (path->kind != MS_E_MEMBER && path->kind != MS_E_NAME) {
    return NULL;
  }
  return body_case_of(body, scrutinee, name, index);
}

/* The payload field type of `kase` under the scrutinee's arguments. */
static MsTy payload(Body *body, MsTy scrutinee, const MsTyCase *kase, uint32_t at) {
  if (at >= kase->fields.len) {
    return MS_TY_NONE;
  }
  const MsTyRow *row = ms_ty_row(&body->program->types, scrutinee);
  const MsDef *def = body_def(body, scrutinee);
  if (def == NULL || def->variables.len != row->arg_count) {
    return kase->fields.ptr[at].ty;
  }
  return ms_ty_subst(&body->program->types, kase->fields.ptr[at].ty, def->variables.ptr,
                     ms_ty_args(&body->program->types, scrutinee), row->arg_count);
}

/* `value:` on an optional names the payload. */
static MsTy bare_payload(const Body *body, const MsArm *arm, MsTy scrutinee) {
  const MsTyTable *types = &body->program->types;
  return arm->bare && ms_ty_is(types, scrutinee, MS_BUILTIN_Optional) && ms_ty_arg_count(types, scrutinee) == 1
             ? ms_ty_args(types, scrutinee)[0]
             : MS_TY_NONE;
}

static MsTy arm_value(Body *body, const MsArm *arm, MsTy scrutinee, MsTy expected) {
  const size_t mark = body_scope_mark(body);
  uint32_t index = 0;
  const MsTyCase *kase = arm_case(body, arm->path, scrutinee, &index);
  if (kase != NULL) {
    /* The bindings are declared next, so their locals run from `next_local` in order. */
    body_set_ref(body, arm->id,
                 (MsRef){.kind = MS_REF_CASE, .index = index, .local = body->next_local, .owner = scrutinee});
  }
  if (kase == NULL && bare_payload(body, arm, scrutinee) != MS_TY_NONE) {
    body_set_ref(body, arm->id, (MsRef){.kind = MS_REF_CASE, .index = 1, .local = body->next_local, .owner = scrutinee});
  }
  for (uint32_t at = 0; at < arm->bindings.len; at++) {
    const MsTy ty = kase != NULL ? payload(body, scrutinee, kase, at) : bare_payload(body, arm, scrutinee);
    (void)body_declare(body, arm->bindings.ptr[at].name, ty, MS_REF_LOCAL, false);
  }
  body_block(body, arm->body);
  const MsTy value = arm->value != NULL ? body_expr(body, arm->value, expected) : MS_TY_NONE;
  body_scope_reset(body, mark);
  return value;
}

MsTy body_match(Body *body, const MsExpr *expr, MsTy expected) {
  const MsTy scrutinee = body_expr(body, expr->u.match.scrutinee, MS_TY_NONE);
  MsTy result = expected;
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsTy value = arm_value(body, expr->u.match.arms.ptr[index], scrutinee, result);
    result = result == MS_TY_NONE ? value : result;
  }
  return result;
}
