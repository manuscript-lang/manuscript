/* compiler/check/exprs_mismatch.c: the diagnostic for binary operands that do not share one type (port of the
 * mismatch branch of infer_binary in crates/ms-check/src/exprs.rs). Only operand pairs that cannot be told
 * apart from a mistake are reported: two different primitives, or an Optional, a Result or a function beside
 * a primitive. Everything else stays with the later operator checks. */
#include "compiler/check/body.h"
#include "compiler/syntax/walk.h"

static bool is_simple(const Body *body, MsTy ty) {
  const MsBuiltin builtin = ms_ty_builtin(&body->program->types, ty);
  return ms_builtin_is_int(builtin) || ms_builtin_is_float(builtin) || builtin == MS_BUILTIN_BigInt ||
         builtin == MS_BUILTIN_Decimal || builtin == MS_BUILTIN_Bool || builtin == MS_BUILTIN_String;
}

static bool is_wrapper(const Body *body, MsTy ty, MsBuiltin builtin, size_t arguments) {
  return ms_ty_is(&body->program->types, ty, builtin) &&
         ms_ty_arg_count(&body->program->types, ty) == arguments;
}

static bool is_optional(const Body *body, MsTy ty) {
  return is_wrapper(body, ty, MS_BUILTIN_Optional, 1);
}

static bool is_result(const Body *body, MsTy ty) {
  return ms_ty_is(&body->program->types, ty, MS_BUILTIN_Result) &&
         ms_ty_arg_count(&body->program->types, ty) > 0;
}

static bool is_function(const Body *body, MsTy ty) {
  return ms_ty_kind(&body->program->types, ty) == MS_TY_FUNCTION;
}

/* `other` beside `odd`, a type that no primitive operand can meet. */
static bool odd_beside_simple(const Body *body, MsTy odd, MsTy other) {
  return is_simple(body, other) && (is_optional(body, odd) || is_result(body, odd) || is_function(body, odd));
}

static bool operands_differ(const Body *body, MsBinaryOp op, MsTy left, MsTy right) {
  if (left == right) {
    return false;
  }
  if (is_simple(body, left) && is_simple(body, right)) {
    return true;
  }
  const bool equality = op == MS_B_EQ || op == MS_B_NE;
  const MsTyTable *types = &body->program->types;
  if (equality && is_optional(body, left) && ms_ty_args(types, left)[0] == right) {
    return false;
  }
  if (equality && is_optional(body, right) && ms_ty_args(types, right)[0] == left) {
    return false;
  }
  return odd_beside_simple(body, left, right) || odd_beside_simple(body, right, left);
}

static const char *operator_text(MsBinaryOp op) {
  switch (op) {
  case MS_B_EQ:
    return "==";
  case MS_B_NE:
    return "!=";
  case MS_B_LT:
    return "<";
  case MS_B_GT:
    return ">";
  case MS_B_LE:
    return "<=";
  case MS_B_GE:
    return ">=";
  case MS_B_ADD:
    return "+";
  case MS_B_SUB:
    return "-";
  case MS_B_MUL:
    return "*";
  case MS_B_DIV:
    return "/";
  default:
    return "%";
  }
}

static void append_type(const Body *body, MsStrBuild *text, MsTy ty) {
  ms_ty_show(text, body->program->names, &body->program->types, ty);
}

/* An Optional used where its payload is wanted. */
static bool optional_hint(const Body *body, MsStrBuild *text, MsTy actual, MsTy other) {
  if (!is_optional(body, actual) || is_optional(body, other)) {
    return false;
  }
  append_type(body, text, actual);
  ms_strbuild_append_text(text, " may be absent; unwrap it first with 'if value := x', get_or(default), "
                                "is_some() before get(), or match");
  return true;
}

/* A Result used where its success type is wanted. */
static bool result_hint(const Body *body, MsStrBuild *text, MsTy actual, MsTy other) {
  if (!is_result(body, actual) || ms_ty_args(&body->program->types, actual)[0] != other) {
    return false;
  }
  ms_strbuild_append_text(text, "unwrap it with a trailing '?' inside a function that returns a compatible "
                                "Result, with 'if value := x', or with '.get()'");
  return true;
}

/* A method named without its call, beside the type it returns. */
static bool uncalled_function(const Body *body, MsTy function, MsTy other) {
  const MsTyTable *types = &body->program->types;
  return is_function(body, function) && !is_function(body, other) &&
         ms_ty_param_count(types, function) == 0 && ms_ty_result(types, function) == other;
}

static bool int_float_mix(const Body *body, MsTy a, MsTy b) {
  const MsTyTable *types = &body->program->types;
  return (ms_ty_is(types, a, MS_BUILTIN_Int) && ms_ty_is(types, b, MS_BUILTIN_Float)) ||
         (ms_ty_is(types, a, MS_BUILTIN_Float) && ms_ty_is(types, b, MS_BUILTIN_Int));
}

static bool text_times_int(const Body *body, MsTy a, MsTy b) {
  const MsTyTable *types = &body->program->types;
  return (ms_ty_is(types, a, MS_BUILTIN_String) && ms_ty_is(types, b, MS_BUILTIN_Int)) ||
         (ms_ty_is(types, a, MS_BUILTIN_Int) && ms_ty_is(types, b, MS_BUILTIN_String));
}

