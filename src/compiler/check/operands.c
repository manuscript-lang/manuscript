/* compiler/check/operands.c: operands that cannot work whatever their values: a non-Bool under `not`, `and` or
 * `or`, and integer arithmetic over literals that always faults (division by zero, overflow). */
#include "compiler/check/body.h"

typedef __int128 Wide;

typedef struct Range {
  Wide low, high;
} Range;

static bool reporting(const Body *body) {
  return body->module < body->program->user_modules && !body->quiet;
}

/* Whether a type is known and is not Bool, so `not`/`and`/`or` cannot take it. */
static bool not_bool(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  return ty != MS_TY_NONE && !ms_ty_is_invalid(types, ty) && !ms_ty_is(types, ty, MS_BUILTIN_Bool) &&
         !ms_ty_is(types, ty, MS_BUILTIN_Never) && !ms_ty_has_variable(types, ty);
}

static void show(const Body *body, MsStrBuild *out, MsTy ty) {
  ms_ty_show(out, body->program->names, &body->program->types, ty);
}

static void report(Body *body, const MsExpr *expr, MsStrBuild *text) {
  ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(text));
}

void body_check_not(Body *body, const MsExpr *expr, MsTy operand) {
  if (!reporting(body) || !not_bool(body, operand)) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "not requires Bool, found ");
  show(body, &text, operand);
  ms_strbuild_append_text(&text, "; compare explicitly, e.g. not (x == 0)");
  report(body, expr, &text);
}

void body_check_logical(Body *body, const MsExpr *expr, MsTy left, MsTy right) {
  const MsTyTable *types = &body->program->types;
  const bool known = left != MS_TY_NONE && right != MS_TY_NONE && !ms_ty_is_invalid(types, left) &&
                     !ms_ty_is_invalid(types, right);
  if (!reporting(body) || !known || (!not_bool(body, left) && !not_bool(body, right))) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "logical operands require Bool, found ");
  show(body, &text, left);
  ms_strbuild_append_text(&text, " and ");
  show(body, &text, right);
  ms_strbuild_append_text(&text, "; compare explicitly, e.g. x != 0");
  report(body, expr, &text);
}

/* ---- constant arithmetic ---- */

static bool int_range(const Body *body, MsTy ty, Range *out) {
  const MsBuiltin builtin = ms_ty_builtin(&body->program->types, ty);
  unsigned bits = 64;
  switch (builtin) {
    case MS_BUILTIN_Int: case MS_BUILTIN_Int64: case MS_BUILTIN_UInt64: bits = 64; break;
    case MS_BUILTIN_Int8: case MS_BUILTIN_UInt8: bits = 8; break;
    case MS_BUILTIN_Int16: case MS_BUILTIN_UInt16: bits = 16; break;
    case MS_BUILTIN_Int32: case MS_BUILTIN_UInt32: bits = 32; break;
    default: return false;
  }
  const bool unsigned_type = builtin == MS_BUILTIN_UInt8 || builtin == MS_BUILTIN_UInt16 ||
                             builtin == MS_BUILTIN_UInt32 || builtin == MS_BUILTIN_UInt64;
  out->low = unsigned_type ? 0 : -((Wide)1 << (bits - 1));
  out->high = unsigned_type ? ((Wide)1 << bits) - 1 : ((Wide)1 << (bits - 1)) - 1;
  return true;
}

/* The value of an integer literal: decimal, `0x` or `0b`, with `_` separators. */
// Signed 128-bit multiply with overflow detection through the unsigned builtin, which expands inline;
// the signed builtin calls __muloti4, which glibc's libgcc does not provide.
static bool wide_mul(Wide a, Wide b, Wide *out) {
  const bool negative = (a < 0) != (b < 0);
  const unsigned __int128 ua = a < 0 ? -(unsigned __int128)a : (unsigned __int128)a;
  const unsigned __int128 ub = b < 0 ? -(unsigned __int128)b : (unsigned __int128)b;
  unsigned __int128 product;
  if (__builtin_mul_overflow(ua, ub, &product)) {
    return false;
  }
  const unsigned __int128 limit = (unsigned __int128)1 << 127;
  if (product > limit || (product == limit && !negative)) {
    return false;
  }
  *out = negative ? (Wide)(0 - product) : (Wide)product;
  return true;
}

static bool literal_value(MsSpan text, Wide *out) {
  unsigned base = 10;
  size_t at = 0;
  if (text.len > 2 && text.ptr[0] == '0' && (text.ptr[1] == 'x' || text.ptr[1] == 'b')) {
    base = text.ptr[1] == 'x' ? 16 : 2;
    at = 2;
  }
  Wide value = 0;
  for (; at < text.len; at++) {
    const char c = (char)text.ptr[at];
    const int digit = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
    if (c == '_') {
      continue;
    }
    if (digit < 0 || (unsigned)digit >= base || !wide_mul(value, (Wide)base, &value) ||
        __builtin_add_overflow(value, (Wide)digit, &value)) {
      return false;
    }
  }
  *out = value;
  return true;
}

