/* compiler/check/exprs_ops.c: types of literals, text and the unary and binary operators. This file computes result types,
 * records the operand conversions the lowering needs, and reports an operand whose type has no such operator. */
#include "compiler/check/body.h"
#include "compiler/check/call_internal.h"
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
  if (body->quiet || !body_reports(body)) {
    return;
  }
  for (size_t index = 0; index < program->diagnostics.len; index++) {
    const MsCheckDiag *diag = &program->diagnostics.ptr[index];
    const MsSpan message = ms_string_span(&diag->message);
    if (diag->module == body->module && (ms_span_starts_with_text(message, "Decimal literal requires") ||
                                         ms_span_starts_with_text(message, "unknown type Decimal") ||
                                         ms_span_starts_with_text(message, "unknown binding Decimal"))) {
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
    body_check_float_literal(body, expr, is_sized_float(body, expected) ? expected : MS_TY_NONE);
    return is_sized_float(body, expected) || numeric_variable(body, expected, false) ? expected
                                                                                   : body_primitive(body, MS_BUILTIN_Float);
  }
  if (is_sized_int(body, expected)) {
    body_check_literal_range(body, expr, negated, expected);
    return expected;
  }
  if (!numeric_variable(body, expected, true)) {
    body_check_int64_literal(body, expr, negated);
    return body_primitive(body, MS_BUILTIN_Int);
  }
  return expected;
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
    const MsTyTable *types = &body->program->types;
    const MsTy wrapped = expected != MS_TY_NONE && ms_ty_is(types, expected, MS_BUILTIN_Optional) && ms_ty_arg_count(types, expected) == 1
                             ? ms_ty_args(types, expected)[0]
                             : expected; /* a literal takes the sized type an optional wraps */
    const MsTy hint = signed_op ? literal_hint(body, operand, wrapped) : MS_TY_NONE;
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
          body_reports(body) && !body->quiet) {
        MsStrBuild text = ms_strbuild_new();
        ms_strbuild_append_text(&text, "unary - is not defined for ");
        ms_ty_show(&text, body->program->names, &body->program->types, value);
        ms_strbuild_append_text(&text, "; subtract from zero with a wider signed type, e.g. 0 - x.to_int()");
        ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      }
    } else if (!is_invalid(body, value) && !ms_ty_is(types, value, MS_BUILTIN_Never) && body_reports(body) && !body->quiet) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, op == MS_U_NEG ? "unary - requires a numeric operand, found " : "unary + requires a numeric operand, found ");
      ms_ty_show(&text, body->program->names, types, value);
      ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
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

static bool is_nullable(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  return ty != MS_TY_NONE && ms_ty_is(types, ty, MS_BUILTIN_Optional) && ms_ty_arg_count(types, ty) == 1;
}

/* Types the two operands. Literals beside a sized number take its type; arithmetic over literals alone takes the
 * expected sized type. */
static void operand_types(Body *body, const MsExpr *expr, MsTy expected, MsTy *left, MsTy *right) {
  const MsBinaryOp op = (MsBinaryOp)expr->op;
  const MsExpr *l = expr->u.bin.left;
  const MsExpr *r = expr->u.bin.right;
  const bool arithmetic = op >= MS_B_ADD;
  if (expected != MS_TY_NONE && ms_ty_is(&body->program->types, expected, MS_BUILTIN_Optional) &&
      ms_ty_arg_count(&body->program->types, expected) == 1) {
    expected = ms_ty_args(&body->program->types, expected)[0]; /* literals take the sized type an optional wraps */
  }
  const MsTy hint = arithmetic ? literal_hint(body, l, expected) : MS_TY_NONE;
  if (hint != MS_TY_NONE && literal_hint(body, r, expected) != MS_TY_NONE) {
    *left = body_expr(body, l, hint);
    *right = body_expr(body, r, hint);
  } else if (literal_tree(body, l) != 0 && l->kind != MS_E_NUMBER && literal_tree(body, r) == 0) {
    *right = body_expr(body, r, MS_TY_NONE); /* arithmetic over literals beside a typed operand takes its type */
    *left = body_expr(body, l, literal_hint(body, l, *right));
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
    if (op == MS_B_OR && is_nullable(body, *left)) {
      *right = body_expr(body, r, body_is_none_name(body, r) ? *left : ms_ty_args(&body->program->types, *left)[0]);
      return;
    }
    const size_t narrow = body_narrow_mark(body);
    if (op == MS_B_AND || op == MS_B_OR) {
      body_narrow(body, l, op == MS_B_AND); /* `v != null and ...` reads v as present; `v == null or ...` too */
    }
    *right = body_expr(body, r, wraps || shaped ? *left : literal_hint(body, r, *left));
    body_narrow_reset(body, narrow);
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
  const MsTy common = right_optional && !left_optional ? right : left;
  if (common != MS_TY_NONE && !is_invalid(body, common) && body_reports(body) && !body->quiet &&
      !ms_check_property(body->program, common, MS_PROPERTY_EQUAL)) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "equality requires Equal operands; ");
    ms_ty_show(&text, body->program->names, types, common);
    ms_strbuild_append_text(&text, " has no equality, so give it 'fn ");
    ms_ty_show(&text, body->program->names, types, common);
    ms_strbuild_append_text(&text, ".equals(other: ");
    ms_ty_show(&text, body->program->names, types, common);
    ms_strbuild_append_text(&text, ") Bool' or compare fields");
    ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  return body_primitive(body, MS_BUILTIN_Bool);
}

