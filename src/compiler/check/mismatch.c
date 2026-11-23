/* compiler/check/mismatch.c: checking a value against the type its position expects.
 *
 * body_expect types an expression and reports "expected X, found Y (in <context>)" when the type does not fit.
 * A type fits when it is the expected type, Never, an Optional's payload type, a concrete type that implements
 * an expected interface, or when either side is still open or invalid (an inference gap or an error already
 * reported). The message carries the oracle's hint and, where the oracle offers one, a repairing edit. */
#include "compiler/check/body.h"
#include "compiler/check/methods.h"
#include "compiler/syntax/walk.h"

/* Whether `ty` is, or holds, an invalid type. */
bool holds_invalid(const MsTyTable *types, MsTy ty, int depth) {
  if (ty == MS_TY_NONE || ms_ty_is_invalid(types, ty)) {
    return true;
  }
  if (depth == 0) {
    return false;
  }
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    if (holds_invalid(types, ms_ty_args(types, ty)[index], depth - 1)) {
      return true;
    }
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    if (holds_invalid(types, ms_ty_params(types, ty)[index].ty, depth - 1)) {
      return true;
    }
  }
  return ms_ty_kind(types, ty) == MS_TY_FUNCTION && holds_invalid(types, ms_ty_result(types, ty), depth - 1);
}

static bool has_generic_operation(const Body *body, MsTy contract) {
  const MsDef *def = body_def(body, contract);
  for (size_t index = 0; def != NULL && index < def->operations.len; index++) {
    if (def->operations.ptr[index].variables.len != 0) {
      return true;
    }
  }
  return false;
}

static bool interface_assignable(Body *body, MsTy actual, MsTy expected) {
  const MsTyTable *types = &body->program->types;
  return ms_ty_kind(types, expected) == MS_TY_CONTRACT && ms_ty_kind(types, actual) != MS_TY_CONTRACT &&
         !has_generic_operation(body, expected) && ms_check_implements(body->program, actual, expected);
}

/* Whether a value of type `actual` may stand where `expected` is required. */
static bool assignable(Body *body, MsTy actual, MsTy expected) {
  const MsTyTable *types = &body->program->types;
  if (actual == expected || ms_ty_is(types, actual, MS_BUILTIN_Never) || holds_invalid(types, actual, 6) ||
      holds_invalid(types, expected, 6)) {
    return true;
  }
  if (ms_ty_shape(&body->program->types, actual) == ms_ty_shape(&body->program->types, expected)) {
    return true;
  }
  /* An open type on either side is an unbound inference slot: the same nominal type fits. */
  const MsTyRow *left = ms_ty_row(types, actual);
  const MsTyRow *right = ms_ty_row(types, expected);
  if ((left->open || right->open) && left->id == right->id && left->arg_count == right->arg_count) {
    return true;
  }
  /* A value wraps once: a plain Int is not an Int??, though an Int? is. */
  if (ms_ty_is(types, expected, MS_BUILTIN_Optional) && ms_ty_arg_count(types, expected) == 1 &&
      (!ms_ty_is(types, ms_ty_args(types, expected)[0], MS_BUILTIN_Optional) || ms_ty_is(types, actual, MS_BUILTIN_Optional)) &&
      assignable(body, actual, ms_ty_args(types, expected)[0])) {
    return true;
  }
  return interface_assignable(body, actual, expected);
}

static void show(const Body *body, MsStrBuild *out, MsTy ty) {
  ms_ty_show(out, body->program->names, &body->program->types, ty);
}

static bool is_builtin(const Body *body, MsTy ty, MsBuiltin builtin) {
  return ms_ty_is(&body->program->types, ty, builtin);
}

static MsTy first_arg(const Body *body, MsTy ty) {
  return ms_ty_arg_count(&body->program->types, ty) != 0 ? ms_ty_args(&body->program->types, ty)[0] : MS_TY_NONE;
}

/* ---- hints ---- */

static bool optional_use_hint(const Body *body, MsStrBuild *out, MsTy actual, MsTy expected) {
  if (!is_builtin(body, actual, MS_BUILTIN_Optional) || ms_ty_arg_count(&body->program->types, actual) != 1 ||
      is_builtin(body, expected, MS_BUILTIN_Optional)) {
    return false;
  }
  show(body, out, actual);
  ms_strbuild_append_text(out, " may be absent; unwrap it first with 'if value := x', get_or(default), is_some() before get(), or match");
  return true;
}

