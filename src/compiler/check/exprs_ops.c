/* compiler/check/exprs_ops.c: types of literals, text and the unary and binary operators (port of infer_number,
 * infer_text, infer_unary and infer_binary of crates/ms-check/src/exprs.rs). This file computes result types and
 * records the operand conversions the lowering needs; diagnostics for ill-typed operands come in a later change,
 * so an operand that does not fit yields the invalid type. */
#include "compiler/check/body.h"

/* ---- classifying types ---- */

static bool is_sized_int(const Body *body, MsTy ty) {
  const MsBuiltin builtin = ms_ty_builtin(&body->program->types, ty);
  return ms_builtin_is_int(builtin) && builtin != MS_BUILTIN_Int;
}

static bool is_sized_float(const Body *body, MsTy ty) {
  const MsBuiltin builtin = ms_ty_builtin(&body->program->types, ty);
  return ms_builtin_is_float(builtin) && builtin != MS_BUILTIN_Float;
}

static bool is_numeric(const Body *body, MsTy ty) {
  const MsBuiltin builtin = ms_ty_builtin(&body->program->types, ty);
  return ms_builtin_is_int(builtin) || ms_builtin_is_float(builtin) || builtin == MS_BUILTIN_BigInt ||
         builtin == MS_BUILTIN_Decimal;
}

static bool is_invalid(const Body *body, MsTy ty) {
  return ty == MS_TY_NONE || ms_ty_is_invalid(&body->program->types, ty);
}

/* ---- number literals ---- */

typedef enum NumberKind { NUMBER_INT, NUMBER_FLOAT, NUMBER_DECIMAL } NumberKind;

static NumberKind number_kind(MsSpan text) {
  if (text.len > 1 && text.ptr[0] == '0' && (text.ptr[1] == 'x' || text.ptr[1] == 'b')) {
    return NUMBER_INT;
  }
  if (text.len > 0 && text.ptr[text.len - 1] == 'd') {
    return NUMBER_DECIMAL;
  }
  for (size_t index = 0; index < text.len; index++) {
    const uint8_t byte = text.ptr[index];
    if (byte == '.' || byte == 'e' || byte == 'E') {
      return NUMBER_FLOAT;
    }
  }
  return NUMBER_INT;
}

static MsSpan number_text(const Body *body, const MsExpr *expr) {
  return ms_names_span(body->program->names, expr->u.sym);
}

/* The type of a number literal: a sized type from `expected` when the literal kind matches it. */
static MsTy number_type(Body *body, const MsExpr *expr, MsTy expected) {
  const NumberKind kind = number_kind(number_text(body, expr));
  if (kind == NUMBER_DECIMAL) {
    const MsSymbol *decimal = body_find_symbol(body, ms_names_intern(body->program->names, ms_span_of_text("Decimal")));
    return decimal != NULL ? decimal->ty : MS_TY_NONE;
  }
  if (kind == NUMBER_FLOAT) {
    return is_sized_float(body, expected) ? expected : body_primitive(body, MS_BUILTIN_Float);
  }
  return is_sized_int(body, expected) ? expected : body_primitive(body, MS_BUILTIN_Int);
}

/* ---- text ---- */

static MsTy text_type(Body *body, const MsExpr *expr) {
  for (uint32_t index = 0; index < expr->u.text.len; index++) {
    if (expr->u.text.ptr[index].expr != NULL) {
      (void)body_expr(body, expr->u.text.ptr[index].expr, MS_TY_NONE);
    }
  }
  return body_primitive(body, MS_BUILTIN_String);
}

MsTy body_literal(Body *body, const MsExpr *expr, MsTy expected) {
  MsTy ty = MS_TY_NONE;
  switch ((MsExprKind)expr->kind) {
    case MS_E_NUMBER: ty = number_type(body, expr, expected); break;
    case MS_E_BOOL: ty = body_primitive(body, MS_BUILTIN_Bool); break;
    case MS_E_VOID: ty = body_primitive(body, MS_BUILTIN_Void); break;
    case MS_E_TEXT: ty = text_type(body, expr); break;
    default: break;
  }
  body_set_type(body, expr->id, ty);
  return ty;
}

/* ---- literal hints ---- */

/* 0 for no literal tree, else 1 for an integer literal tree and 2 for a fractional one: a number, a sign on
 * one, or arithmetic over them. */
