/* compiler/check/instantiate.c: type argument inference for generic calls. */
#include "compiler/check/instantiate.h"
#include "compiler/check/program.h"

void ms_instance_free(MsInstance *instance) {
  ms_ty_list_free(&instance->args);
  ms_ty_list_free(&instance->unbound);
  ms_string_release(&instance->message);
  *instance = (MsInstance){.message = ms_string_empty()};
}

static bool fail(MsInstance *out, MsStrBuild *text) {
  out->message = ms_strbuild_finish(text);
  return false;
}

/* Matches `pattern` against `actual`, committing the bindings only when the whole match holds. */
static bool unify_commit(const MsTyTable *types, MsTy pattern, MsTy actual, const MsTy *vars, size_t count,
                         MsTy *bound) {
  MsTyList trial = {0};
  for (size_t index = 0; index < count; index++) {
    ms_ty_list_push(&trial, bound[index]);
  }
  const bool ok = ms_check_unify(types, pattern, actual, vars, count, trial.ptr);
  for (size_t index = 0; ok && index < count; index++) {
    bound[index] = trial.ptr[index];
  }
  ms_ty_list_free(&trial);
  return ok;
}

/* An argument for an Optional parameter may be the payload itself. */
static bool unify_argument(const MsTyTable *types, MsTy pattern, MsTy actual, const MsTy *vars, size_t count,
                           MsTy *bound) {
  if (unify_commit(types, pattern, actual, vars, count, bound)) {
    return true;
  }
  /* A variable another argument bound to `U?` takes a `U` (it converts), and one bound to `U` widens to `U?`. */
  for (size_t index = 0; index < count; index++) {
    if (vars[index] != pattern || bound[index] == MS_TY_NONE) {
      continue;
    }
    if (ms_ty_is(types, bound[index], MS_BUILTIN_Optional) && ms_ty_arg_count(types, bound[index]) == 1 &&
        ms_ty_args(types, bound[index])[0] == actual) {
      return true;
    }
    if (ms_ty_is(types, actual, MS_BUILTIN_Optional) && ms_ty_arg_count(types, actual) == 1 &&
        ms_ty_args(types, actual)[0] == bound[index]) {
      bound[index] = actual;
      return true;
    }
  }
  return ms_ty_is(types, pattern, MS_BUILTIN_Optional) && ms_ty_arg_count(types, pattern) == 1 &&
         unify_commit(types, ms_ty_args(types, pattern)[0], actual, vars, count, bound);
}

static void conflict(MsCheckProgram *program, MsInstance *out, MsTy pattern, MsTy actual) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "conflicting generic inference; argument of type ");
  ms_ty_show(&text, program->names, &program->types, actual);
  ms_strbuild_append_text(&text, " does not match ");
  ms_ty_show(&text, program->names, &program->types, pattern);
  ms_strbuild_append_text(&text, " under the types the other arguments imply, so make them the same type or give "
                                 "type arguments explicitly, e.g. f[Int](...)");
  (void)fail(out, &text);
}

/* The default of each unbound variable, read with the bindings known so far. */
static void apply_defaults(MsCheckProgram *program, const MsTy *vars, size_t count, MsTy *bound) {
  for (size_t index = 0; index < count; index++) {
    const MsTyVariable *record = ms_ty_variable(&program->types, vars[index]);
    if (bound[index] != MS_TY_NONE || record == NULL || record->default_ty == MS_TY_NONE) {
      continue;
    }
    MsTyList known_vars = {0};
    MsTyList known_args = {0};
    for (size_t at = 0; at < count; at++) {
      if (bound[at] != MS_TY_NONE) {
        ms_ty_list_push(&known_vars, vars[at]);
        ms_ty_list_push(&known_args, bound[at]);
      }
    }
    bound[index] = ms_ty_subst(&program->types, record->default_ty, known_vars.ptr, known_args.ptr, known_vars.len);
    ms_ty_list_free(&known_vars);
    ms_ty_list_free(&known_args);
  }
}

static void missing_message(MsCheckProgram *program, MsSpan name, const MsTy *vars, size_t count, const MsTy *bound,
                            MsInstance *out) {
  const MsTyTable *types = &program->types;
  MsStrBuild list = ms_strbuild_new();
  MsStrBuild parts = ms_strbuild_new();
  size_t missing = 0;
  for (size_t index = 0; index < count; index++) {
    const MsSpan variable = ms_names_span(program->names, ms_ty_row(types, vars[index])->name);
    if (index > 0) {
      ms_strbuild_append_text(&parts, ", ");
    }
    if (bound[index] != MS_TY_NONE) {
      ms_ty_show(&parts, program->names, types, bound[index]);
      continue;
    }
    ms_strbuild_append(&parts, variable);
    ms_ty_list_push(&out->unbound, vars[index]);
    if (missing++ > 0) {
      ms_strbuild_append_text(&list, ", ");
    }
    ms_strbuild_append(&list, variable);
  }
  MsStrBuild text = ms_strbuild_new();
  const char *noun = missing == 1 ? "argument" : "arguments";
  const char *each = missing == 1 ? "an explicit type for" : "explicit types for";
  ms_strbuild_printf(&text, "cannot infer type %s %.*s for %.*s; write %.*s[%.*s](...) with %s %.*s; call "
                            "arguments and the expected result must determine every type parameter",
                     noun, (int)ms_strbuild_length(&list), (const char *)ms_strbuild_span(&list).ptr,
                     (int)name.len, (const char *)name.ptr, (int)name.len, (const char *)name.ptr,
                     (int)ms_strbuild_length(&parts), (const char *)ms_strbuild_span(&parts).ptr, each,
                     (int)ms_strbuild_length(&list), (const char *)ms_strbuild_span(&list).ptr);
  ms_strbuild_free(&list);
  ms_strbuild_free(&parts);
  (void)fail(out, &text);
}

