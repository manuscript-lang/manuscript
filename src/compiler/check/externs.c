/* compiler/check/externs.c: the signature of a user `extern fn`, which crosses the native ABI.
 *
 * Parameters and results are sized numbers, Bool, String, Bytes, `extern type`s the program declares and Lists of
 * them; a parameter may also be a function of those, and a result a Result whose error is a code/message
 * alternative. */
#include "compiler/check/body.h"

static const char *const CROSSES = "sized numbers, Bool, String, Bytes, extern types this program declares, and Lists of them";
static const size_t MAX_CALLBACK_PARAMS = 6;

/* An `extern type` declared outside the standard library. */
static bool user_extern(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  const MsDef *def = body_def(body, ty);
  return ms_ty_kind(types, ty) == MS_TY_NATIVE && ms_ty_arg_count(types, ty) == 0 && def != NULL &&
         body->program->symbols.ptr[def->symbol].module < body->program->user_modules;
}

static bool crosses_element(const Body *body, MsTy ty) {
  static const char *const SCALARS[] = {"Int",    "Int8",   "Int16",  "Int32",   "Int64", "UInt8", "UInt16",
                                        "UInt32", "UInt64", "Float",  "Float32", "Bool",  "String"};
  const MsTyTable *types = &body->program->types;
  if (ms_ty_is(types, ty, MS_BUILTIN_Bytes) || user_extern(body, ty)) {
    return true;
  }
  const MsSpan name = ms_names_span(body->program->names, ms_ty_row(types, ty)->id);
  for (size_t index = 0; index < MS_COUNT_OF(SCALARS); index++) {
    if (ms_span_is_text(name, SCALARS[index])) {
      return true;
    }
  }
  return false;
}

static bool crosses_native(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  if (ms_ty_is(types, ty, MS_BUILTIN_List) && ms_ty_arg_count(types, ty) == 1) {
    return crosses_element(body, ms_ty_args(types, ty)[0]);
  }
  return crosses_element(body, ty);
}

static bool crosses_callback(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  const MsTy result = ms_ty_row(types, ty)->result;
  const bool result_ok = result == MS_TY_NONE || ms_ty_is(types, result, MS_BUILTIN_Void) ||
                         (crosses_element(body, result) && !user_extern(body, result));
  if (ms_ty_param_count(types, ty) > MAX_CALLBACK_PARAMS || !result_ok) {
    return false;
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    if (!crosses_element(body, ms_ty_params(types, ty)[index].ty)) {
      return false;
    }
  }
  return true;
}

static void report(Body *body, MsPos pos, MsStrBuild text) {
  ms_check_report(body->program, body->module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void type_name(Body *body, MsStrBuild *out, MsTy ty) {
  ms_strbuild_append(out, ms_names_span(body->program->names, ms_ty_row(&body->program->types, ty)->name));
}

/* Whether every case of the error alternative carries nothing, `code: Int`, `message: String`, or both. */
static bool reportable_error(Body *body, MsTy error) {
  const MsTyTable *types = &body->program->types;
  const MsDef *def = body_def(body, error);
  if (def == NULL || ms_ty_kind(types, error) != MS_TY_ALTERNATIVE || def->cases.len == 0) {
    return false;
  }
  for (size_t index = 0; index < def->cases.len; index++) {
    const MsTyParamList *fields = &def->cases.ptr[index].fields;
    for (size_t at = 0; at < fields->len; at++) {
      const MsSpan name = ms_names_span(body->program->names, fields->ptr[at].name);
      const bool code = ms_span_is_text(name, "code") && ms_ty_is(types, fields->ptr[at].ty, MS_BUILTIN_Int);
      const bool message = ms_span_is_text(name, "message") && ms_ty_is(types, fields->ptr[at].ty, MS_BUILTIN_String);
      if (!code && !message) {
        return false;
      }
    }
  }
  return true;
}

static void check_result(Body *body, const MsFunc *func, MsTy result) {
  const MsTyTable *types = &body->program->types;
  const MsPos pos = func->result->pos;
  if (ms_ty_is(types, result, MS_BUILTIN_Result) && ms_ty_arg_count(types, result) == 2) {
    const MsTy ok = ms_ty_args(types, result)[0];
    const MsTy error = ms_ty_args(types, result)[1];
    MsStrBuild text = ms_strbuild_new();
    if (!ms_ty_is(types, ok, MS_BUILTIN_Void) && !crosses_native(body, ok)) {
      ms_strbuild_append_text(&text, "extern Result value has type ");
      type_name(body, &text, ok);
      ms_strbuild_printf(&text, ", which cannot cross the native boundary; an extern Result holds %s, or Void", CROSSES);
      report(body, pos, text);
    } else if (!reportable_error(body, error)) {
      ms_strbuild_append_text(&text, "extern error type ");
      type_name(body, &text, error);
      ms_strbuild_append_text(&text, " must be an alternative whose cases carry nothing, `code Int`, `message String`, or "
                                     "both; the native returns the status 1 + the case index and fills code_out and "
                                     "message_out");
      report(body, pos, text);
    } else {
      ms_strbuild_free(&text);
    }
  } else if (!ms_ty_is(types, result, MS_BUILTIN_Void) && !crosses_native(body, result)) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "extern result has type ");
    type_name(body, &text, result);
    ms_strbuild_printf(&text, ", which cannot cross the native boundary; an extern returns %s, Void, or a Result of one",
                       CROSSES);
    report(body, pos, text);
  }
}

