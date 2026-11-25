/* compiler/check/conversions.c: the implicit conversions the checker applies where an expression meets the type
 * it is expected to have, recorded as conversion facts for lowering: a value seen as an interface it implements,
 * a plain value wrapped as an optional, and a function used where one with other parameter modes is expected.
 * Reporting a mismatch is left to the diagnostics that run after this call. */
#include "compiler/check/body.h"

static bool is_optional(const MsTyTable *types, MsTy ty) {
  return ms_ty_is(types, ty, MS_BUILTIN_Optional) && ms_ty_arg_count(types, ty) == 1;
}

static bool has_generic_operation(const MsCheckProgram *program, MsTy contract) {
  const MsDef *def = ms_defs_get(&program->defs, ms_ty_row(&program->types, contract)->def);
  for (size_t index = 0; index < def->operations.len; index++) {
    if (def->operations.ptr[index].variables.len > 0) {
      return true;
    }
  }
  return false;
}

/* A value of `actual` where the interface `expected` is wanted. */
static bool interface_assignable(MsCheckProgram *program, MsTy actual, MsTy expected) {
  const MsTyTable *types = &program->types;
  return ms_ty_kind(types, expected) == MS_TY_CONTRACT && ms_ty_kind(types, actual) != MS_TY_CONTRACT &&
         !has_generic_operation(program, expected) && ms_check_implements(program, actual, expected);
}

/* Whether `actual` is `expected` except that it reads parameters `expected` may change or take: a plain
 * parameter stands where a `var` or `move` one is expected, never the other way round. */
bool body_reads_where_var_expected(const MsTyTable *types, MsTy actual, MsTy expected) {
  if (ms_ty_kind(types, actual) != MS_TY_FUNCTION || ms_ty_kind(types, expected) != MS_TY_FUNCTION ||
      ms_ty_param_count(types, actual) != ms_ty_param_count(types, expected) ||
      ms_ty_result(types, actual) != ms_ty_result(types, expected)) {
    return false;
  }
  const MsTyParam *a = ms_ty_params(types, actual);
  const MsTyParam *e = ms_ty_params(types, expected);
  const uint8_t modes = MS_PARAM_VAR | MS_PARAM_MOVE;
  bool differs = false;
  for (size_t index = 0; index < ms_ty_param_count(types, actual); index++) {
    const bool borrows = (a[index].flags & modes) == (e[index].flags & modes) || (a[index].flags & modes) == 0;
    if (a[index].ty != e[index].ty || !borrows) {
      return false;
    }
    differs = differs || (a[index].flags & modes) != (e[index].flags & modes);
  }
  return differs;
}

static void record(Body *body, const MsExpr *expr, MsConversionKind kind, MsTy from, MsTy to) {
  const MsConversion conversion = {expr->id, kind, from, to};
  ms_facts_add_conversion(body->facts, &conversion);
}

void body_convert(Body *body, const MsExpr *expr, MsTy actual, MsTy expected) {
  const MsTyTable *types = &body->program->types;
  if (actual == MS_TY_NONE || expected == MS_TY_NONE || actual == expected || ms_ty_is_invalid(types, actual) ||
      ms_ty_is_invalid(types, expected) || ms_ty_is(types, actual, MS_BUILTIN_Never)) {
    return;
  }
  if (is_optional(types, expected)) {
    const MsTy payload = ms_ty_args(types, expected)[0];
    if (payload == actual || interface_assignable(body->program, actual, payload)) { /* an implementor wraps as its interface first */
      record(body, expr, MS_CONV_OPTIONAL_WRAP, actual, expected);
    }
    return;
  }
  if (interface_assignable(body->program, actual, expected)) {
    record(body, expr, MS_CONV_INTERFACE_VIEW, actual, expected);
  } else if (ms_ty_kind(types, actual) == MS_TY_FUNCTION && ms_ty_kind(types, expected) == MS_TY_FUNCTION &&
             ms_ty_shape(&body->program->types, actual) == ms_ty_shape(&body->program->types, expected)) {
    /* The same function type, but one side lets a call leave parameters out: a function value crosses them as optionals. */
    record(body, expr, MS_CONV_FUNCTION_VALUE, actual, expected);
  } else if (body_reads_where_var_expected(types, actual, expected)) {
    record(body, expr, MS_CONV_FUNCTION_VALUE, actual, expected);
  }
}
