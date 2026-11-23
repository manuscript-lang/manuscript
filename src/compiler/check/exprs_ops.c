/* compiler/check/exprs_ops.c: types of literals, text and the unary and binary operators (port of infer_number,
 * infer_text, infer_unary and infer_binary of crates/ms-check/src/exprs.rs). This file computes result types and
 * records the operand conversions the lowering needs; diagnostics for ill-typed operands come in a later change,
 * so an operand that does not fit yields the invalid type. */
#include "compiler/check/body.h"
#include "compiler/syntax/walk.h"

/* ---- classifying types ---- */

static bool is_sized_int(const Body *body, MsTy ty) {
  const MsBuiltin builtin = ms_ty_builtin(&body->program->types, ty);
  return ms_builtin_is_int(builtin) && builtin != MS_BUILTIN_Int;
}

static bool is_sized_float(const Body *body, MsTy ty) {
  const MsBuiltin builtin = ms_ty_builtin(&body->program->types, ty);
  return ms_builtin_is_float(builtin) && builtin != MS_BUILTIN_Float;
}

static bool is_numeric_builtin(MsBuiltin builtin) {
  return ms_builtin_is_int(builtin) || ms_builtin_is_float(builtin) || builtin == MS_BUILTIN_BigInt ||
         builtin == MS_BUILTIN_Decimal;
}