/* `<`, `<=`, `>` and `>=` over two operands of one type: the type must be Comparable (numbers, String, Duration,
 * Instant, a type with its own `compare`, or a variable bounded by Comparable or by a set of numbers). */
static MsTy ordering_type(Body *body, const MsExpr *expr, MsTy operand) {
  MsCheckProgram *program = body->program;
  const MsSymbolId symbol = resolver_prelude_symbol(program, ms_names_intern(program->names, ms_span_of_text("Comparable")));
  const MsTy comparable = symbol != 0 ? program->symbols.ptr[symbol].ty : MS_TY_NONE;
  if (operand != MS_TY_NONE && !is_invalid(body, operand) && comparable != MS_TY_NONE &&
      !ms_ty_is(&program->types, operand, MS_BUILTIN_Never) && !is_numeric(body, operand) &&
      !ms_check_implements(program, operand, comparable) && body_reports(body) && !body->quiet) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "ordering requires Comparable operands; ");
    ms_ty_show(&text, program->names, &program->types, operand);
    const MsTyKind kind = ms_ty_kind(&program->types, operand);
    const bool own = (kind == MS_TY_TYPE || kind == MS_TY_ALTERNATIVE) && ms_ty_builtin(&program->types, operand) == MS_BUILTIN_NONE;
    if (kind == MS_TY_VARIABLE) {
      ms_strbuild_append_text(&text, " has no order; bound it where it is declared, as in `[");
      ms_ty_show(&text, program->names, &program->types, operand);
      ms_strbuild_append_text(&text, " Comparable]`");
    } else if (own) {
      ms_strbuild_append_text(&text, " has no order; compare a field that has one, or give it 'fn ");
      ms_ty_show(&text, program->names, &program->types, operand);
      ms_strbuild_append_text(&text, ".compare(other ");
      ms_ty_show(&text, program->names, &program->types, operand);
      ms_strbuild_append_text(&text, ") Int'");
    } else {
      ms_strbuild_append_text(&text, " has no order; compare values that have one, such as numbers or text");
    }
    ms_check_report(program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  return body_primitive(body, MS_BUILTIN_Bool);
}

/* `x or d` over a nullable `x`: `d` is evaluated only when `x` is null. The result is the payload when `d` is a plain
 * value and a nullable when `d` is one. */
static MsTy nullable_or_type(Body *body, const MsExpr *expr, MsTy left, MsTy right) {
  const MsTy payload = ms_ty_args(&body->program->types, left)[0];
  if (right == payload || right == left) {
    return right;
  }
  if (right != MS_TY_NONE && ms_ty_is(&body->program->types, right, MS_BUILTIN_Never)) {
    return payload; /* `x or panic(..)`, `x or fail()`: the right side never gives a value */
  }
  if (right != MS_TY_NONE && !is_invalid(body, right) && body_reports(body) && !body->quiet) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "`or` on ");
    ms_ty_show(&text, body->program->names, &body->program->types, left);
    ms_strbuild_append_text(&text, " needs ");
    ms_ty_show(&text, body->program->names, &body->program->types, payload);
    ms_strbuild_append_text(&text, " or ");
    ms_ty_show(&text, body->program->names, &body->program->types, left);
    ms_strbuild_append_text(&text, " on the right, found ");
    ms_ty_show(&text, body->program->names, &body->program->types, right);
    ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  return payload;
}