static bool infer(MsCheckProgram *program, MsTy callee, const MsTy *variables, size_t nvars, MsSpan name,
                  const MsTy *explicit_args, size_t nexplicit, const MsTy *arg_tys, size_t nargs,
                  MsTy expected_result, MsInstance *out, MsTy *bound) {
  MsTyTable *types = &program->types;
  *out = (MsInstance){.ty = callee, .message = ms_string_empty()};
  if (nexplicit > nvars) {
    MsStrBuild text = ms_strbuild_new();
    if (nvars == 0) {
      ms_strbuild_append_text(&text, "nongeneric function cannot take type arguments; remove the [...] after ");
      ms_strbuild_append(&text, name);
    } else {
      ms_strbuild_printf(&text, "generic arity mismatch; expected %zu type arguments, found %zu", nvars, nexplicit);
    }
    return fail(out, &text);
  }
  for (size_t index = 0; index < nexplicit; index++) {
    bound[index] = ms_ty_is_invalid(types, explicit_args[index]) ? MS_TY_NONE : explicit_args[index];
  }
  const size_t nparams = ms_ty_param_count(types, callee);
  for (size_t index = 0; index < nargs && index < nparams && nvars > 0; index++) {
    const MsTy pattern = ms_ty_params(types, callee)[index].ty;
    const MsTy actual = arg_tys[index];
    if (actual == MS_TY_NONE || ms_ty_is_invalid(types, actual) || !ms_ty_has_variable(types, pattern)) {
      continue;
    }
    if (unify_argument(types, pattern, actual, variables, nvars, bound)) {
      continue;
    }
    MsTyList fresh = {0};
    for (size_t at = 0; at < nvars; at++) {
      ms_ty_list_push(&fresh, MS_TY_NONE);
    }
    const bool alone = unify_argument(types, pattern, actual, variables, nvars, fresh.ptr);
    ms_ty_list_free(&fresh);
    if (alone) {
      conflict(program, out, pattern, actual);
      return false;
    }
  }
  const MsTy result = ms_ty_result(types, callee);
  if (expected_result != MS_TY_NONE && !ms_ty_is_invalid(types, expected_result) && nvars > 0 &&
      ms_ty_has_variable(types, result)) {
    if (!unify_commit(types, result, expected_result, variables, nvars, bound)) {
      /* Arguments already fixed one part of the result; the expected type still decides the parts they did not. */
      const size_t parts = ms_ty_arg_count(types, result);
      for (size_t part = 0; ms_ty_row(types, result)->id == ms_ty_row(types, expected_result)->id &&
                            parts == ms_ty_arg_count(types, expected_result) && part < parts;
           part++) {
        const MsTy pattern = ms_ty_args(types, result)[part];
        const MsTy wanted = ms_ty_args(types, expected_result)[part];
        for (size_t at = 0; at < nvars; at++) {
          /* An argument typed T where T? is expected converts, so the expected type wins. */
          if (variables[at] == pattern && bound[at] != MS_TY_NONE && ms_ty_is(types, wanted, MS_BUILTIN_Optional) &&
              ms_ty_arg_count(types, wanted) == 1 && ms_ty_args(types, wanted)[0] == bound[at]) {
            bound[at] = wanted;
          }
          /* An argument that implements the expected interface converts to it, so the expected type wins. */
          if (variables[at] == pattern && bound[at] != MS_TY_NONE && ms_ty_kind(types, wanted) == MS_TY_CONTRACT &&
              ms_ty_kind(types, bound[at]) != MS_TY_CONTRACT && ms_check_implements(program, bound[at], wanted)) {
            bound[at] = wanted;
          }
        }
        (void)unify_commit(types, pattern, wanted, variables, nvars, bound);
      }
    }
  }
  apply_defaults(program, variables, nvars, bound);
  for (size_t index = 0; index < nvars; index++) {
    if (bound[index] == MS_TY_NONE) {
      missing_message(program, name, variables, nvars, bound, out);
      return false;
    }
  }
  for (size_t index = 0; index < nvars; index++) {
    MsString why = ms_string_empty();
    if (!ms_check_bounds_hold_with(program, variables[index], bound[index], variables, bound, nvars,
                                  index < nexplicit ? "use a type that implements it" : "pass a type that already implements it", &why)) {
      out->message = why;
      return false;
    }
  }
  for (size_t index = 0; index < nvars; index++) {
    ms_ty_list_push(&out->args, bound[index]);
  }
  out->ty = ms_ty_subst(types, callee, variables, bound, nvars);
  return true;
}

bool ms_check_instantiate(MsCheckProgram *program, MsTy callee, const MsTy *variables, size_t nvars, MsSpan name,
                          const MsTy *explicit_args, size_t nexplicit, const MsTy *arg_tys, size_t nargs,
                          MsTy expected_result, MsInstance *out) {
  MsTyList bound = {0};
  for (size_t index = 0; index < nvars; index++) {
    ms_ty_list_push(&bound, MS_TY_NONE);
  }
  const bool ok = infer(program, callee, variables, nvars, name, explicit_args, nexplicit, arg_tys, nargs,
                        expected_result, out, bound.ptr);
  ms_ty_list_free(&bound);
  return ok;
}
