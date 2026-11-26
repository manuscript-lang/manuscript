/* compiler/check/calls.c: typing a call and recording its fact.
 *
 * The callee decides the signature: a function or closure, a method found for the receiver's type, a record
 * constructor, or an enum case with a payload. Arguments are matched to parameters (labels first, then
 * position), typed against the parameter types as far as inference has bound them, and the call's type
 * arguments come from ms_check_instantiate. The MsCall fact lists one argument per parameter, the receiver
 * first for a method: written, defaulted, or omitted. */
#include "compiler/check/call_internal.h"
#include "compiler/syntax/walk.h"

#include <string.h>
#include "compiler/check/instantiate.h"
#include "compiler/check/methods.h"
#include "compiler/syntax/parse.h"



/* ---- arguments ---- */



static bool param_index(const Body *body, const Target *target, MsName name, size_t *index) {
  for (size_t at = 0; at < ms_ty_param_count(&body->program->types, target->sig); at++) {
    if (target_param_name(body, target, at) == name) {
      *index = at;
      return true;
    }
  }
  return false;
}

/* Assigns each written argument a parameter: by label, else the next free one in order. */
static void match_args(const Body *body, const Target *target, const MsExpr *call, Matched *matched) {
  const MsTyTable *types = &body->program->types;
  const size_t nparams = ms_ty_param_count(types, target->sig);
  size_t cursor = 0;
  for (uint32_t at = 0; at < call->u.call.args.len; at++) {
    const MsArg *arg = &call->u.call.args.ptr[at];
    size_t index = 0;
    if (arg->has_name) {
      const bool found = param_index(body, target, arg->name, &index) && !target_positional(body, target, index);
      matched->state[at] = !found ? ARG_UNKNOWN : matched->slot[index] >= 0 ? ARG_DUPLICATE : ARG_MATCHED;
      matched->slot[index] = matched->state[at] == ARG_MATCHED ? (int32_t)at : matched->slot[index];
      continue;
    }
    while (cursor < nparams && matched->slot[cursor] >= 0) {
      cursor++;
    }
    const bool named_only = target->nominal != MS_TY_NONE && /* `reserve` of a List is named-only */
                            ms_ty_is(types, target->nominal, MS_BUILTIN_List);
    if (named_only) {
      cursor = nparams;
    }
    matched->state[at] = cursor < nparams ? ARG_MATCHED : ARG_EXTRA;
    if (cursor < nparams) {
      matched->slot[cursor] = (int32_t)at;
    }
  }
}

/* A generic type still carrying its own declaration's variables, as `none` has before a target gives it one. */
static bool unapplied(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  if (ty == MS_TY_NONE || ms_ty_arg_count(types, ty) == 0) {
    return false;
  }
  const uint32_t at = ms_ty_row(types, ty)->def;
  const MsDef *def = at == 0 ? NULL : ms_defs_get(&body->program->defs, at);
  if (def == NULL || def->variables.len != ms_ty_arg_count(types, ty)) {
    return false;
  }
  for (size_t index = 0; index < def->variables.len; index++) {
    if (ms_ty_args(types, ty)[index] != def->variables.ptr[index]) {
      return false;
    }
  }
  return true;
}

/* The parameter type with the variables bound so far substituted. */
static MsTy expected_param(Body *body, const Target *target, MsTy param, const MsTy *bound) {
  size_t known = 0;
  MsTy vars[16];
  MsTy args[16];
  for (size_t index = 0; index < target->vars.len && index < 16; index++) {
    if (bound[index] != MS_TY_NONE) {
      vars[known] = target->vars.ptr[index];
      args[known++] = bound[index];
    }
  }
  return known == 0 ? param : ms_ty_subst(&body->program->types, param, vars, args, known);
}

static bool is_own_variable(const Target *target, MsTy ty) {
  for (size_t at = 0; at < target->vars.len; at++) {
    if (target->vars.ptr[at] == ty) {
      return true;
    }
  }
  return false;
}

/* The variables the expected result of the call fixes, for an argument that has no better source: `T?` expected
 * as `Int?` says an open `T?` argument is an `Int?`. An argument still binds the variable first. */
static void result_hint(Body *body, const Target *target, MsTy expected, MsTy *hint) {
  const MsTyTable *types = &body->program->types;
  const size_t count = target->vars.len;
  const MsTy result = target->sig == MS_TY_NONE ? MS_TY_NONE : ms_ty_result(types, target->sig);
  if (expected != MS_TY_NONE && result != MS_TY_NONE && ms_ty_is(types, expected, MS_BUILTIN_Optional) &&
      ms_ty_arg_count(types, expected) == 1 && !ms_ty_is(types, result, MS_BUILTIN_Optional)) {
    expected = ms_ty_args(types, expected)[0]; /* a value wrapped as an optional is typed as its payload */
  }
  if (expected == MS_TY_NONE || ms_ty_is_invalid(types, expected) || count == 0 || count > 16 || result == MS_TY_NONE ||
      !ms_ty_has_variable(types, result) || body_has_foreign_variable(body, expected)) {
    return;
  }
  MsTy trial[16] = {0};
  if (ms_check_unify(types, result, expected, target->vars.ptr, count, trial)) {
    for (size_t index = 0; index < count; index++) {
      hint[index] = trial[index];
    }
  }
}

/* Whether `ty` mentions one of the callee's own variables (an inference slot not yet bound). */
static bool mentions_vars(const MsTyTable *types, MsTy ty, const MsTyList *vars) {
  if (!ms_ty_has_variable(types, ty)) {
    return false;
  }
  for (size_t index = 0; index < vars->len; index++) {
    if (vars->ptr[index] == ty) {
      return true;
    }
  }
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    if (mentions_vars(types, ms_ty_args(types, ty)[index], vars)) {
      return true;
    }
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    if (mentions_vars(types, ms_ty_params(types, ty)[index].ty, vars)) {
      return true;
    }
  }
  return ms_ty_kind(types, ty) == MS_TY_FUNCTION && mentions_vars(types, ms_ty_result(types, ty), vars);
}

/* A function-typed argument with the parameter modes (`move`, `var`) its context declares: a function value
 * passes where the callee's parameter type differs from its own only in how the arguments are borrowed. */