static int literal_tree(const Body *body, const MsExpr *expr) {
  if (expr->kind == MS_E_NUMBER) {
    const NumberKind kind = number_kind(number_text(body, expr));
    return kind == NUMBER_INT ? 1 : (kind == NUMBER_FLOAT ? 2 : 0);
  }
  if (expr->kind == MS_E_UNARY && (expr->op == MS_U_NEG || expr->op == MS_U_PLUS)) {
    return literal_tree(body, expr->u.bin.left);
  }
  if (expr->kind != MS_E_BINARY || expr->op < MS_B_ADD) {
    return 0;
  }
  const int left = literal_tree(body, expr->u.bin.left);
  const int right = literal_tree(body, expr->u.bin.right);
  return left == 0 || right == 0 ? 0 : (left > right ? left : right);
}

/* The sized type of `other` when an unsuffixed literal tree beside it should take that type. */
static MsTy literal_hint(const Body *body, const MsExpr *expr, MsTy other) {
  const int kind = literal_tree(body, expr);
  if ((kind == 1 && is_sized_int(body, other)) || (kind == 2 && is_sized_float(body, other))) {
    return other;
  }
  return MS_TY_NONE;
}

/* ---- unary ---- */

/* `-` on a number literal: the literal takes its sized type from `expected` (-128 fits Int8). */
static MsTy negated_literal(Body *body, const MsExpr *expr, MsTy expected) {
  const MsExpr *operand = expr->u.bin.left;
  const MsTy ty = number_type(body, operand, expected);
  body_set_type(body, operand->id, ty);
  return ty;
}

static MsTy try_type(Body *body, MsTy operand) {
  const MsTyTable *types = &body->program->types;
  const bool optional = ms_ty_is(types, operand, MS_BUILTIN_Optional) && ms_ty_arg_count(types, operand) == 1;
  const bool result = ms_ty_is(types, operand, MS_BUILTIN_Result) && ms_ty_arg_count(types, operand) == 2;
  return optional || result ? ms_ty_args(types, operand)[0] : MS_TY_NONE;
}

MsTy body_unary(Body *body, const MsExpr *expr, MsTy expected) {
  const MsUnaryOp op = (MsUnaryOp)expr->op;
  const MsExpr *operand = expr->u.bin.left;
  MsTy ty = MS_TY_NONE;
  if (op == MS_U_NEG && operand->kind == MS_E_NUMBER && number_kind(number_text(body, operand)) != NUMBER_DECIMAL) {
    ty = negated_literal(body, expr, expected);
  } else {
    const bool signed_op = op == MS_U_NEG || op == MS_U_PLUS;
    const MsTy hint = signed_op ? literal_hint(body, operand, expected) : MS_TY_NONE;
    const MsTy value = body_expr(body, operand, hint);
    if (op == MS_U_NOT) {
      ty = body_primitive(body, MS_BUILTIN_Bool);
    } else if (op == MS_U_TRY) {
      ty = try_type(body, value);
    } else if (is_numeric(body, value)) {
      ty = value;
    }
  }
  body_set_type(body, expr->id, ty);
  return ty;
}

/* ---- binary ---- */

static bool is_logical(MsBinaryOp op) {
  return op == MS_B_AND || op == MS_B_OR;
}

static bool is_comparison(MsBinaryOp op) {
  return op >= MS_B_EQ && op <= MS_B_GE;
}

/* The type of `Instant`/`Duration` arithmetic, or MS_TY_NONE when the operands select no row. */
static MsTy time_type(const Body *body, MsBinaryOp op, MsTy left, MsTy right) {
  const MsTyTable *types = &body->program->types;
  const MsBuiltin a = ms_ty_builtin(types, left);
  const MsBuiltin b = ms_ty_builtin(types, right);
  if (a == MS_BUILTIN_Duration && b == MS_BUILTIN_Duration) {
    return left;
  }
  if (a == MS_BUILTIN_Instant && b == MS_BUILTIN_Duration) {
    return left;
  }
  if (a == MS_BUILTIN_Instant && b == MS_BUILTIN_Instant && op == MS_B_SUB) {
    const MsSymbol *duration = body_find_symbol(body, ms_names_intern(body->program->names, ms_span_of_text("Duration")));
    return duration != NULL ? duration->ty : MS_TY_NONE;
  }
  return MS_TY_NONE;
}

/* Types the two operands. Literals beside a sized number take its type; arithmetic over literals alone takes the
 * expected sized type. */