static bool number_conversion_hint(const Body *body, MsStrBuild *out, MsTy actual, MsTy expected) {
  const bool to_float = is_builtin(body, actual, MS_BUILTIN_Int) && is_builtin(body, expected, MS_BUILTIN_Float);
  const bool to_int = is_builtin(body, actual, MS_BUILTIN_Float) && is_builtin(body, expected, MS_BUILTIN_Int);
  const bool to_text = (is_builtin(body, actual, MS_BUILTIN_Int) || is_builtin(body, actual, MS_BUILTIN_Float) ||
                        is_builtin(body, actual, MS_BUILTIN_Bool)) &&
                       is_builtin(body, expected, MS_BUILTIN_String);
  if (to_float) {
    ms_strbuild_append_text(out, "Int does not convert to Float implicitly; write a Float literal such as 3.0, or call to_float() on an Int value");
  } else if (to_int) {
    ms_strbuild_append_text(out, "Float does not convert to Int implicitly; truncate_to_int() returns Int?, so unwrap it, e.g. value.truncate_to_int().get(0)");
  } else if (to_text) {
    show(body, out, actual);
    ms_strbuild_append_text(out, " does not convert to String implicitly; interpolate it into text, e.g. f\"{value}\"");
  }
  return to_float || to_int || to_text;
}

static bool wrapping_hint(const Body *body, MsStrBuild *out, MsTy actual, MsTy expected) {
  if (is_builtin(body, actual, MS_BUILTIN_String) && is_builtin(body, expected, MS_BUILTIN_Error)) {
    ms_strbuild_append_text(out, "String does not convert to Error implicitly; make the error with Error(\"message\"), e.g. error(Error(\"message\"))");
    return true;
  }
  if (is_builtin(body, expected, MS_BUILTIN_Result) && ms_ty_arg_count(&body->program->types, expected) != 0 &&
      first_arg(body, expected) == actual) {
    ms_strbuild_append_text(out, "wrap the value in ok(...) to return it as a success, e.g. return ok(value); when another argument is a Result call, unwrap that call with ? instead, e.g. expect_equal(f()?, value)?");
    return true;
  }
  return false;
}

static bool promise_wait_fits(const Body *body, MsTy actual, MsTy expected) {
  return is_builtin(body, actual, MS_BUILTIN_Promise) && ms_ty_arg_count(&body->program->types, actual) == 1 &&
         is_builtin(body, expected, MS_BUILTIN_Result) && ms_ty_arg_count(&body->program->types, expected) == 2 &&
         first_arg(body, actual) == first_arg(body, expected);
}

static bool promise_use_hint(const Body *body, MsStrBuild *out, MsTy actual, MsTy expected) {
  if (promise_wait_fits(body, actual, expected)) {
    ms_strbuild_append_text(out, "a call that waits returns a Promise; call wait() on it to get the result");
    return true;
  }
  if (!is_builtin(body, actual, MS_BUILTIN_Promise) || ms_ty_arg_count(&body->program->types, actual) != 1 ||
      is_builtin(body, expected, MS_BUILTIN_Promise)) {
    return false;
  }
  ms_strbuild_append_text(out, "a call that waits returns a Promise; wait() gives its result, ");
  show(body, out, first_arg(body, actual));
  ms_strbuild_append_text(out, "!, so call wait() and unwrap it with a trailing '?' or '.get()' before using it as ");
  show(body, out, expected);
  return true;
}

static bool uncalled_function(const Body *body, MsTy actual, MsTy expected) {
  const MsTyTable *types = &body->program->types;
  return ms_ty_kind(types, actual) == MS_TY_FUNCTION && ms_ty_kind(types, expected) != MS_TY_FUNCTION &&
         ms_ty_param_count(types, actual) == 0 && ms_ty_result(types, actual) == expected;
}

static bool uncalled_function_hint(const Body *body, MsStrBuild *out, MsTy actual, MsTy expected) {
  if (!uncalled_function(body, actual, expected)) {
    return false;
  }
  ms_strbuild_append_text(out, "this is a method, not a property; call it with parentheses to get its ");
  show(body, out, expected);
  ms_strbuild_append_text(out, " result, as in `xs.length()`");
  return true;
}