static MsTy with_context_modes(Body *body, MsTy param, MsTy arg) {
  const MsTyTable *types = &body->program->types;
  if (arg == MS_TY_NONE || param == MS_TY_NONE || ms_ty_kind(types, arg) != MS_TY_FUNCTION ||
      ms_ty_kind(types, param) != MS_TY_FUNCTION || ms_ty_param_count(types, arg) != ms_ty_param_count(types, param)) {
    return arg;
  }
  MsTyParamList params = {0};
  for (size_t index = 0; index < ms_ty_param_count(types, arg); index++) {
    MsTyParam entry = ms_ty_params(types, arg)[index];
    entry.flags = (uint8_t)((entry.flags & ~(MS_PARAM_VAR | MS_PARAM_MOVE)) |
                            (ms_ty_params(types, param)[index].flags & (MS_PARAM_VAR | MS_PARAM_MOVE)));
    ms_ty_param_list_push(&params, entry);
  }
  const MsTy adapted = body_call_function_type(body, &params, ms_ty_result(types, arg));
  ms_ty_param_list_free(&params);
  return adapted;
}

static bool is_empty_literal(const MsExpr *expr) {
  return (expr->kind == MS_E_LIST && expr->u.list.len == 0) || (expr->kind == MS_E_MAP && expr->u.map.len == 0);
}

static bool is_function(const MsTyTable *types, MsTy ty) {
  return ms_ty_kind(types, ty) == MS_TY_FUNCTION;
}

/* `argument 'name' of callee`, the context of a mismatch in one argument; empty when the callee has no name. */
static void argument_context(Body *body, const Target *target, size_t index, MsStrBuild *context) {
  if (target->name.len == 0) {
    return;
  }
  ms_strbuild_append_text(context, "argument '");
  ms_strbuild_append(context, ms_names_span(body->program->names, target_param_name(body, target, index)));
  ms_strbuild_append_text(context, "' of ");
  ms_strbuild_append(context, target->name);
}

static void append_count(MsStrBuild *text, size_t count) {
  ms_strbuild_printf(text, "%zu parameter%s", count, count == 1 ? "" : "s");
}

/* A function argument for a callback parameter that mentions the callee's variables, with another parameter count:
 * reported at the argument; it binds nothing. */