static bool apply(MsBinaryOp op, Wide a, Wide b, Wide *out) {
  switch (op) {
    case MS_B_ADD: return !__builtin_add_overflow(a, b, out);
    case MS_B_SUB: return !__builtin_sub_overflow(a, b, out);
    case MS_B_MUL: return wide_mul(a, b, out);
    case MS_B_DIV: return b != 0 && (*out = a / b, true);
    case MS_B_REM: return b != 0 && (*out = a % b, true);
    default: return false;
  }
}

/* The value of an integer expression built from literals and `+ - * / %`, or false when an operand is not
 * constant, a division is by zero, or an intermediate leaves `range`. */
static bool fold(const Body *body, const MsExpr *expr, Range range, Wide *out) {
  Wide a = 0;
  Wide b = 0;
  if (expr->kind == MS_E_NUMBER) {
    return literal_value(ms_names_span(body->program->names, expr->u.sym), out) && *out >= range.low && *out <= range.high;
  }
  if (expr->kind == MS_E_UNARY && (expr->op == MS_U_NEG || expr->op == MS_U_PLUS)) {
    if (!fold(body, expr->u.bin.left, range, &a)) {
      return false;
    }
    *out = expr->op == MS_U_NEG ? -a : a;
    return *out >= range.low && *out <= range.high;
  }
  if (expr->kind != MS_E_BINARY || expr->op < MS_B_ADD || !fold(body, expr->u.bin.left, range, &a) ||
      !fold(body, expr->u.bin.right, range, &b)) {
    return false;
  }
  return apply((MsBinaryOp)expr->op, a, b, out) && *out >= range.low && *out <= range.high;
}

static void append_wide(MsStrBuild *out, Wide value) {
  char digits[48];
  size_t at = sizeof digits;
  const bool negative = value < 0;
  unsigned __int128 magnitude = negative ? -(unsigned __int128)value : (unsigned __int128)value;
  do {
    digits[--at] = (char)('0' + (int)(magnitude % 10));
    magnitude /= 10;
  } while (magnitude != 0);
  ms_strbuild_append_text(out, negative ? "-" : "");
  ms_strbuild_append(out, (MsSpan){(const uint8_t *)digits + at, sizeof digits - at});
}

static const char *op_text(MsBinaryOp op) {
  return op == MS_B_ADD ? "+" : op == MS_B_SUB ? "-" : op == MS_B_MUL ? "*" : op == MS_B_DIV ? "/" : "%";
}

/* An integer literal written where a sized integer type is expected must fit it: `out.append(256)` for a UInt8. */
void body_check_literal_range(Body *body, const MsExpr *number, bool negated, MsTy ty) {
  Range range = {0};
  Wide value = 0;
  const MsSpan text = ms_names_span(body->program->names, number->u.sym);
  if (!reporting(body) || ms_ty_is(&body->program->types, ty, MS_BUILTIN_Int) || !int_range(body, ty, &range) ||
      !literal_value(text, &value)) {
    return;
  }
  const Wide signed_value = negated ? -value : value;
  if (signed_value >= range.low && signed_value <= range.high) {
    return;
  }
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, negated ? "literal -" : "literal ");
  ms_strbuild_append(&out, text);
  ms_strbuild_append_text(&out, " is out of range for ");
  show(body, &out, ty);
  ms_strbuild_append_text(&out, "; use a value between ");
  append_wide(&out, range.low);
  ms_strbuild_append_text(&out, " and ");
  append_wide(&out, range.high);
  ms_check_report(body->program, body->module, number->pos, MS_CHECK_TYPE, ms_strbuild_finish(&out));
}

void body_check_constant_arithmetic(Body *body, const MsExpr *expr, MsTy ty) {
  Range range = {0};
  const MsBinaryOp op = (MsBinaryOp)expr->op;
  if (!reporting(body) || !int_range(body, ty, &range) || op < MS_B_ADD || op > MS_B_REM) {
    return;
  }
  Wide a = 0;
  Wide b = 0;
  Wide divisor = 1;
  if ((op == MS_B_DIV || op == MS_B_REM) && fold(body, expr->u.bin.right, range, &divisor) && divisor == 0) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "division by zero always faults; guard the divisor or use a nonzero constant");
    report(body, expr, &text);
    return;
  }
  Wide value = 0;
  if (!fold(body, expr->u.bin.left, range, &a) || !fold(body, expr->u.bin.right, range, &b) ||
      !apply(op, a, b, &value) || (value >= range.low && value <= range.high)) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  append_wide(&text, a);
  ms_strbuild_append_text(&text, " ");
  ms_strbuild_append_text(&text, op_text(op));
  ms_strbuild_append_text(&text, " ");
  append_wide(&text, b);
  ms_strbuild_append_text(&text, " overflows ");
  show(body, &text, ty);
  ms_strbuild_append_text(&text, " and always faults; use a smaller value or a wider type such as BigInt");
  report(body, expr, &text);
}