static MsTy arithmetic_type(Body *body, const MsExpr *expr, MsBinaryOp op, MsTy left, MsTy right) {
  const bool text = ms_ty_is(&body->program->types, left, MS_BUILTIN_String);
  const bool span = ms_ty_is(&body->program->types, left, MS_BUILTIN_Duration) && (op == MS_B_ADD || op == MS_B_SUB);
  if (left != right || !(is_numeric(body, left) || (text && op == MS_B_ADD) || span)) {
    if (!holds_invalid(&body->program->types, left, 6) && !holds_invalid(&body->program->types, right, 6) &&
        body_reports(body) && !body->quiet) {
      ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE,
                      ms_string_from_span(ms_span_of_text("arithmetic requires numeric operands")));
    }
    return left == right ? left : MS_TY_NONE;
  }
  const MsBuiltin builtin = ms_ty_builtin(&body->program->types, left);
  if (op == MS_B_REM && (ms_builtin_is_float(builtin) || builtin == MS_BUILTIN_Decimal) && body_reports(body) &&
      !body->quiet) {
    MsStrBuild message = ms_strbuild_new();
    ms_strbuild_append_text(&message, "remainder requires integer operands, found ");
    ms_ty_show(&message, body->program->names, &body->program->types, left);
    ms_strbuild_append_text(&message, "; convert to Int or use math functions");
    ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&message));
  }
  return left;
}

/* `x == null` and `x != null`: the `null` side takes the nullable type of the other, and the comparison is Bool. Any
 * other operand is reported unless it is itself wrong. */
static MsTy none_comparison(Body *body, const MsExpr *expr) {
  const bool null_left = body_is_none_name(body, expr->u.bin.left);
  const MsExpr *other = null_left ? expr->u.bin.right : expr->u.bin.left;
  const MsExpr *nothing = null_left ? expr->u.bin.left : expr->u.bin.right;
  /* a narrowed local is read as the nullable it is stored as: the test is about presence, not the payload */
  const MsLocal *found = other->kind == MS_E_NAME ? body_find_local(body, other->u.sym) : NULL;
  MsLocal *narrowed = found != NULL ? &body->locals.ptr[found - body->locals.ptr] : NULL;
  const MsTy held = narrowed != NULL ? narrowed->narrowed : MS_TY_NONE;
  if (narrowed != NULL) {
    narrowed->narrowed = MS_TY_NONE;
  }
  const MsTy ty = body_expr(body, other, MS_TY_NONE);
  if (narrowed != NULL) {
    narrowed->narrowed = held;
  }
  if (is_nullable(body, ty)) {
    body_expr(body, nothing, ty);
    return body_primitive(body, MS_BUILTIN_Bool);
  }
  if (ty != MS_TY_NONE && !is_invalid(body, ty) && body_reports(body) && !body->quiet) {
    ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE,
                    ms_string_from_span(ms_span_of_text(
                        "null has no type of its own here; compare a nullable with `x == null`, or compare plain "
                        "values with each other, e.g. x == 3")));
  }
  return body_primitive(body, MS_BUILTIN_Bool);
}

MsTy body_binary(Body *body, const MsExpr *expr, MsTy expected) {
  const MsBinaryOp op = (MsBinaryOp)expr->op;
  if ((op == MS_B_EQ || op == MS_B_NE) && (body_is_none_name(body, expr->u.bin.left) || body_is_none_name(body, expr->u.bin.right))) {
    const MsTy ty = none_comparison(body, expr);
    body_set_type(body, expr->id, ty);
    return ty;
  }
  MsTy left = MS_TY_NONE;
  MsTy right = MS_TY_NONE;
  operand_types(body, expr, expected, &left, &right);
  MsTy ty = MS_TY_NONE;
  if (op == MS_B_OR && is_nullable(body, left)) {
    ty = nullable_or_type(body, expr, left, right);
  } else if (op == MS_B_OR && !is_invalid(body, left) && left != MS_TY_NONE && left == right &&
             !ms_ty_is(&body->program->types, left, MS_BUILTIN_Bool) && body_redundant_or(body, expr)) {
    ty = left;
  } else if (op == MS_B_OR && (is_invalid(body, left) || left == MS_TY_NONE) && right != MS_TY_NONE &&
             ms_ty_is(&body->program->types, right, MS_BUILTIN_Never)) {
    ty = MS_TY_NONE; /* `bad or panic(..)`: the left side already failed, and the right never gives a value */
  } else if (is_logical(op)) {
    body_check_logical(body, expr, left, right);
    ty = body_primitive(body, MS_BUILTIN_Bool);
  } else if (is_invalid(body, left) || is_invalid(body, right)) {
    ty = is_comparison(op) ? body_primitive(body, MS_BUILTIN_Bool) : MS_TY_NONE;
  } else if (body_report_operand_mismatch(body, expr, left, right)) {
    ty = is_comparison(op) ? body_primitive(body, MS_BUILTIN_Bool) : MS_TY_NONE;
  } else if (op == MS_B_EQ || op == MS_B_NE) {
    ty = equality_type(body, expr, left, right);
  } else if (is_comparison(op)) {
    ty = ordering_type(body, expr, ms_ty_is(&body->program->types, left, MS_BUILTIN_Never) ? right : left);
  } else {
    ty = arithmetic_type(body, expr, op, left, right);
    body_check_constant_arithmetic(body, expr, ty);
  }
  body_set_type(body, expr->id, ty);
  return ty;
}