static bool report_callback_arity(Body *body, const Target *target, const MsExpr *value, MsTy param, MsTy actual) {
  const MsTyTable *types = &body->program->types;
  if (!is_function(types, param) || !is_function(types, actual) || !mentions_vars(types, param, &target->vars) ||
      ms_ty_param_count(types, param) == ms_ty_param_count(types, actual)) {
    return false;
  }
  if (body_reports(body) && !body->quiet) {
    const size_t have = ms_ty_param_count(types, actual);
    const size_t want = ms_ty_param_count(types, param);
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "callback mismatch: the function takes ");
    append_count(&text, have);
    ms_strbuild_append_text(&text, " but this position expects ");
    ms_strbuild_printf(&text, "%zu; pass a function with ", want);
    append_count(&text, want);
    ms_strbuild_append_text(&text, ", or wrap it in a closure that supplies the rest");
    ms_check_report(body->program, body->module, value->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  return true;
}

/* Whether `actual` cannot be what `pattern` shapes, whatever its variables turn out to be: another kind or another head. */
static bool head_differs(const MsTyTable *types, MsTy pattern, MsTy actual) {
  if (ms_ty_kind(types, pattern) == MS_TY_VARIABLE || ms_ty_kind(types, pattern) == MS_TY_CONTRACT || actual == MS_TY_NONE || ms_ty_is_invalid(types, actual) ||
      ms_ty_kind(types, actual) == MS_TY_VARIABLE) {
    return false;
  }
  const MsTyRow *want = ms_ty_row(types, pattern);
  const MsTyRow *have = ms_ty_row(types, actual);
  return want->kind != have->kind || want->id != have->id;
}

/* An argument whose shape cannot meet the parameter that infers the callee's variables: reported at the argument, as
 * the parameter's type and what the argument is (a callback gets its result named). */
static bool report_shape_mismatch(Body *body, const Target *target, const MsExpr *value, MsTy param, MsTy actual) {
  const MsTyTable *types = &body->program->types;
  if (!mentions_vars(types, param, &target->vars) || body_is_none_name(body, value) || holds_invalid(types, actual, 6)) {
    return false;
  }
  MsStrBuild text = ms_strbuild_new();
  if (is_function(types, param) && is_function(types, actual) &&
      ms_ty_param_count(types, param) == ms_ty_param_count(types, actual) &&
      ms_ty_is(types, ms_ty_result(types, param), MS_BUILTIN_Result) &&
      head_differs(types, ms_ty_result(types, param), ms_ty_result(types, actual))) {
    const MsTy wanted = ms_ty_result(types, param);
    ms_strbuild_append_text(&text, "the callback returns ");
    ms_ty_show(&text, body->program->names, types, ms_ty_result(types, actual));
    ms_strbuild_append_text(&text, ", but this parameter needs a function returning ");
    ms_ty_show(&text, body->program->names, types, wanted);
    if (ms_ty_is(types, wanted, MS_BUILTIN_Result)) {
      ms_strbuild_append_text(&text, "; a Result-returning callback reports failure as a value, so wrap the value in ok(...), "
                                     "e.g. fn: ok(value)");
    }
  } else if (!is_function(types, param) && !ms_ty_is(types, param, MS_BUILTIN_Optional) && head_differs(types, param, actual) && !is_function(types, actual)) {
    ms_strbuild_append_text(&text, "expected ");
    ms_ty_show(&text, body->program->names, types, param);
    ms_strbuild_append_text(&text, ", found ");
    ms_ty_show(&text, body->program->names, types, actual);
    ms_strbuild_append_text(&text, "; the argument must be a ");
    ms_ty_show(&text, body->program->names, types, param);
    ms_strbuild_append_text(&text, ", and the type variables are inferred from it");
  } else {
    ms_strbuild_free(&text);
    return false;
  }
  if (body_reports(body) && !body->quiet) {
    ms_check_report(body->program, body->module, value->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    const MsExpr *result = value->kind == MS_E_LAMBDA && value->u.lambda.body.len == 1 &&
                                   (value->u.lambda.body.ptr[0]->kind == MS_S_CALL || value->u.lambda.body.ptr[0]->kind == MS_S_RETURN)
                               ? value->u.lambda.body.ptr[0]->u.expr
                               : NULL;
    const MsSpan source = body->program->modules.ptr[body->module].source;
    const MsPos from = result != NULL ? ms_expr_start(result) : (MsPos){0};
    if (result != NULL && is_function(types, param) && ms_ty_is(types, ms_ty_result(types, param), MS_BUILTIN_Result) &&
        result->end.offset > from.offset && result->end.offset <= source.len) {
      MsStrBuild fix = ms_strbuild_new(); /* wrap the callback's value: it reports failure as a value */
      ms_strbuild_append_text(&fix, "ok(");
      ms_strbuild_append(&fix, ms_span_of(source.ptr + from.offset, result->end.offset - from.offset));
      ms_strbuild_append_text(&fix, ")");
      ms_check_attach_fix(body->program, from, result->end, ms_strbuild_finish(&fix));
    }
  } else {
    ms_strbuild_free(&text);
  }
  return true;
}

/* The type the expected result gives the callee's own variable `variable`, or MS_TY_NONE. */
static MsTy hint_for(const Target *target, MsTy variable, const MsTy *hint) {
  for (size_t at = 0; at < target->vars.len && at < 16; at++) {
    if (target->vars.ptr[at] == variable) {
      return hint[at];
    }
  }
  return MS_TY_NONE;
}

/* Whether a function parameter's own parameter types still mention variables nothing has fixed. */
static bool function_params_open(Body *body, const Target *target, MsTy param, const MsTy *bound) {
  const MsTyTable *types = &body->program->types;
  if (ms_ty_is(types, param, MS_BUILTIN_Optional) && ms_ty_arg_count(types, param) == 1) {
    param = ms_ty_args(types, param)[0];
  }
  if (!is_function(types, param)) {
    return false;
  }
  const MsTy known = expected_param(body, target, param, bound);
  for (size_t at = 0; at < ms_ty_param_count(types, known); at++) {
    if (mentions_vars(types, ms_ty_params(types, known)[at].ty, &target->vars)) {
      return true;
    }
  }
  return false;
}

/* Types the written arguments in parameter order; returns the type of each parameter's argument. */
static void type_args(Body *body, const Target *target, const MsExpr *call, const Matched *matched, MsTy *arg_tys,
                      MsTy *bound, const MsTy *hint) {
  const MsTyTable *types = &body->program->types;
  /* A function literal is typed after the other arguments, so the variables they fix are known to it. */
  const size_t nargs = call->u.call.args.len;
  bool *const typed = MS_ARENA_NEW_ARRAY(&body->program->arena, bool, nargs + 1);
  bool *const waited = MS_ARENA_NEW_ARRAY(&body->program->arena, bool, matched->count + 1); /* left open by an uninferred case */
  bool has_lambda = false;
  for (size_t at = 0; at < nargs; at++) {
    has_lambda = has_lambda || call->u.call.args.ptr[at].value->kind == MS_E_LAMBDA;
  }
  /* Without a function literal only the first pass types anything; the later passes would only scan. */
  const size_t rounds = has_lambda ? nargs * (nargs + 1) : nargs;
  for (size_t round = 0; round < rounds; round++) {
    const size_t written = round % nargs; /* arguments bind variables in the order they are written */
    const size_t pass = round / nargs;    /* 0 types the other arguments; each later pass the function literals */
    size_t index = 0;
    while (index < matched->count && matched->slot[index] != (int32_t)written) {
      index++;
    }
    if (index == matched->count) {
      continue;
    }
    const MsTy param = ms_ty_params(types, target->sig)[index].ty;
    const MsArg *arg = &call->u.call.args.ptr[matched->slot[index]];
    if ((arg->value->kind == MS_E_LAMBDA) != (pass >= 1) || typed[written]) {
      continue;
    }
    if (pass >= 1 && pass < nargs && function_params_open(body, target, param, bound)) {
      continue; /* a function literal whose parameters another function literal fixes waits for it */
    }
    typed[written] = true;
    MsStrBuild context = ms_strbuild_new();
    if (target->name.len != 0) {
      ms_strbuild_append_text(&context, "argument '");
      ms_strbuild_append(&context, ms_names_span(body->program->names, target_param_name(body, target, index)));
      ms_strbuild_append_text(&context, "' of ");
      ms_strbuild_append(&context, target->name);
    }
    MsTy wanted = expected_param(body, target, param, bound);
    bool open = mentions_vars(types, wanted, &target->vars);
    bool by_hint = false; /* only the call's expected result closes the parameter: a function argument is judged later */
    if (open && (!is_own_variable(target, wanted) || (target->constructor && ms_ty_is(types, ms_ty_result(types, target->sig), MS_BUILTIN_Result) && hint_for(target, wanted, hint) != MS_TY_NONE))) {
      MsTy known[16] = {0};
      for (size_t at = 0; at < target->vars.len && at < 16; at++) {
        known[at] = bound[at] != MS_TY_NONE ? bound[at] : hint[at];
      }
      wanted = expected_param(body, target, param, known);
      open = mentions_vars(types, wanted, &target->vars);
      by_hint = !open && is_function(types, wanted) && arg->value->kind == MS_E_NAME;
    }
    /* A collection literal is inferred from its entries, then unified with the open parameter type. */
    const bool literal = arg->value->kind == MS_E_LIST || arg->value->kind == MS_E_MAP;
    bool bare = false; /* the parameter is one of the callee's own variables: it says nothing the argument can use */
    for (size_t at = 0; at < target->vars.len; at++) {
      bare = bare || target->vars.ptr[at] == wanted;
    }
    /* An empty literal beside an open parameter waits for the other arguments: it is reported below if none fixes it. */
    const bool quiet_before = body->quiet;
    body->quiet = quiet_before || (open && is_empty_literal(arg->value));
    const bool defer_before = body->defer_uninferred;
    const uint32_t uninferred = body->uninferred;
    body->defer_uninferred = open; /* a case only the other arguments or the result can type waits for them */
    arg_tys[index] = open || by_hint ? body_expr(body, arg->value, literal || bare ? MS_TY_NONE : wanted)
                         : body_expect(body, arg->value, wanted, ms_strbuild_span(&context));
    body->quiet = quiet_before;
    body->defer_uninferred = defer_before;
    waited[index] = body->uninferred != uninferred;
    if (by_hint && arg_tys[index] != MS_TY_NONE && is_function(types, arg_tys[index]) &&
        ms_ty_param_count(types, arg_tys[index]) == ms_ty_param_count(types, wanted)) {
      body_check_assignable(body, arg->value, arg_tys[index], wanted, ms_strbuild_span(&context));
    }
    ms_strbuild_free(&context);
    arg_tys[index] = with_context_modes(body, param, unapplied(body, arg_tys[index]) ? MS_TY_NONE : arg_tys[index]);
    /* An argument typed exactly as its open parameter (`Opt.None` for `Opt[T]`) fixes nothing: the other arguments do. */
    const bool echoes = open && arg_tys[index] == wanted;
    if (target->vars.len != 0 && target->vars.len <= 16 && arg_tys[index] != MS_TY_NONE && !echoes &&
        !body_is_none_name(body, arg->value) && !(is_function(types, arg_tys[index]) && unapplied(body, ms_ty_result(types, arg_tys[index]))) &&
        !report_callback_arity(body, target, arg->value, param, arg_tys[index])) {
      if (!ms_check_unify(types, param, arg_tys[index], target->vars.ptr, target->vars.len, bound)) {
        (void)report_shape_mismatch(body, target, arg->value, param, arg_tys[index]);
      }
    }
  }
  /* An argument checked while the callee's variables were open meets its final parameter type only now. */
  for (size_t index = 0; index < matched->count; index++) {
    if (matched->slot[index] < 0) {
      continue;
    }
    const MsTy param = ms_ty_params(types, target->sig)[index].ty;
    if (mentions_vars(types, param, &target->vars)) {
      const MsExpr *value = call->u.call.args.ptr[matched->slot[index]].value;
      MsTy known[16] = {0}; /* what the arguments bound, then what the expected result implies */
      for (size_t at = 0; at < target->vars.len && at < 16; at++) {
        known[at] = bound[at] != MS_TY_NONE ? bound[at] : hint[at];
      }
      const MsTy final = expected_param(body, target, param, known);
      if (is_empty_literal(value) && mentions_vars(types, final, &target->vars) && body_reports(body) && !body->quiet) {
        body_report_empty_literal(body, value);
      }
      if (arg_tys[index] == final && mentions_vars(types, final, &target->vars) && value->kind == MS_E_MEMBER) {
        body_report_uninferred_case(body, value, final); /* `Opt.None` beside nothing that fixes its type arguments */
      }
      if (waited[index] && mentions_vars(types, final, &target->vars)) {
        arg_tys[index] = body_expr(body, value, MS_TY_NONE); /* nothing fixed the case: typed again to report it */
        continue;
      }
      if ((arg_tys[index] == MS_TY_NONE || body_has_foreign_variable(body, arg_tys[index])) && !mentions_vars(types, final, &target->vars)) {
        /* An argument typed while a variable was open (`Box(none)` beside `Box(value)`) is typed again at its final type. */
        const bool quiet = body->quiet;
        body->quiet = true;
        const MsTy again = body_expr(body, value, final);
        body->quiet = quiet;
        arg_tys[index] = again != MS_TY_NONE ? again : arg_tys[index];
      }
      if (arg_tys[index] != MS_TY_NONE && is_function(types, final) && is_function(types, arg_tys[index]) &&
          ms_ty_param_count(types, final) != ms_ty_param_count(types, arg_tys[index]) &&
          !mentions_vars(types, final, &target->vars)) {
        MsStrBuild context = ms_strbuild_new();
        argument_context(body, target, index, &context);
        body_check_assignable(body, value, arg_tys[index], final, ms_strbuild_span(&context));
        ms_strbuild_free(&context);
      } else if (arg_tys[index] != MS_TY_NONE) {
        body_convert(body, value, arg_tys[index], final);
      }
    }
  }
}

/* Whether the function argument takes its parameter `at` as `var`: a lambda by what it writes (an expected `var` does
 * not make a reading lambda change it), another function by its type. */
static bool written_var(const MsTyTable *types, const MsExpr *value, MsTy given, size_t at) {
  if (value->kind == MS_E_LAMBDA) {
    return at < value->u.lambda.params.len && value->u.lambda.params.ptr[at]->is_mutable;
  }
  return (ms_ty_params(types, given)[at].flags & MS_PARAM_VAR) != 0;
}

/* One MsCallArg per parameter (the receiver first): written, defaulted or omitted. */
static MsCallArg *build_args(Body *body, const Target *target, const MsExpr *call, const Matched *matched,
                             uint32_t *count) {
  const MsTyTable *types = &body->program->types;
  const size_t offset = target->receiver != NULL ? 1 : 0;
  MsCallArg *args = MS_ARENA_NEW_ARRAY(&body->program->arena, MsCallArg, matched->count + offset);
  if (offset != 0) {
    args[0] = (MsCallArg){.source = MS_ARG_WRITTEN, .node = {body->module, target->receiver->id},
                          .flags = target->receiver_flags};
  }
  for (size_t index = 0; offset != 0 && index < matched->count && (args[0].flags & MS_PARAM_VAR) == 0; index++) {
    /* A callback that takes one of the receiver's elements as `var` changes the receiver where it runs. */
    const MsTy declared = ms_ty_params(types, target->sig)[index].ty;
    const MsTy receiver = ms_facts_type(body->facts, target->receiver->id);
    if (matched->slot[index] < 0 || receiver == MS_TY_NONE || !is_function(types, declared)) {
      continue;
    }
    const MsTy given = ms_facts_type(body->facts, call->u.call.args.ptr[matched->slot[index]].value->id);
    for (size_t at = 0; given != MS_TY_NONE && is_function(types, given) && at < ms_ty_param_count(types, declared) &&
                        at < ms_ty_param_count(types, given);
         at++) {
      const MsTyParam *want = &ms_ty_params(types, declared)[at];
      for (size_t arg = 0; (want->flags & MS_PARAM_VAR) != 0 && written_var(types, call->u.call.args.ptr[matched->slot[index]].value, given, at) &&
                           arg < ms_ty_arg_count(types, receiver);
           arg++) {
        if (ms_ty_args(types, receiver)[arg] == want->ty) {
          args[0].flags |= MS_PARAM_VAR;
        }
      }
    }
  }
  for (size_t index = 0; index < matched->count; index++) {
    const MsTyParam *param = &ms_ty_params(types, target->sig)[index];
    MsCallArg *out = &args[index + offset];
    out->flags = param->flags & (MS_PARAM_VAR | MS_PARAM_MOVE);
    const MsExpr *def = target->ast != NULL && index < target->ast->len ? target->ast->ptr[index]->def : NULL;
    if (matched->slot[index] >= 0) {
      const MsArg *arg = &call->u.call.args.ptr[matched->slot[index]];
      *out = (MsCallArg){.source = MS_ARG_WRITTEN, .node = {body->module, arg->value->id},
                         .label = arg->has_name ? arg->name : 0, .flags = out->flags};
    } else if (def != NULL) {
      *out = (MsCallArg){.source = MS_ARG_DEFAULT, .node = {target->ast_module, def->id}, .flags = out->flags};
    } else if ((param->flags & MS_PARAM_LIFTED) != 0 && ms_ty_is(types, param->ty, MS_BUILTIN_Error)) {
      out->source = MS_ARG_MISSING_VALUE; /* a function value of `ok_or` keeps its cause optional; another omittable parameter is none */
    } else {
      out->source = MS_ARG_OMITTED;
    }
  }
  *count = (uint32_t)(matched->count + offset);
  return args;
}

static MsTy record_call(Body *body, const MsExpr *call, const Target *target, MsTy instantiated, const MsTyList *type_args_list,
                        const Matched *matched) {
  MsCall fact = {.node = call->id, .callee = target->ref, .callee_ty = instantiated, .constructor = target->constructor};
  fact.args = build_args(body, target, call, matched, &fact.arg_count);
  if (type_args_list->len != 0) {
    MsTy *copy = MS_ARENA_NEW_ARRAY(&body->program->arena, MsTy, type_args_list->len);
    for (size_t index = 0; index < type_args_list->len; index++) {
      copy[index] = type_args_list->ptr[index];
    }
    fact.type_args = copy;
    fact.type_arg_count = (uint32_t)type_args_list->len;
  }
  ms_facts_add_call(body->facts, &fact);
  return ms_ty_result(&body->program->types, instantiated);
}

/* An argument typed `T` for a parameter the expected result made `T?` is wrapped (`ok(3)` where `Int?!` is wanted). */
static void wrap_to_expected(Body *body, const MsExpr *call, MsTy sig, const MsTy *arg_tys, const Matched *matched) {
  const MsTyTable *types = &body->program->types;
  for (size_t index = 0; index < matched->count; index++) {
    const MsTy param = ms_ty_params(types, sig)[index].ty;
    const MsExpr *value = matched->slot[index] >= 0 ? call->u.call.args.ptr[matched->slot[index]].value : NULL;
    if (value != NULL && unapplied(body, ms_facts_type(body->facts, value->id))) {
      body_set_type(body, value->id, param); /* `none` takes the type its target gives it */
    }
    if (matched->slot[index] >= 0 && arg_tys[index] != MS_TY_NONE && ms_ty_is(types, param, MS_BUILTIN_Optional) &&
        ms_ty_arg_count(types, param) == 1 && ms_ty_args(types, param)[0] == arg_tys[index]) {
      body_convert(body, call->u.call.args.ptr[matched->slot[index]].value, arg_tys[index], param);
    }
  }
}

/* Whether every diagnostic since `before` is an uninferred callback parameter or an argument or type the call could
 * not read, which the call's own failure explains. */
static bool only_callback_diagnostics(const MsCheckProgram *program, size_t before) {
  for (size_t index = before; index < program->diagnostics.len; index++) {
    const MsSpan message = ms_string_span(&program->diagnostics.ptr[index].message);
    if (!ms_span_starts_with_text(message, "cannot infer callback parameter") &&
        !ms_span_starts_with_text(message, "unknown argument ") &&
        !ms_span_starts_with_text(message, "unknown type ")) {
      return false;
    }
  }
  return true;
}

/* An instantiation failure worth reporting: a type argument no argument determines, while every argument typed. */
static bool uninferable(const Body *body, const MsInstance *instance, const MsTy *arg_tys, const Matched *matched,
                        size_t before, MsTy callee) {
  const size_t count = matched->count;
  const MsSpan message = ms_string_span(&instance->message);
  const MsTyTable *types = &body->program->types;
  size_t found = 0;
  const bool unmet_bound = ms_span_find(message, ms_span_of_text(" does not satisfy "), &found) ||
                           ms_span_find(message, ms_span_of_text(" is not a member of the type set "), &found);
  if (!body_reports(body) || body->quiet ||
      !(unmet_bound || ms_span_starts_with_text(message, "cannot infer type argument")) ||
      !only_callback_diagnostics(body->program, before) || holds_invalid(types, body->result, 6) ||
      holds_invalid(types, callee, 6)) {
    return false;
  }
  if (body->program->diagnostics.len > before) {
    return true; /* the callbacks that could not be typed explain every untyped argument */
  }
  for (size_t index = 0; index < count; index++) {
    if (matched->slot[index] >= 0 && holds_invalid(types, arg_tys[index], 6)) { /* an omitted argument has no type */
      return false;
    }
  }
  return true;
}

/* A constructor names each variable it could not infer; any other callee gets the one message. */
static void report_uninferred(Body *body, const MsExpr *call, const Target *target, const MsInstance *instance) {
  if (!target->constructor || instance->unbound.len == 0) { /* a constructor names each variable it left unbound */
    ms_check_report(body->program, body->module, call->pos, MS_CHECK_TYPE,
                    ms_string_from_span(ms_string_span(&instance->message)));
    return;
  }
  for (size_t index = 0; index < instance->unbound.len; index++) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "cannot infer constructor type argument ");
    ms_strbuild_append(&text, ms_names_span(body->program->names, ms_ty_row(&body->program->types, instance->unbound.ptr[index])->name));
    ms_strbuild_append_text(&text, "; write the type arguments, e.g. Box[Int](...), or annotate the binding");
    ms_check_report(body->program, body->module, call->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
}

/* Arguments that imply different types for one variable: the one written later is the one that disagrees. */
static void report_conflict(Body *body, const MsExpr *call, const Target *target, const MsInstance *instance,
                            const MsTy *arg_tys, const Matched *matched, size_t before) {
  const int32_t slot = matched->slot[instance->conflict];
  if (!body_reports(body) || body->quiet || slot < 0) {
    return;
  }
  const MsArg *arg = &call->u.call.args.ptr[slot];
  const MsTy param = ms_ty_params(&body->program->types, target->sig)[instance->conflict].ty;
  bool bare = false; /* a number for a bare variable waits for the other arguments, so it only mismatches */
  for (size_t at = 0; at < target->vars.len; at++) {
    bare = bare || target->vars.ptr[at] == param;
  }
  if (!(bare && arg->value->kind == MS_E_NUMBER)) {
    ms_check_report(body->program, body->module, arg->pos, MS_CHECK_TYPE,
                    ms_string_from_span(ms_string_span(&instance->message)));
  }
  for (size_t index = before; index < body->program->diagnostics.len; index++) { /* the argument already failed its type */
    if (body->program->diagnostics.ptr[index].pos.offset == arg->value->pos.offset) {
      return;
    }
  }
  const MsTy wanted = ms_ty_subst(&body->program->types, param, target->vars.ptr, instance->args.ptr, target->vars.len);
  MsStrBuild context = ms_strbuild_new();
  argument_context(body, target, instance->conflict, &context);
  body_check_assignable(body, arg->value, arg_tys[instance->conflict], wanted, ms_strbuild_span(&context));
  ms_strbuild_free(&context);
}

/* The nodes typed while the callee's variables were open (a callback's first `return error(...)`) name them: now that
 * the call has its type arguments, they take them. */
static void settle_typed(Body *body, const Target *target, const MsTyList *args) {
  const MsTyTable *types = &body->program->types;
  MsTy from[16];
  MsTy to[16];
  size_t count = 0;
  for (size_t at = 0; at < target->vars.len && at < args->len && at < 16; at++) {
    if (args->ptr[at] != MS_TY_NONE && !holds_invalid(types, args->ptr[at], 6) &&
        body_has_foreign_variable(body, target->vars.ptr[at])) { /* not the enclosing function's own variable */
      from[count] = target->vars.ptr[at];
      to[count++] = args->ptr[at];
    }
  }
  for (size_t at = target->journal; count != 0 && at < body->typed.len; at++) {
    const MsNode node = body->typed.ptr[at];
    const MsTy ty = body->facts->types[node];
    if (ty != MS_TY_NONE && ms_ty_has_variable(types, ty)) {
      body->facts->types[node] = ms_ty_subst(&body->program->types, ty, from, to, count);
    }
  }
  for (size_t at = target->calls_mark; count != 0 && at < body->facts->calls.len; at++) { /* and the calls inside it */
    MsCall *call = &body->facts->calls.ptr[at];
    call->callee_ty = ms_ty_subst(&body->program->types, call->callee_ty, from, to, count);
    if (call->type_arg_count != 0) {
      MsTy *fresh = MS_ARENA_NEW_ARRAY(&body->program->arena, MsTy, call->type_arg_count);
      for (uint32_t index = 0; index < call->type_arg_count; index++) {
        fresh[index] = ms_ty_subst(&body->program->types, call->type_args[index], from, to, count);
      }
      call->type_args = fresh;
    }
  }
}

static MsTy finish_call(Body *body, const MsExpr *call, Target *target, const MsTy *arg_tys, const Matched *matched,
                        MsTy expected, size_t diagnostics_before) {
  MsInstance instance = {0};
  MsTy sig = target->sig;
  bool instantiated = true;
  MsTy partial = MS_TY_NONE; /* a constructor that left a variable unbound still has the parts the arguments fixed */
  MsTyList typed = {0};
  const MsTy *written = arg_tys; /* the arguments' own types, before any is held back from inference */
  if (body->program->diagnostics.len > diagnostics_before && only_callback_diagnostics(body->program, diagnostics_before)) {
    /* a callback that could not be typed gives the call no evidence about its type arguments */
    for (size_t index = 0; index < matched->count; index++) {
      ms_ty_list_push(&typed, holds_invalid(&body->program->types, arg_tys[index], 6) ? MS_TY_NONE : arg_tys[index]);
    }
    arg_tys = typed.ptr;
  }
  if (target->vars.len != 0 && typed.len == 0) {
    bool bare = false;
    for (size_t index = 0; index < matched->count; index++) {
      bare = bare || (matched->slot[index] >= 0 && body_is_none_name(body, call->u.call.args.ptr[matched->slot[index]].value));
    }
    for (size_t index = 0; bare && index < matched->count; index++) {
      const bool none = matched->slot[index] >= 0 && body_is_none_name(body, call->u.call.args.ptr[matched->slot[index]].value);
      ms_ty_list_push(&typed, none ? MS_TY_NONE : arg_tys[index]);
    }
    arg_tys = bare ? typed.ptr : arg_tys;
  }
  if (target->vars.len != 0) {
    const MsSpan name = target->name;
    size_t *order = MS_ARENA_NEW_ARRAY(&body->program->arena, size_t, matched->count + 1);
    size_t ordered = 0;
    for (int32_t slot = 0; ordered < matched->count && slot < (int32_t)call->u.call.args.len; slot++) {
      for (size_t index = 0; index < matched->count; index++) {
        if (matched->slot[index] == slot) {
          order[ordered++] = index;
        }
      }
    }
    for (size_t index = 0; index < matched->count; index++) { /* omitted parameters follow */
      if (matched->slot[index] < 0) {
        order[ordered++] = index;
      }
    }
    if (ms_check_instantiate(body->program, target->sig, target->vars.ptr, target->vars.len, name,
                             target->explicit_args.ptr, target->explicit_args.len, arg_tys, matched->count, order,
                             expected, &instance)) {
      if (target->outer_vars.len != 0) { /* a default that names the receiver's arguments */
        for (size_t at = 0; at < instance.args.len; at++) {
          instance.args.ptr[at] = ms_ty_subst(&body->program->types, instance.args.ptr[at], target->outer_vars.ptr,
                                              target->outer_args.ptr, target->outer_vars.len);
        }
        instance.ty = ms_ty_subst(&body->program->types, target->sig, target->vars.ptr, instance.args.ptr, instance.args.len);
      }
      sig = instance.ty;
      settle_typed(body, target, &instance.args);
      wrap_to_expected(body, call, sig, arg_tys, matched);
    } else {
      instantiated = false;
      if (instance.conflict != SIZE_MAX) {
        report_conflict(body, call, target, &instance, arg_tys, matched, diagnostics_before);
      } else if ((expected == MS_TY_NONE || !holds_invalid(&body->program->types, expected, 6)) && uninferable(body, &instance, written, matched, diagnostics_before, target->sig)) {
        report_uninferred(body, call, target, &instance);
        if (target->constructor && instance.unbound.len != 0 && instance.args.len == target->vars.len) {
          /* what the arguments did fix stays: `ok(1)` is a Result whose error type is the invalid marker */
          partial = ms_ty_result(&body->program->types, ms_ty_subst(&body->program->types, target->sig, target->vars.ptr,
                                                                    instance.args.ptr, instance.args.len));
        }
        /* the call's failure comes before the callbacks it could not type */
        MsCheckDiagList *list = &body->program->diagnostics;
        if (list->len > diagnostics_before + 1) {
          const MsCheckDiag last = list->ptr[list->len - 1];
          memmove(list->ptr + diagnostics_before + 1, list->ptr + diagnostics_before,
                  (list->len - 1 - diagnostics_before) * sizeof last);
          list->ptr[diagnostics_before] = last;
        }
      }
    }
  }
  MsTy result = record_call(body, call, target, sig, &instance.args, matched);
  body_set_type(body, call->u.call.callee->id, sig);
  ms_instance_free(&instance);
  ms_ty_list_free(&typed);
  return instantiated ? result : partial;
}

/* The callee as written: `f`, `values.map`; empty for any other expression. */
static void append_callee_name(const Body *body, MsStrBuild *out, const MsExpr *callee) {
  if (callee->kind == MS_E_NAME) {
    ms_strbuild_append(out, ms_names_span(body->program->names, callee->u.sym));
  } else if (callee->kind == MS_E_MEMBER) {
    append_callee_name(body, out, callee->u.member.left);
    ms_strbuild_append_text(out, ms_strbuild_length(out) != 0 ? "." : "");
    ms_strbuild_append(out, ms_names_span(body->program->names, callee->u.member.name));
  } else if (callee->kind == MS_E_APPLY) {
    append_callee_name(body, out, callee->u.apply.left);
  }
}

/* `Int("1")`: a primitive type is built from a literal or a standard function, not called. */
static bool report_builtin_constructor(Body *body, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_NAME || body_find_local(body, callee->u.sym) != NULL) {
    return false;
  }
  if (body_find_symbol(body, callee->u.sym) != NULL ||
      ms_builtin_primitive(ms_names_span(body->program->names, callee->u.sym)) == MS_BUILTIN_NONE) {
    return false;
  }
  const MsSpan name = ms_names_span(body->program->names, callee->u.sym);
  for (size_t index = 0; index < body->program->diagnostics.len; index++) { /* a declaration reusing the name is rejected */
    const MsCheckDiag *diag = &body->program->diagnostics.ptr[index];
    const MsSpan message = ms_string_span(&diag->message);
    MsStrBuild reused = ms_strbuild_new();
    ms_strbuild_append_text(&reused, "duplicate or intrinsic name ");
    ms_strbuild_append(&reused, name);
    ms_strbuild_append_text(&reused, ";");
    const bool match = diag->module == body->module && ms_span_starts_with(message, ms_strbuild_span(&reused));
    ms_strbuild_free(&reused);
    if (match) {
      return true;
    }
  }
  if (body_reports(body) && !body->quiet) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "this type has no source constructor: ");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, " is built in; write a literal or call a standard function that returns it");
    if (ms_span_is_text(name, "String")) {
      ms_strbuild_append_text(&text, "; make text with interpolation f\"{value}\" or value.to_string()");
    } else if (ms_span_is_text(name, "Int")) {
      ms_strbuild_append_text(&text, "; parse text with text.parse_int() (Int?); Float has truncate_to_int()");
    } else if (ms_span_is_text(name, "Float")) {
      ms_strbuild_append_text(&text, "; convert an Int with value.to_float(); parse text with parse_float (import parse_float "
                                     "from \"@std/math/math.ms\")");
    }
    ms_check_report(body->program, body->module, call->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  return true;
}