/* The hint for an expected interface that the value does not satisfy. */
static void interface_hint(Body *body, MsStrBuild *out, MsTy actual, MsTy expected) {
  const MsTyTable *types = &body->program->types;
  ms_strbuild_append_text(out, "; ");
  if (has_generic_operation(body, expected)) {
    show(body, out, expected);
    ms_strbuild_append_text(out, " declares an operation with type parameters of its own, so it bounds a type parameter (`fn f[T: ");
    show(body, out, expected);
    ms_strbuild_append_text(out, "](x: T)`) but cannot type a value");
    return;
  }
  const MsDef *def = body_def(body, actual);
  const bool source = def != NULL && def->symbol != 0 && body->program->symbols.ptr[def->symbol].native == MS_NATIVE_SOURCE &&
                      (ms_ty_kind(types, actual) == MS_TY_TYPE || ms_ty_kind(types, actual) == MS_TY_ALTERNATIVE);
  if (source && !ms_check_implements(body->program, actual, expected)) {
    MsStrBuild gap = ms_strbuild_new();
    (void)ms_check_shape_gap(body->program, actual, expected, &gap);
    show(body, out, actual);
    ms_strbuild_append_text(out, " does not satisfy ");
    show(body, out, expected);
    ms_strbuild_append_text(out, " by its own methods (");
    ms_strbuild_append(out, ms_strbuild_span(&gap));
    ms_strbuild_append_text(out, "); declare each operation as a method of ");
    show(body, out, actual);
    ms_strbuild_append_text(out, " with the interface's exact signature");
    ms_strbuild_free(&gap);
    return;
  }
  ms_strbuild_append_text(out, "use a concrete value implementing ");
  show(body, out, expected);
}

/* The text after the head of the message: the first hint that applies. */
static void append_hints(Body *body, MsStrBuild *out, MsTy actual, MsTy expected) {
  const MsTyTable *types = &body->program->types;
  MsStrBuild hint = ms_strbuild_new();
  if (is_builtin(body, actual, MS_BUILTIN_Result) && first_arg(body, actual) == expected) {
    ms_strbuild_append_text(out, "; unwrap it with a trailing '?' inside a function that returns a compatible Result, with 'if value := x', or with '.get()'");
  }
  const bool found = optional_use_hint(body, &hint, actual, expected) || number_conversion_hint(body, &hint, actual, expected) ||
                     wrapping_hint(body, &hint, actual, expected) || promise_use_hint(body, &hint, actual, expected) ||
                     uncalled_function_hint(body, &hint, actual, expected);
  if (found) {
    ms_strbuild_append_text(out, "; ");
    ms_strbuild_append(out, ms_strbuild_span(&hint));
  } else if (ms_ty_kind(types, expected) == MS_TY_CONTRACT && !ms_ty_is_invalid(types, actual)) {
    interface_hint(body, out, actual, expected);
  }
  ms_strbuild_free(&hint);
}

/* ---- fixes ---- */

/* A written expression a `.method()` suffix or a `()` call binds to as a whole. */
bool body_expr_is_atomic(const MsExpr *expr) {
  return expr->kind == MS_E_NAME || expr->kind == MS_E_MEMBER || expr->kind == MS_E_CALL ||
         expr->kind == MS_E_INDEX || expr->kind == MS_E_APPLY || expr->kind == MS_E_LIST || expr->kind == MS_E_MAP;
}

static bool all_digits(MsSpan text) {
  for (size_t index = 0; index < text.len; index++) {
    if (text.ptr[index] < '0' || text.ptr[index] > '9') {
      return false;
    }
  }
  return text.len != 0;
}

/* Replaces the written expression with `prefix text suffix`, parenthesised when the suffix is a method call. */
static bool rewrite(Body *body, const MsExpr *expr, const char *prefix, const char *suffix, bool method) {
  const MsPos start = ms_expr_start(expr);
  MsSpan text = {0};
  if (expr->end.offset <= start.offset || !ms_span_slice(body->source, start.offset, expr->end.offset, &text)) {
    return false;
  }
  MsStrBuild out = ms_strbuild_new();
  const bool parens = method && !body_expr_is_atomic(expr);
  ms_strbuild_append_text(&out, prefix);
  ms_strbuild_append_text(&out, parens ? "(" : "");
  ms_strbuild_append(&out, text);
  ms_strbuild_append_text(&out, parens ? ")" : "");
  ms_strbuild_append_text(&out, suffix);
  ms_check_attach_fix(body->program, start, expr->end, ms_strbuild_finish(&out));
  return true;
}

static bool interpolation_fix(Body *body, const MsExpr *expr) {
  const MsPos start = ms_expr_start(expr);
  MsSpan text = {0};
  if (expr->end.offset <= start.offset || !ms_span_slice(body->source, start.offset, expr->end.offset, &text)) {
    return false;
  }
  if (expr->kind == MS_E_NUMBER && all_digits(text)) {
    return rewrite(body, expr, "\"", "\"", false);
  }
  for (size_t index = 0; index < text.len; index++) {
    const uint8_t byte = text.ptr[index];
    if (byte == '"' || byte == '{' || byte == '}' || byte == '\n') {
      return false;
    }
  }
  return rewrite(body, expr, "f\"{", "}\"", false);
}