static void operand_types(Body *body, const MsExpr *expr, MsTy expected, MsTy *left, MsTy *right) {
  const MsBinaryOp op = (MsBinaryOp)expr->op;
  const MsExpr *l = expr->u.bin.left;
  const MsExpr *r = expr->u.bin.right;
  const bool arithmetic = op >= MS_B_ADD;
  const MsTy hint = arithmetic ? literal_hint(body, l, expected) : MS_TY_NONE;
  if (hint != MS_TY_NONE && literal_hint(body, r, expected) != MS_TY_NONE) {
    *left = body_expr(body, l, hint);
    *right = body_expr(body, r, hint);
  } else if (literal_tree(body, l) == 2 && literal_tree(body, r) != 2) {
    *right = body_expr(body, r, MS_TY_NONE);
    *left = body_expr(body, l, literal_hint(body, l, *right));
  } else {
    *left = body_expr(body, l, MS_TY_NONE);
    const bool wraps = (op == MS_B_EQ || op == MS_B_NE) &&
                       ms_ty_is(&body->program->types, *left, MS_BUILTIN_Optional) &&
                       ms_ty_arg_count(&body->program->types, *left) == 1;
    *right = body_expr(body, r, wraps ? *left : literal_hint(body, r, *left));
  }
}

/* Records `T` to `T?` on the plain side of an equality against an optional. */
static void record_wrap(Body *body, const MsExpr *plain, MsTy from, MsTy to) {
  const MsConversion conversion = {plain->id, MS_CONV_OPTIONAL_WRAP, from, to};
  ms_facts_add_conversion(body->facts, &conversion);
}

static MsTy equality_type(Body *body, const MsExpr *expr, MsTy left, MsTy right) {
  const MsTyTable *types = &body->program->types;
  const bool left_optional = ms_ty_is(types, left, MS_BUILTIN_Optional) && ms_ty_arg_count(types, left) == 1;
  const bool right_optional = ms_ty_is(types, right, MS_BUILTIN_Optional) && ms_ty_arg_count(types, right) == 1;
  if (left_optional && !right_optional && right == ms_ty_args(types, left)[0]) {
    record_wrap(body, expr->u.bin.right, right, left);
  } else if (right_optional && !left_optional && left == ms_ty_args(types, right)[0]) {
    record_wrap(body, expr->u.bin.left, left, right);
  }
  return body_primitive(body, MS_BUILTIN_Bool);
}

/* An operand is a Duration or an Instant: the time rows of the operator table decide, not the mismatch report. */
static bool time_operands(const Body *body, MsTy left, MsTy right) {
  const MsTyTable *types = &body->program->types;
  return ms_ty_is(types, left, MS_BUILTIN_Duration) || ms_ty_is(types, left, MS_BUILTIN_Instant) ||
         ms_ty_is(types, right, MS_BUILTIN_Duration) || ms_ty_is(types, right, MS_BUILTIN_Instant);
}

static MsTy arithmetic_type(Body *body, MsBinaryOp op, MsTy left, MsTy right) {
  const bool time = ms_ty_is(&body->program->types, left, MS_BUILTIN_Duration) ||
                    ms_ty_is(&body->program->types, left, MS_BUILTIN_Instant) ||
                    ms_ty_is(&body->program->types, right, MS_BUILTIN_Duration);
  if (time && (op == MS_B_ADD || op == MS_B_SUB)) {
    return time_type(body, op, left, right);
  }
  const bool text = ms_ty_is(&body->program->types, left, MS_BUILTIN_String);
  if (left != right || !(is_numeric(body, left) || (text && op == MS_B_ADD))) {
    return MS_TY_NONE;
  }
  return left;
}

MsTy body_binary(Body *body, const MsExpr *expr, MsTy expected) {
  const MsBinaryOp op = (MsBinaryOp)expr->op;
  MsTy left = MS_TY_NONE;
  MsTy right = MS_TY_NONE;
  operand_types(body, expr, expected, &left, &right);
  MsTy ty = MS_TY_NONE;
  if (is_logical(op)) {
    ty = body_primitive(body, MS_BUILTIN_Bool);
  } else if (is_invalid(body, left) || is_invalid(body, right)) {
    ty = is_comparison(op) ? body_primitive(body, MS_BUILTIN_Bool) : MS_TY_NONE;
  } else if (!time_operands(body, left, right) && body_report_operand_mismatch(body, expr, left, right)) {
    ty = is_comparison(op) ? body_primitive(body, MS_BUILTIN_Bool) : MS_TY_NONE;
  } else if (op == MS_B_EQ || op == MS_B_NE) {
    ty = equality_type(body, expr, left, right);
  } else if (is_comparison(op)) {
    ty = body_primitive(body, MS_BUILTIN_Bool);
  } else {
    ty = arithmetic_type(body, op, left, right);
  }
  body_set_type(body, expr->id, ty);
  return ty;
}
