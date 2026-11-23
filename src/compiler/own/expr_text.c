/* compiler/own/expr_text.c: how a diagnostic names an expression (see expr_text.h). */
#include "compiler/own/expr_text.h"

void ms_own_expr_text(MsStrBuild *out, const MsNames *names, const MsExpr *expr) {
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  if (expr->kind == MS_E_NAME) {
    ms_strbuild_append(out, ms_names_span(names, expr->u.sym));
  } else if (expr->kind == MS_E_MEMBER) {
    ms_own_expr_text(out, names, expr->u.member.left);
    ms_strbuild_append_text(out, ".");
    ms_strbuild_append(out, ms_names_span(names, expr->u.member.name));
  } else if (expr->kind == MS_E_CALL) {
    ms_own_expr_text(out, names, expr->u.call.callee);
    ms_strbuild_append_text(out, "(..)");
  } else if (ms_expr_index(expr, &left, &index)) {
    ms_own_expr_text(out, names, left);
    ms_strbuild_append_text(out, "[..]");
  } else {
    ms_strbuild_append_text(out, "this value");
  }
}