void body_check_extern(Body *body, const MsDecl *decl, MsTy fn_ty) {
  const MsFunc *func = &decl->u.fn;
  const MsTyTable *types = &body->program->types;
  if (body->module >= body->program->user_modules || body->quiet) {
    return;
  }
  const MsSpan name = ms_names_span(body->program->names, func->name);
  if (ms_span_starts_with(name, ms_span_of_text("msrt_")) || ms_span_starts_with(name, ms_span_of_text("msstd_"))) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "extern fn ");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, " names a runtime-internal symbol; msrt_ and msstd_ natives are reserved for bundled "
                                   "standard modules, so call the standard library instead");
    report(body, decl->pos, text);
  }
  if (func->type_params.len != 0) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "an extern fn cannot be generic; declare the concrete types the native symbol takes");
    report(body, decl->pos, text);
  }
  const size_t count = ms_ty_param_count(types, fn_ty);
  for (uint32_t index = 0; index < func->params.len && index < count; index++) {
    const MsParam *param = func->params.ptr[index];
    const MsTy ty = ms_ty_params(types, fn_ty)[index].ty;
    MsStrBuild text = ms_strbuild_new();
    const MsSpan param_name = ms_names_span(body->program->names, param->name);
    if (param->is_mutable) {
      ms_strbuild_append_text(&text, "extern parameter ");
      ms_strbuild_append(&text, param_name);
      ms_strbuild_append_text(&text, " cannot be var; a native borrows its arguments");
      report(body, param->pos, text);
    } else if (param->def != NULL) {
      ms_strbuild_append_text(&text, "extern parameter ");
      ms_strbuild_append(&text, param_name);
      ms_strbuild_append_text(&text, " cannot have a default; the native symbol takes every argument");
      report(body, param->pos, text);
    } else if (ty != MS_TY_NONE && ms_ty_kind(types, ty) == MS_TY_FUNCTION) {
      if (!crosses_callback(body, ty)) {
        ms_strbuild_append_text(&text, "extern parameter ");
        ms_strbuild_append(&text, param_name);
        ms_strbuild_append_text(&text, " has type ");
        ms_ty_show(&text, body->program->names, types, ty);
        ms_strbuild_printf(&text, ", which cannot cross the native boundary; a function an extern takes has at most %zu "
                                  "parameters of sized numbers, Bool, String, Bytes or extern types this program "
                                  "declares, and returns a number, Bool, String, Bytes or Void",
                           MAX_CALLBACK_PARAMS);
        report(body, param->pos, text);
      } else {
        ms_strbuild_free(&text);
      }
    } else if (ty != MS_TY_NONE && !holds_invalid(types, ty, 6) && !crosses_native(body, ty)) {
      ms_strbuild_append_text(&text, "extern parameter ");
      ms_strbuild_append(&text, param_name);
      ms_strbuild_append_text(&text, " has type ");
      type_name(body, &text, ty);
      ms_strbuild_append_text(&text, ", which cannot cross the native boundary; an extern takes sized numbers, Bool, "
                                     "String, Bytes, extern types this program declares, Lists of them, and functions of "
                                     "them");
      report(body, param->pos, text);
    } else {
      ms_strbuild_free(&text);
    }
  }
  const MsTy result = ms_ty_row(types, fn_ty)->result;
  if (func->result != NULL && result != MS_TY_NONE && !holds_invalid(types, result, 6)) {
    check_result(body, func, result);
  }
}