static void attach_fix(Body *body, const MsExpr *expr, MsTy actual, MsTy expected) {
  if (promise_wait_fits(body, actual, expected)) {
    (void)rewrite(body, expr, "", ".wait()", true);
  } else if (uncalled_function(body, actual, expected)) {
    if (body_expr_is_atomic(expr)) {
      (void)rewrite(body, expr, "", "()", false);
    }
  } else if (is_builtin(body, actual, MS_BUILTIN_Int) && is_builtin(body, expected, MS_BUILTIN_Float)) {
    MsSpan text = {0};
    const MsPos start = ms_expr_start(expr);
    const bool plain = expr->kind == MS_E_NUMBER && ms_span_slice(body->source, start.offset, expr->end.offset, &text) &&
                       all_digits(text);
    (void)(plain ? rewrite(body, expr, "", ".0", false) : rewrite(body, expr, "", ".to_float()", true));
  } else if ((is_builtin(body, actual, MS_BUILTIN_Int) || is_builtin(body, actual, MS_BUILTIN_Float) ||
              is_builtin(body, actual, MS_BUILTIN_Bool)) &&
             is_builtin(body, expected, MS_BUILTIN_String)) {
    (void)interpolation_fix(body, expr);
  } else if (is_builtin(body, actual, MS_BUILTIN_String) && is_builtin(body, expected, MS_BUILTIN_Error)) {
    (void)rewrite(body, expr, "Error(", ")", false);
  }
}

/* ---- reporting ---- */

/* Whether `actual` is the type of a bare `none`: an Optional of its own unbound payload. */
static bool is_none(const Body *body, MsTy actual) {
  const MsTyTable *types = &body->program->types;
  return ms_ty_is(types, actual, MS_BUILTIN_Optional) && ms_ty_arg_count(types, actual) == 1 &&
         ms_ty_kind(types, ms_ty_args(types, actual)[0]) == MS_TY_VARIABLE &&
         ms_ty_row(types, actual)->open;
}

bool body_is_none_type(const Body *body, MsTy ty) {
  return is_none(body, ty);
}

void body_report_uninferred_none(Body *body, MsPos pos) {
  if (body->quiet || body->module >= body->program->user_modules) {
    return;
  }
  ms_check_report(body->program, body->module, pos, MS_CHECK_TYPE,
                  ms_string_from_span(ms_span_of_text("cannot infer the type of none; give it a target, e.g. `x: Int? := "
                                                      "none`, or pass a value")));
}

static void report_mismatch(Body *body, const MsExpr *expr, MsTy actual, MsTy expected, MsSpan context) {
  if (is_none(body, actual) && ms_ty_kind(&body->program->types, expected) == MS_TY_CONTRACT) {
    body_report_uninferred_none(body, expr->pos); /* an interface is no target for none */
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "expected ");
  show(body, &text, expected);
  if (is_none(body, actual)) {
    ms_strbuild_append_text(&text, ", found none");
  } else {
    ms_strbuild_append_text(&text, ", found ");
    show(body, &text, actual);
  }
  if (context.len != 0) {
    ms_strbuild_append_text(&text, " (in ");
    ms_strbuild_append(&text, context);
    ms_strbuild_append_text(&text, ")");
  }
  if (is_none(body, actual)) {
    ms_strbuild_append_text(&text, "; none is absent, so it fits only an Optional position: declare the target ");
    show(body, &text, expected);
    ms_strbuild_append_text(&text, "? or give a value");
  } else {
    append_hints(body, &text, actual, expected);
  }
  ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  if (!is_none(body, actual)) {
    attach_fix(body, expr, actual, expected);
  }
}

void body_check_assignable(Body *body, const MsExpr *expr, MsTy actual, MsTy expected, MsSpan context) {
  if (body->quiet || body->module >= body->program->user_modules || expected == MS_TY_NONE || actual == MS_TY_NONE ||
      assignable(body, actual, expected)) {
    return;
  }
  report_mismatch(body, expr, actual, expected, context);
}

MsTy body_expect(Body *body, const MsExpr *expr, MsTy expected, MsSpan context) {
  const MsTy actual = body_expr(body, expr, expected);
  if (expr->kind != MS_E_LAMBDA) {
    body_check_assignable(body, expr, actual, expected, context);
  }
  return actual;
}