/* A number type, or a type variable bounded by a set whose every member is one. */
static bool is_numeric(const Body *body, MsTy ty) {
  MsTyTable *types = &body->program->types;
  if (ms_ty_kind(types, ty) == MS_TY_VARIABLE) {
    const MsTyVariable *record = ms_ty_variable(types, ty);
    for (size_t index = 0; record != NULL && index < record->bounds.len; index++) {
      const MsTy bound = record->bounds.ptr[index];
      bool all = ms_ty_is(types, bound, MS_BUILTIN_TypeSet) && ms_ty_arg_count(types, bound) != 0;
      for (size_t at = 0; all && at < ms_ty_arg_count(types, bound); at++) {
        all = is_numeric_builtin(ms_ty_builtin(types, ms_ty_args(types, bound)[at]));
      }
      if (all) {
        return true;
      }
    }
    return false;
  }
  return is_numeric_builtin(ms_ty_builtin(types, ty));
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

/* Whether `ty` is a type variable bounded by a set of number types that all admit an `integer` or fractional
 * literal: `T: Numeric` takes `0` (the set holds integers), a set of floats takes `0.5`. */
static bool numeric_variable(Body *body, MsTy ty, bool integer) {
  MsTyTable *types = &body->program->types;
  if (ty == MS_TY_NONE || ms_ty_kind(types, ty) != MS_TY_VARIABLE) {
    return false;
  }
  const MsTyVariable *record = ms_ty_variable(types, ty);
  for (size_t index = 0; record != NULL && index < record->bounds.len; index++) {
    const MsTy bound = record->bounds.ptr[index];
    if (!ms_ty_is(types, bound, MS_BUILTIN_TypeSet) || ms_ty_arg_count(types, bound) == 0) {
      continue;
    }
    bool admits = true;
    bool has_integer = false;
    for (size_t at = 0; at < ms_ty_arg_count(types, bound); at++) {
      const MsBuiltin member = ms_ty_builtin(types, ms_ty_args(types, bound)[at]);
      has_integer = has_integer || ms_builtin_is_int(member);
      admits = admits && (ms_builtin_is_int(member) || ms_builtin_is_float(member)) &&
               (integer || ms_builtin_is_float(member));
    }
    if (admits && (!integer || has_integer)) {
      return true;
    }
  }
  return false;
}

/* A decimal literal needs the canonical `Decimal` import; once one diagnostic names `Decimal`, later literals stay
 * quiet. */
static void report_missing_decimal(Body *body, const MsExpr *expr) {
  MsCheckProgram *program = body->program;
  if (body->quiet || body->module >= program->user_modules) {
    return;
  }
  for (size_t index = 0; index < program->diagnostics.len; index++) {
    const MsCheckDiag *diag = &program->diagnostics.ptr[index];
    const MsSpan message = ms_string_span(&diag->message);
    if (diag->module == body->module && (ms_span_starts_with(message, ms_span_of_text("Decimal literal requires")) ||
                                         ms_span_starts_with(message, ms_span_of_text("unknown type Decimal")) ||
                                         ms_span_starts_with(message, ms_span_of_text("unknown binding Decimal")))) {
      return;
    }
  }
  ms_check_report(program, body->module, expr->pos, MS_CHECK_RESOLUTION,
                  ms_string_from_span(ms_span_of_text("Decimal literal requires the canonical Decimal import; add: "
                                                      "import Decimal from \"@std/math/decimal.ms\"")));
  const MsPos start = {.offset = 0, .line = 1, .column = 1};
  ms_check_attach_fix(program, start, start,
                      ms_string_from_span(ms_span_of_text("import Decimal from \"@std/math/decimal.ms\"\n")));
}

/* The type of a number literal: a sized type from `expected` when the literal kind matches it. */
static MsTy number_type(Body *body, const MsExpr *expr, MsTy expected, bool negated) {
  const MsTyTable *types = &body->program->types;
  if (expected != MS_TY_NONE && ms_ty_is(types, expected, MS_BUILTIN_Optional) && ms_ty_arg_count(types, expected) == 1) {
    expected = ms_ty_args(types, expected)[0]; /* a literal takes the sized type an optional wraps */
  }
  const NumberKind kind = number_kind(number_text(body, expr));
  if (kind == NUMBER_DECIMAL) {
    const MsSymbol *decimal = body_find_symbol(body, ms_names_intern(body->program->names, ms_span_of_text("Decimal")));
    if (decimal != NULL && decimal->module >= body->program->user_modules) {
      return decimal->ty;
    }
    report_missing_decimal(body, expr);
    return body_std_type(body, "Decimal", NULL, 0);
  }
  if (kind == NUMBER_FLOAT) {
    return is_sized_float(body, expected) || numeric_variable(body, expected, false) ? expected
                                                                                   : body_primitive(body, MS_BUILTIN_Float);
  }
  if (is_sized_int(body, expected)) {
    body_check_literal_range(body, expr, negated, expected);
    return expected;
  }
  return numeric_variable(body, expected, true) ? expected : body_primitive(body, MS_BUILTIN_Int);
}

/* The decimal literals inside a constant's initializer, which the constants pass leaves unreported. */
void body_report_decimal_literals(Body *body, const MsExpr *expr) {
  if (expr == NULL) {
    return;
  }
  switch ((MsExprKind)expr->kind) {
  case MS_E_NUMBER:
    if (number_kind(number_text(body, expr)) == NUMBER_DECIMAL) {
      const MsSymbol *decimal = body_find_symbol(body, ms_names_intern(body->program->names, ms_span_of_text("Decimal")));
      if (decimal == NULL || decimal->module < body->program->user_modules) {
        report_missing_decimal(body, expr);
      }
    }
    return;
  case MS_E_LIST:
    for (uint32_t index = 0; index < expr->u.list.len; index++) {
      body_report_decimal_literals(body, expr->u.list.ptr[index]);
    }
    return;
  case MS_E_MAP:
    for (uint32_t index = 0; index < expr->u.map.len; index++) {
      body_report_decimal_literals(body, expr->u.map.ptr[index].key);
      body_report_decimal_literals(body, expr->u.map.ptr[index].value);
    }
    return;
  case MS_E_UNARY:
    body_report_decimal_literals(body, expr->u.bin.left);
    return;
  case MS_E_BINARY:
    body_report_decimal_literals(body, expr->u.bin.left);
    body_report_decimal_literals(body, expr->u.bin.right);
    return;
  default:
    return;
  }
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
    case MS_E_NUMBER: ty = number_type(body, expr, expected, false); break;
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
  const MsTy ty = number_type(body, operand, expected, true);
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
      body_check_not(body, expr, value);
      ty = body_primitive(body, MS_BUILTIN_Bool);
    } else if (op == MS_U_TRY) {
      body_check_try(body, expr, value);
      ty = try_type(body, value);
    } else if (is_numeric(body, value)) {
      ty = value;
      const MsBuiltin builtin = ms_ty_builtin(&body->program->types, value);
      if (op == MS_U_NEG && (builtin == MS_BUILTIN_UInt8 || builtin == MS_BUILTIN_UInt16 || builtin == MS_BUILTIN_UInt32 ||
                             builtin == MS_BUILTIN_UInt64) &&
          body->module < body->program->user_modules && !body->quiet) {
        MsStrBuild text = ms_strbuild_new();
        ms_strbuild_append_text(&text, "unary - is not defined for ");
        ms_ty_show(&text, body->program->names, &body->program->types, value);
        ms_strbuild_append_text(&text, "; subtract from zero with a wider signed type, e.g. 0 - x.to_int()");
        ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      }
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

static bool collection_literal(const MsExpr *expr) {
  return expr->kind == MS_E_LIST || expr->kind == MS_E_MAP;
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
  } else if (collection_literal(l) && !collection_literal(r) && (op == MS_B_EQ || op == MS_B_NE)) {
    *right = body_expr(body, r, MS_TY_NONE); /* a literal beside a typed collection takes its type */
    *left = body_expr(body, l, *right);
  } else {
    *left = body_expr(body, l, MS_TY_NONE);
    const bool wraps = (op == MS_B_EQ || op == MS_B_NE) &&
                       ms_ty_is(&body->program->types, *left, MS_BUILTIN_Optional) &&
                       ms_ty_arg_count(&body->program->types, *left) == 1;
    const bool shaped = (op == MS_B_EQ || op == MS_B_NE) && collection_literal(r);
    *right = body_expr(body, r, wraps || shaped ? *left : literal_hint(body, r, *left));
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

static MsTy arithmetic_type(Body *body, const MsExpr *expr, MsBinaryOp op, MsTy left, MsTy right) {
  const bool text = ms_ty_is(&body->program->types, left, MS_BUILTIN_String);
  if (left != right || !(is_numeric(body, left) || (text && op == MS_B_ADD))) {
    if (left == right && !holds_invalid(&body->program->types, left, 6) && body->module < body->program->user_modules &&
        !body->quiet) {
      ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE,
                      ms_string_from_span(ms_span_of_text("arithmetic requires numeric operands")));
    }
    return left == right ? left : MS_TY_NONE;
  }
  return left;
}

static bool names_none(Body *body, const MsExpr *expr) {
  return expr->kind == MS_E_NAME && body_find_local(body, expr->u.sym) == NULL &&
         ms_span_is_text(ms_names_span(body->program->names, expr->u.sym), "none");
}

/* `x == none` and `x != none`: `none` takes its type from a target, and an operand is none. The other operand is
 * typed alone; it is reported unless it is itself wrong. */
static MsTy none_comparison(Body *body, const MsExpr *expr) {
  const MsExpr *other = names_none(body, expr->u.bin.left) ? expr->u.bin.right : expr->u.bin.left;
  const MsTy ty = body_expr(body, other, MS_TY_NONE);
  if (ty != MS_TY_NONE && !is_invalid(body, ty) && body->module < body->program->user_modules && !body->quiet) {
    const bool optional = ms_ty_is(&body->program->types, ty, MS_BUILTIN_Optional);
    ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE,
                    ms_string_from_span(ms_span_of_text(
                        "none has no type of its own here; test absence with `x.is_none()` or `x.is_some()` (`x != "
                        "none` is `x.is_some()`), or compare with the plain value, e.g. x == 3")));
    MsSpan text = {0};
    const MsPos start = ms_expr_start(other);
    if (optional && other->end.offset > start.offset && ms_span_slice(body->source, start.offset, other->end.offset, &text)) {
      MsStrBuild fix = ms_strbuild_new();
      const bool parens = !body_expr_is_atomic(other);
      ms_strbuild_append_text(&fix, parens ? "(" : "");
      ms_strbuild_append(&fix, text);
      ms_strbuild_append_text(&fix, parens ? ")" : "");
      ms_strbuild_append_text(&fix, expr->op == MS_B_NE ? ".is_some()" : ".is_none()");
      ms_check_attach_fix(body->program, ms_expr_start(expr), expr->end, ms_strbuild_finish(&fix));
    }
  }
  return body_primitive(body, MS_BUILTIN_Bool);
}

MsTy body_binary(Body *body, const MsExpr *expr, MsTy expected) {
  const MsBinaryOp op = (MsBinaryOp)expr->op;
  if ((op == MS_B_EQ || op == MS_B_NE) && (names_none(body, expr->u.bin.left) || names_none(body, expr->u.bin.right))) {
    const MsTy ty = none_comparison(body, expr);
    body_set_type(body, expr->id, ty);
    return ty;
  }
  MsTy left = MS_TY_NONE;
  MsTy right = MS_TY_NONE;
  operand_types(body, expr, expected, &left, &right);
  MsTy ty = MS_TY_NONE;
  if (is_logical(op)) {
    body_check_logical(body, expr, left, right);
    ty = body_primitive(body, MS_BUILTIN_Bool);
  } else if (is_invalid(body, left) || is_invalid(body, right)) {
    ty = is_comparison(op) ? body_primitive(body, MS_BUILTIN_Bool) : MS_TY_NONE;
  } else if (body_report_operand_mismatch(body, expr, left, right)) {
    ty = is_comparison(op) ? body_primitive(body, MS_BUILTIN_Bool) : MS_TY_NONE;
  } else if (op == MS_B_EQ || op == MS_B_NE) {
    ty = equality_type(body, expr, left, right);
  } else if (is_comparison(op)) {
    ty = body_primitive(body, MS_BUILTIN_Bool);
  } else {
    ty = arithmetic_type(body, expr, op, left, right);
    body_check_constant_arithmetic(body, expr, ty);
  }
  body_set_type(body, expr->id, ty);
  return ty;
}