/* A call whose callee is a value that is not a function. */
static void report_not_callable(Body *body, const MsExpr *call, const Target *target) {
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    (void)body_expr(body, call->u.call.args.ptr[index].value, MS_TY_NONE);
  }
  if (!body_reports(body) || body->quiet) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  if (target->name.len != 0) {
    ms_strbuild_append(&text, target->name);
    ms_strbuild_append_text(&text, " is not a function");
  } else {
    ms_strbuild_append_text(&text, "callee is not a function");
  }
  ms_strbuild_append_text(&text, " (it has type ");
  ms_ty_show(&text, body->program->names, &body->program->types, target->sig);
  ms_strbuild_append_text(&text, "); only functions and methods can be called, so remove the (...) or call a function instead");
  ms_check_report(body->program, body->module, call->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* `I(value)` where I is an interface: the value already passes wherever I is expected. Reports and answers true. */
static bool report_interface_build(Body *body, const MsExpr *call, const Target *target) {
  MsTyTable *types = &body->program->types;
  if (target->nominal == MS_TY_NONE || ms_ty_kind(types, target->nominal) != MS_TY_CONTRACT) {
    return false;
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    (void)body_expr(body, call->u.call.args.ptr[index].value, MS_TY_NONE);
  }
  if (body_reports(body) && !body->quiet) {
    const MsDef *def = body_def(body, target->nominal);
    MsTy shown = target->nominal;
    if (def != NULL && target->explicit_args.len == def->variables.len && def->variables.len != 0) {
      shown = ms_ty_subst(types, target->nominal, def->variables.ptr, target->explicit_args.ptr, def->variables.len);
    }
    MsStrBuild text = ms_strbuild_new();
    ms_ty_show(&text, body->program->names, types, shown);
    ms_strbuild_append_text(&text, " is an interface and cannot be constructed; a type whose methods match ");
    ms_ty_show(&text, body->program->names, types, shown);
    ms_strbuild_append_text(&text, " passes wherever ");
    ms_ty_show(&text, body->program->names, types, shown);
    ms_strbuild_append_text(&text, " is expected, so pass the value directly");
    ms_check_report(body->program, body->module, call->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  return true;
}

/* `A()` where A is a constant: the parentheses are the mistake. Reports it and answers true. */
static bool report_constant_call(Body *body, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  const MsSymbol *symbol = callee->kind == MS_E_NAME && body_find_local(body, callee->u.sym) == NULL
                               ? body_find_symbol(body, callee->u.sym)
                               : NULL;
  if (symbol == NULL || symbol->decl == NULL || symbol->decl->kind != MS_D_CONST) {
    return false;
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    (void)body_expr(body, call->u.call.args.ptr[index].value, MS_TY_NONE);
  }
  if (body_reports(body) && !body->quiet) {
    MsStrBuild text = ms_strbuild_new();
    const MsSpan name = ms_names_span(body->program->names, callee->u.sym);
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, " is a constant, not a function; remove the parentheses and write ");
    ms_strbuild_append(&text, name);
    ms_check_report(body->program, body->module, call->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  return true;
}

/* `some(value)`: an Optional has no `some` constructor; a plain value converts where a `T?` is expected. The
 * arguments are read so their own errors still show. */
static bool report_optional_some(Body *body, const MsExpr *call, const Target *target) {
  const MsExpr *callee = call->u.call.callee;
  if (target->ref.kind != MS_REF_CASE || callee->kind != MS_E_NAME ||
      !ms_span_is_text(ms_names_span(body->program->names, callee->u.sym), "some") ||
      !ms_ty_is(&body->program->types, target->ref.owner, MS_BUILTIN_Optional)) {
    return false;
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    (void)body_expr(body, call->u.call.args.ptr[index].value, MS_TY_NONE);
  }
  if (body_reports(body) && !body->quiet) {
    ms_check_report(body->program, body->module, call->pos, MS_CHECK_TYPE,
                    ms_string_static(ms_span_of_text("there is no some(...); a plain value converts where a T? is "
                                                     "expected, so pass it directly, or annotate the binding, e.g. "
                                                     "x Int? := 5")));
  }
  return true;
}

MsTy body_call(Body *body, const MsExpr *expr, MsTy expected) {
  Target target = {0};
  MsTy result = MS_TY_NONE;
  const size_t diagnostics_before = body->program->diagnostics.len;
  const MsExpr *callee = expr->u.call.callee;
  if (body_present_get(body, expr, &result)) {
    return result;
  }
  target.name_text = ms_strbuild_new();
  append_callee_name(body, &target.name_text, callee);
  target.name = ms_strbuild_span(&target.name_text);
  target.nargs = expr->u.call.args.len;
  if (body_resolve_target(body, callee, expected, &target)) {
    if (report_optional_some(body, expr, &target)) {
      body_target_free(&target);
      return MS_TY_NONE;
    }
    body_deny_opaque_build(body, expr, &target);
    body_reject_nullable_method(body, expr, &target);
    const size_t count = ms_ty_param_count(&body->program->types, target.sig);
    Matched matched = {.slot = MS_ARENA_NEW_ARRAY(&body->program->arena, int32_t, count + 1),
                       .state = MS_ARENA_NEW_ARRAY(&body->program->arena, uint8_t, expr->u.call.args.len + 1),
                       .count = count};
    MsTy *arg_tys = MS_ARENA_NEW_ARRAY(&body->program->arena, MsTy, count + 1);
    MsTy *bound = MS_ARENA_NEW_ARRAY(&body->program->arena, MsTy, target.vars.len + 1);
    for (size_t index = 0; index < target.vars.len; index++) {
      bound[index] = index < target.explicit_args.len ? target.explicit_args.ptr[index] : MS_TY_NONE;
    }
    for (size_t index = 0; index < count; index++) {
      matched.slot[index] = -1;
    }
    match_args(body, &target, expr, &matched);
    MsTy hint[16] = {0};
    result_hint(body, &target, expected, hint);
    target.journal = body->typed.len;
    target.calls_mark = body->facts->calls.len;
    type_args(body, &target, expr, &matched, arg_tys, bound, hint);
    MsTy *shown = MS_ARENA_NEW_ARRAY(&body->program->arena, MsTy, target.vars.len + 1);
    for (size_t index = 0; index < target.vars.len; index++) { /* the expected result fixes what the arguments left open */
      shown[index] = bound[index] != MS_TY_NONE || index >= 16 ? bound[index] : hint[index];
    }
    matched.bound = shown;
    body_report_arguments(body, &target, expr, &matched);
    result = finish_call(body, expr, &target, arg_tys, &matched, expected, diagnostics_before);
    /* an argument that already disagreed with the expected result's type is the one error: the call has that type */
    if (target.constructor && expected != MS_TY_NONE && body->program->diagnostics.len > diagnostics_before &&
        result != MS_TY_NONE && ms_ty_is(&body->program->types, result, MS_BUILTIN_Result) &&
        !ms_ty_has_variable(&body->program->types, expected)) {
      const MsTyTable *types = &body->program->types;
      MsTy plain = expected;
      if (ms_ty_is(types, plain, MS_BUILTIN_Optional) && ms_ty_arg_count(types, plain) == 1) {
        plain = ms_ty_args(types, plain)[0];
      }
      result = ms_ty_is(types, plain, MS_BUILTIN_Result) ? plain : result;
    }
  } else if (target.sig != MS_TY_NONE && !ms_ty_is_invalid(&body->program->types, target.sig) &&
             ms_ty_kind(&body->program->types, target.sig) != MS_TY_FUNCTION) {
    report_not_callable(body, expr, &target);
  } else if (report_interface_build(body, expr, &target)) {
    /* an interface is not constructed: reported, and the arguments are read */
  } else if (report_constant_call(body, expr)) {
    /* a constant is not called: reported, and the arguments are read */
  } else if (report_builtin_constructor(body, expr)) {
    /* a built-in type has no source constructor: reported, and the arguments are left alone */
  } else {
    body_fix_removed_nullable_call(body, expr);
    const bool quiet = body->quiet; /* an unknown callee gives its arguments no context to report against */
    for (uint32_t index = 0; index < expr->u.call.args.len; index++) {
      const MsExpr *value = expr->u.call.args.ptr[index].value;
      /* a method of an unresolved receiver still reads its callbacks, which have no context to take parameters from */
      body->quiet = quiet ? true : !(value->kind == MS_E_LAMBDA && callee->kind == MS_E_MEMBER);
      (void)body_expr(body, value, MS_TY_NONE);
    }
    body->quiet = quiet;
  }
  body_target_free(&target);
  return result;
}
