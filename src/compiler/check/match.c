/* compiler/check/match.c: `match` expressions: arm patterns bind a case's payload; the result is the first
 * typed arm value (or the expected type). */
#include "compiler/check/body.h"
#include "compiler/check/suggest.h"

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
    (void)body_declare(body, arm->bindings.ptr[at].name, ty, MS_REF_LOCAL, false, arm->id, arm->pos);
  }
  body_block(body, arm->body);
  const MsTy value = arm->value != NULL ? body_expr(body, arm->value, expected) : MS_TY_NONE;
  body_scope_reset(body, mark);
  return value;
}

/* Whether `ty` is known and a match cannot take it: not an alternative, an interface value, Int, String or Bool. */
static bool unmatchable(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  const MsTyKind kind = (MsTyKind)ms_ty_kind(types, ty);
  if (ty == MS_TY_NONE || ms_ty_has_variable(types, ty) || ms_ty_is(types, ty, MS_BUILTIN_Never)) {
    return false;
  }
  if (kind == MS_TY_ALTERNATIVE || kind == MS_TY_CONTRACT || kind == MS_TY_INVALID || kind == MS_TY_INFERRED) {
    return false;
  }
  return !ms_ty_is(types, ty, MS_BUILTIN_Int) && !ms_ty_is(types, ty, MS_BUILTIN_String) &&
         !ms_ty_is(types, ty, MS_BUILTIN_Bool);
}

static void check_scrutinee(Body *body, const MsExpr *expr, MsTy ty) {
  if (body->quiet || body->module >= body->program->user_modules || !unmatchable(body, ty)) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "match requires an alternative, contract view, Int, String or Bool, found ");
  ms_ty_show(&text, body->program->names, &body->program->types, ty);
  ms_strbuild_append_text(&text, "; match on a type with cases, or use if/else");
  ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* A match over a user enum that names none of the cases it misses and has no `_` arm: the cases it misses, the
 * arms that would cover them. Arms that are not known cases leave the match to their own diagnostics. */
static void check_exhaustive(Body *body, const MsExpr *expr, MsTy scrutinee) {
  const MsDef *def = body_def(body, scrutinee);
  MsCheckProgram *program = body->program;
  if (body->quiet || body->module >= program->user_modules || def == NULL || def->kind != MS_TY_ALTERNATIVE ||
      ms_ty_kind(&program->types, scrutinee) != MS_TY_ALTERNATIVE) {
    return;
  }
  const MsDecl *home = program->symbols.ptr[def->symbol].decl;
  if (home == NULL || home->kind != MS_D_ENUM) {
    return;
  }
  uint8_t *seen = MS_ARENA_NEW_ARRAY(&body->program->arena, uint8_t, def->cases.len + 1);
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsArm *arm = expr->u.match.arms.ptr[index];
    uint32_t at = 0;
    if (arm->path != NULL && arm->path->kind == MS_E_NAME &&
        ms_span_is_text(ms_names_span(program->names, arm->path->u.sym), "_")) {
      return;
    }
    if (arm_case(body, arm->path, scrutinee, &at) == NULL) {
      return;
    }
    seen[at] = 1;
  }
  MsSpanList names = {0};
  MsStrBuild arms = ms_strbuild_new();
  size_t shown = 0;
  for (size_t index = 0; index < def->cases.len; index++) {
    if (seen[index]) {
      continue;
    }
    const MsTyCase *kase = &def->cases.ptr[index];
    ms_span_list_push(&names, ms_names_span(program->names, kase->name));
    if (shown++ >= 12) {
      continue;
    }
    ms_strbuild_append_text(&arms, shown > 1 ? ", '" : "'");
    ms_strbuild_append(&arms, ms_names_span(program->names, kase->name));
    for (size_t field = 0; field < kase->fields.len; field++) {
      ms_strbuild_append_text(&arms, field == 0 ? "(" : ", ");
      ms_strbuild_append(&arms, ms_names_span(program->names, kase->fields.ptr[field].name));
    }
    ms_strbuild_append_text(&arms, kase->fields.len != 0 ? "):'" : ":'");
  }
  if (names.len != 0) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "non-exhaustive match; missing cases: ");
    ms_suggest_list(&text, &names, 12);
    ms_strbuild_append_text(&text, ", or add a final '_:' arm; add the arms ");
    ms_strbuild_append(&text, ms_strbuild_span(&arms));
    ms_strbuild_append_text(&text, names.len > 12 ? ", ..." : "");
    ms_check_report(program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  ms_strbuild_free(&arms);
  ms_span_list_free(&names);
}

MsTy body_match(Body *body, const MsExpr *expr, MsTy expected) {
  const MsTy scrutinee = body_expr(body, expr->u.match.scrutinee, MS_TY_NONE);
  check_scrutinee(body, expr, scrutinee);
  /* An expected type that still names an open variable guides the arms but is not the result: the arms decide it. */
  MsTy result = expected != MS_TY_NONE && body_has_foreign_variable(body, expected) ? MS_TY_NONE : expected;
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsTy value = arm_value(body, expr->u.match.arms.ptr[index], scrutinee, result == MS_TY_NONE ? expected : result);
    result = result == MS_TY_NONE ? value : result;
  }
  check_exhaustive(body, expr, scrutinee);
  return result;
}