static void append_hint(const Body *body, MsStrBuild *text, MsBinaryOp op, MsTy a, MsTy b) {
  if (uncalled_function(body, a, b) || uncalled_function(body, b, a)) {
    ms_strbuild_append_text(
        text, "this is a method, not a property; call it with parentheses, as in `xs.length()`");
  } else if (optional_hint(body, text, a, b) || optional_hint(body, text, b, a) ||
             result_hint(body, text, a, b) || result_hint(body, text, b, a)) {
    return;
  } else if (int_float_mix(body, a, b)) {
    ms_strbuild_append_text(
        text,
        "convert the Int with value.to_float(), or the Float with value.truncate_to_int() (returns Int?)");
  } else if (op == MS_B_MUL && text_times_int(body, a, b)) {
    ms_strbuild_append_text(
        text, "to repeat text write text.repeat(count), which returns a Result (append '?' to propagate it)");
  } else {
    ms_strbuild_append_text(text, "convert one side so both have one type (e.g. interpolate into text with "
                                  "f\"{value}\", or convert between Int and Float)");
  }
}

/* ---- the repairing edit ---- */

/* The source text of `expr`, or an empty span when it has none. */
static MsSpan expr_text(const Body *body, const MsExpr *expr) {
  const MsSpan source = body->program->modules.ptr[body->module].source;
  const MsPos start = ms_expr_start(expr);
  if (expr->end.offset <= start.offset || expr->end.offset > source.len) {
    return ms_span_of(NULL, 0);
  }
  return ms_span_of(source.ptr + start.offset, expr->end.offset - start.offset);
}

/* A written expression a `.method()` suffix or a `()` call binds to as a whole. */
static bool is_atomic(const MsExpr *expr) {
  return expr->kind == MS_E_NAME || expr->kind == MS_E_MEMBER || expr->kind == MS_E_CALL ||
         expr->kind == MS_E_INDEX || expr->kind == MS_E_APPLY || expr->kind == MS_E_LIST ||
         expr->kind == MS_E_MAP;
}

static bool all_digits(MsSpan text) {
  for (size_t at = 0; at < text.len; at++) {
    if (text.ptr[at] < '0' || text.ptr[at] > '9') {
      return false;
    }
  }
  return text.len > 0;
}

/* Replaces `expr` with `text` followed by `suffix`, parenthesizing the text unless `bare` says it binds. */
static void attach_rewrite(Body *body, const MsExpr *expr, MsSpan text, const char *suffix,
                           bool parenthesize) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, parenthesize ? "(" : "");
  ms_strbuild_append(&out, text);
  ms_strbuild_append_text(&out, parenthesize ? ")" : "");
  ms_strbuild_append_text(&out, suffix);
  ms_check_attach_fix(body->program, ms_expr_start(expr), expr->end, ms_strbuild_finish(&out));
  ms_strbuild_free(&out);
}

/* `value()` for a method written without its call. */
static void attach_parens(Body *body, const MsExpr *expr) {
  const MsSpan text = expr_text(body, expr);
  if (text.len > 0 && is_atomic(expr)) {
    attach_rewrite(body, expr, text, "()", false);
  }
}

/* `3` becomes `3.0`, any other Int expression `.to_float()`. */
static void attach_to_float(Body *body, const MsExpr *expr) {
  const MsSpan text = expr_text(body, expr);
  if (text.len == 0) {
    return;
  }
  if (expr->kind == MS_E_NUMBER) {
    if (all_digits(text)) {
      attach_rewrite(body, expr, text, ".0", false);
    }
    return;
  }
  attach_rewrite(body, expr, text, ".to_float()", !is_atomic(expr));
}

/* A compound assignment (`x += y`) desugars to `x = x + y`: the left operand is its target. */
static MsBinaryOp op_of(const MsExpr *expr) {
  return (MsBinaryOp)expr->op;
}

/* The operator's own width in the source. */
static size_t operator_length(MsBinaryOp op) {
  return op == MS_B_ADD || op == MS_B_SUB || op == MS_B_MUL || op == MS_B_DIV || op == MS_B_REM ? 1 : 2;
}

static bool is_compound(const Body *body, const MsExpr *expr) {
  const MsSpan source = body->program->modules.ptr[body->module].source;
  const size_t at = expr->pos.offset + operator_length(op_of(expr));
  return at < source.len && source.ptr[at] == '=';
}

static void attach_fix(Body *body, const MsExpr *expr, MsTy left, MsTy right) {
  const MsTyTable *types = &body->program->types;
  if (uncalled_function(body, left, right)) {
    attach_parens(body, expr->u.bin.left);
  } else if (uncalled_function(body, right, left)) {
    attach_parens(body, expr->u.bin.right);
  } else if (ms_ty_is(types, left, MS_BUILTIN_Int) && ms_ty_is(types, right, MS_BUILTIN_Float)) {
    if (!is_compound(body, expr)) {
      attach_to_float(body, expr->u.bin.left);
    }
  } else if (ms_ty_is(types, left, MS_BUILTIN_Float) && ms_ty_is(types, right, MS_BUILTIN_Int)) {
    attach_to_float(body, expr->u.bin.right);
  }
}

bool body_report_operand_mismatch(Body *body, const MsExpr *expr, MsTy left, MsTy right) {
  const MsBinaryOp op = (MsBinaryOp)expr->op;
  if (!operands_differ(body, op, left, right)) {
    return false;
  }
  if (body->quiet || body->module >= body->program->user_modules) {
    return true;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "operator operands require the same independently known type, found ");
  append_type(body, &text, left);
  ms_strbuild_append_text(&text, " ");
  ms_strbuild_append_text(&text, operator_text(op));
  ms_strbuild_append_text(&text, " ");
  append_type(body, &text, right);
  ms_strbuild_append_text(&text, "; ");
  append_hint(body, &text, op, left, right);
  ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  ms_strbuild_free(&text);
  attach_fix(body, expr, left, right);
  return true;
}
