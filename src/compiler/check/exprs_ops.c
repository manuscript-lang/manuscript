/* compiler/check/exprs_ops.c: literals, text and the unary and binary operators.
 *
 * Placeholder: the back end owner replaces this file with the full port of the oracle's operator typing. */
#include "compiler/check/body.h"

MsTy body_literal(Body *body, const MsExpr *expr, MsTy expected) {
  switch ((MsExprKind)expr->kind) {
  case MS_E_BOOL:
    return body_primitive(body, MS_BUILTIN_Bool);
  case MS_E_VOID:
    return body_primitive(body, MS_BUILTIN_Void);
  case MS_E_TEXT:
    for (uint32_t index = 0; index < expr->u.text.len; index++) {
      if (expr->u.text.ptr[index].expr != NULL) {
        (void)body_expr(body, expr->u.text.ptr[index].expr, MS_TY_NONE);
      }
    }
    return body_primitive(body, MS_BUILTIN_String);
  default:
    break;
  }
  const MsSpan text = ms_names_span(body->program->names, expr->u.sym);
  size_t at = 0;
  const bool fractional = ms_span_find(text, ms_span_of_text("."), &at);
  (void)expected;
  return body_primitive(body, fractional ? MS_BUILTIN_Float : MS_BUILTIN_Int);
}

MsTy body_unary(Body *body, const MsExpr *expr, MsTy expected) {
  const MsTy operand = body_expr(body, expr->u.bin.left, expected);
  return expr->op == MS_U_NOT ? body_primitive(body, MS_BUILTIN_Bool) : operand;
}

MsTy body_binary(Body *body, const MsExpr *expr, MsTy expected) {
  const MsTy left = body_expr(body, expr->u.bin.left, MS_TY_NONE);
  const MsTy right = body_expr(body, expr->u.bin.right, left);
  (void)right;
  (void)expected;
  switch ((MsBinaryOp)expr->op) {
  case MS_B_ADD: case MS_B_SUB: case MS_B_MUL: case MS_B_DIV: case MS_B_REM:
    return left;
  default:
    return body_primitive(body, MS_BUILTIN_Bool);
  }
}
