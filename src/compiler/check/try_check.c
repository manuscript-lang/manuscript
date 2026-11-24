/* The `?` operator: its operand must be a Result or an Optional the enclosing function can return from. */
#include "body.h"

static void report(Body *body, const MsExpr *expr, MsStrBuild *text) {
  ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(text));
}

static void show(const Body *body, MsStrBuild *out, MsTy ty) {
  ms_ty_show(out, body->program->names, &body->program->types, ty);
}

void body_check_try(Body *body, const MsExpr *expr, MsTy operand) {
  const MsTyTable *types = &body->program->types;
  if (!body_reports(body) || body->quiet || operand == MS_TY_NONE) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  const bool optional = ms_ty_is(types, operand, MS_BUILTIN_Optional) && ms_ty_arg_count(types, operand) == 1;
  const bool result = ms_ty_is(types, operand, MS_BUILTIN_Result) && ms_ty_arg_count(types, operand) == 2;
  const MsTy enclosing = body->result;
  if (!optional && !result) {
    ms_strbuild_append_text(&text, "'?' requires a Result or an Optional, found ");
    show(body, &text, operand);
    ms_strbuild_append_text(&text, "; apply '?' to a value of type Result[T, E] or T?");
    report(body, expr, &text);
    return;
  }
  if (enclosing == MS_TY_NONE) {
    ms_strbuild_free(&text);
    return;
  }
  if (optional) {
    const bool returns_optional = ms_ty_is(types, enclosing, MS_BUILTIN_Optional);
    if (!returns_optional && !ms_ty_is(types, enclosing, MS_BUILTIN_Void)) {
      ms_strbuild_append_text(&text, "'?' on an Optional leaves the function when the value is absent, so the "
                                     "function must return an Optional or Void; declare it to return T?, or use "
                                     "'if x != null', or 'x or default'");
      report(body, expr, &text);
      return;
    }
    ms_strbuild_free(&text);
    return;
  }
  if (!ms_ty_is(types, enclosing, MS_BUILTIN_Result) || ms_ty_arg_count(types, enclosing) != 2) {
    ms_strbuild_append_text(&text, "'?' requires an enclosing Result; declare this function to return Result[T, E], "
                                   "or use 'if value := x', '.get_or(default)', or '.get()'");
    report(body, expr, &text);
    return;
  }
  const MsTy returned = ms_ty_args(types, enclosing)[1];
  if (returned == ms_ty_args(types, operand)[1] || ms_ty_is_invalid(types, returned)) {
    ms_strbuild_free(&text);
    return;
  }
  ms_strbuild_append_text(&text, "'?' requires the same error type; this function returns ");
  show(body, &text, enclosing);
  ms_strbuild_append_text(&text, " but the operand fails with ");
  show(body, &text, ms_ty_args(types, operand)[1]);
  ms_strbuild_append_text(&text, ", so change the return error type or translate the error with map_error");
  report(body, expr, &text);
}

/* An expression statement discards its value: a `?` must leave Void, and a Result must not be dropped silently. */
void body_check_call_statement(Body *body, const MsStmt *stmt, MsTy value) {
  const MsTyTable *types = &body->program->types;
  if (!body_reports(body) || body->quiet || value == MS_TY_NONE || stmt == body->bench_last ||
      ms_ty_is_invalid(types, value)) {
    return;
  }
  const MsExpr *expr = stmt->u.expr;
  const bool try_op = expr->kind == MS_E_UNARY && expr->op == MS_U_TRY;
  MsStrBuild text = ms_strbuild_new();
  if (try_op) {
    if (ms_ty_is(types, value, MS_BUILTIN_Void)) {
      ms_strbuild_free(&text);
      return;
    }
    ms_strbuild_append_text(&text, "a standalone '?' requires a Void success value, found ");
    show(body, &text, value);
    ms_strbuild_append_text(&text, "; use 'name := call()?' to keep the value or 'return call()?' to return it");
    report(body, expr, &text);
    return;
  }
  if (!ms_ty_is(types, value, MS_BUILTIN_Result) || ms_ty_is_invalid(types, ms_ty_args(types, value)[0]) ||
      ms_ty_is_invalid(types, ms_ty_args(types, value)[1])) {
    ms_strbuild_free(&text);
    return;
  }
  ms_strbuild_append_text(&text, "this statement discards ");
  show(body, &text, value);
  ms_strbuild_append_text(&text, ", so a failure would be lost; write a trailing '?' to propagate it, 'if value := x' "
                                 "or 'match' to handle it, or 'void ...' to drop it on purpose");
  ms_check_report(body->program, body->module, stmt->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}
