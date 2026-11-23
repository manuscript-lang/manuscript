/* compiler/check/call_report.c: the diagnostics of matching a call's arguments to the callee's parameters.
 *
 * A positional argument beyond the last parameter, a label that names no parameter, a label that names a
 * parameter twice, and a parameter left without an argument. The unmatched arguments are still typed so their
 * own diagnostics and facts exist. */
#include "compiler/check/call_internal.h"
#include "compiler/check/suggest.h"

static MsPos advance(MsPos pos, size_t bytes) {
  return (MsPos){pos.offset + (uint32_t)bytes, pos.line, pos.column + (uint32_t)bytes};
}

static void report_text(Body *body, MsPos pos, size_t length, MsStrBuild *text) {
  ms_check_report(body->program, body->module, pos, MS_CHECK_TYPE, ms_strbuild_finish(text));
  if (length != 0) {
    ms_check_attach_end(body->program, advance(pos, length));
  }
}

MsName target_param_name(const Body *body, const Target *target, size_t index) {
  return target->ast != NULL && index < target->ast->len ? target->ast->ptr[index]->name
                                                          : ms_ty_params(&body->program->types, target->sig)[index].name;
}

/* Whether the callee is a local or parameter declared with a written function type, whose parameters carry no labels. */
static bool written_fn_value(const Body *body, const Target *target) {
  if (target->ref.kind != MS_REF_LOCAL && target->ref.kind != MS_REF_PARAM) {
    return false;
  }
  for (size_t index = 0; index < body->locals.len; index++) {
    const MsLocal *local = &body->locals.ptr[index];
    if (local->site == target->ref.decl.node && local->kind == target->ref.kind) {
      return local->written_fn;
    }
  }
  return false;
}

bool target_positional(const Body *body, const Target *target, size_t index) {
  /* A lambda or method value keeps its parameters' names (the local's `ast`); any other function value has none. */
  const bool value = target->ast == NULL && (target->ref.kind == MS_REF_LOCAL || target->ref.kind == MS_REF_PARAM ||
                                             target->ref.kind == MS_REF_NONE);
  return value || (ms_ty_params(&body->program->types, target->sig)[index].flags & MS_PARAM_POSITIONAL) != 0;
}

static MsSpan param_name(const Body *body, const Target *target, size_t index) {
  return ms_names_span(body->program->names, target_param_name(body, target, index));
}

/* `T`, with a type variable no argument fixed yet written `_`. */
static void append_param_type(Body *body, MsStrBuild *out, MsTy ty) {
  MsStrBuild shown = ms_strbuild_new();
  ms_ty_show(&shown, body->program->names, &body->program->types, ty);
  const MsSpan text = ms_strbuild_span(&shown);
  MsSpan rest = text;
  size_t at = 0;
  while (ms_span_find(rest, ms_span_of_text("<invalid>"), &at) || ms_span_find(rest, ms_span_of_text("<unknown>"), &at)) {
    ms_strbuild_append(out, (MsSpan){rest.ptr, at});
    ms_strbuild_append_text(out, "_");
    rest = (MsSpan){rest.ptr + at + 9, rest.len - at - 9};
  }
  ms_strbuild_append(out, rest);
  ms_strbuild_free(&shown);
}

/* `; function values take positional arguments (T, U), so pass them without labels`, a near miss, or the names. */
static void unknown_hint(Body *body, const Target *target, MsSpan name, MsStrBuild *out) {
  const MsTyTable *types = &body->program->types;
  const size_t count = ms_ty_param_count(types, target->sig);
  MsSpanList names = {0};
  bool all_positional = count != 0;
  for (size_t index = 0; index < count; index++) {
    ms_span_list_push(&names, param_name(body, target, index));
    all_positional = all_positional && target_positional(body, target, index);
  }
  if (all_positional) {
    ms_strbuild_append_text(out, "; function values take positional arguments (");
    for (size_t index = 0; index < count; index++) {
      ms_strbuild_append_text(out, index != 0 ? ", " : "");
      append_param_type(body, out, ms_ty_params(types, target->sig)[index].ty);
    }
    ms_strbuild_append_text(out, "), so pass them without labels");
  } else if (!ms_suggest_did_you_mean(out, name, &names)) {
    if (count == 0) {
      ms_strbuild_append_text(out, "; this call takes no arguments");
    } else {
      ms_strbuild_append_text(out, "; parameters");
      ms_strbuild_append_text(out, target->name.len != 0 ? " of " : "");
      ms_strbuild_append(out, target->name);
      ms_strbuild_append_text(out, ": ");
      ms_suggest_list(out, &names, 12);
    }
  }
  ms_span_list_free(&names);
}

static void report_extra(Body *body, const Target *target, const MsExpr *call, const MsArg *arg, bool *hinted) {
  const MsExpr *callee = call->u.call.callee;
  const bool get = callee->kind == MS_E_MEMBER &&
                   ms_span_is_text(ms_names_span(body->program->names, callee->u.member.name), "get");
  MsStrBuild text = ms_strbuild_new();
  if (get && !*hinted) {
    *hinted = true;
    ms_strbuild_append_text(&text, "too many positional arguments; `get` takes no fallback, write `get_or` to supply "
                                   "one; did you mean 'get_or'?");
    report_text(body, call->pos, 3, &text);
  } else if (!*hinted) {
    ms_strbuild_append_text(&text, "too many positional arguments; every parameter is already supplied, so remove "
                                   "this argument");
    report_text(body, arg->pos, 0, &text);
  }
  (void)target;
  ms_strbuild_free(&text);
}

static void report_labelled(Body *body, const Target *target, const MsArg *arg, ArgState state) {
  const MsSpan name = ms_names_span(body->program->names, arg->name);
  MsStrBuild text = ms_strbuild_new();
  if (state == ARG_DUPLICATE) {
    ms_strbuild_append_text(&text, "duplicate argument ");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, "; pass each argument once");
  } else {
    ms_strbuild_append_text(&text, "unknown argument ");
    ms_strbuild_append(&text, name);
    unknown_hint(body, target, name, &text);
  }
  report_text(body, arg->pos, 0, &text);
  ms_strbuild_free(&text);
}

/* Whether a call may leave `param` out: it has a default, or its type is optional (a `T?` parameter defaults to none). */
bool body_param_omittable(const Body *body, const MsParam *param) {
  if (param->def != NULL) {
    return true;
  }
  const MsTypeRef *ty = param->ty;
  return ty != NULL && ty->kind == MS_TYPE_NAMED && ty->args.len == 1 &&
         ms_span_is_text(ms_names_span(body->program->names, ty->name), "Optional");
}

/* A parameter a call may leave out: lifted, declared with a default, or the only payload of a case, a Void. */
static bool omittable(const Body *body, const Target *target, const MsTyParam *param, size_t index) {
  const MsTyTable *types = &body->program->types;
  const bool void_payload = target->ref.kind == MS_REF_CASE && ms_ty_param_count(types, target->sig) == 1 &&
                            (ms_ty_is(types, param->ty, MS_BUILTIN_Void) || ms_ty_kind(types, param->ty) == MS_TY_VARIABLE);
  return void_payload || (param->flags & MS_PARAM_LIFTED) != 0 ||
         (target->ast != NULL ? index < target->ast->len && body_param_omittable(body, target->ast->ptr[index])
                              : ms_ty_is(types, param->ty, MS_BUILTIN_Optional));
}

static void report_missing(Body *body, const Target *target, const MsExpr *call, const Matched *matched, size_t index) {
  const MsTyParam *param = &ms_ty_params(&body->program->types, target->sig)[index];
  /* the type as far as the other arguments fix it, a type argument nothing fixed yet written `_` */
  const MsTy shown = matched->bound != NULL && target->vars.len != 0
                         ? ms_ty_subst(&body->program->types, param->ty, target->vars.ptr, matched->bound, target->vars.len)
                         : param->ty;
  if ((shown == MS_TY_NONE || ms_ty_has_variable(&body->program->types, shown)) && target->vars.len != 0) {
    return; /* a type argument nothing fixes is reported as one that cannot be inferred */
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "missing argument ");
  const bool positional = target_positional(body, target, index);
  if (positional) {
    ms_strbuild_printf(&text, "%zu", index + 1);
  } else {
    ms_strbuild_append(&text, param_name(body, target, index));
  }
  ms_strbuild_append_text(&text, ": ");
  append_param_type(body, &text, shown);
  if (target->name.len != 0) {
    ms_strbuild_append_text(&text, " in call to ");
    ms_strbuild_append(&text, target->name);
  }
  if (positional) {
    ms_strbuild_append_text(&text, "; pass it positionally, without a label");
  } else {
    ms_strbuild_append_text(&text, "; add '");
    ms_strbuild_append(&text, param_name(body, target, index));
    ms_strbuild_append_text(&text, ": <");
    append_param_type(body, &text, shown);
    ms_strbuild_append_text(&text, ">'");
  }
  report_text(body, call->pos, 0, &text);
  ms_strbuild_free(&text);
}

void body_report_arguments(Body *body, const Target *target, const MsExpr *call, const Matched *matched) {
  const bool report = body_reports(body) && !body->quiet && !target->builtin;
  bool hinted = false;
  for (uint32_t at = 0; at < call->u.call.args.len; at++) {
    const MsArg *arg = &call->u.call.args.ptr[at];
    const ArgState state = (ArgState)matched->state[at];
    if (state == ARG_MATCHED) {
      continue;
    }
    if (!report) {
      (void)state;
    } else if (state == ARG_EXTRA) {
      report_extra(body, target, call, arg, &hinted);
    } else {
      report_labelled(body, target, arg, state);
    }
    (void)body_expr(body, arg->value, MS_TY_NONE);
  }
  const MsTyTable *types = &body->program->types;
  const bool written = written_fn_value(body, target);
  for (size_t index = 0; index < matched->count; index++) {
    const MsTyParam *param = &ms_ty_params(types, target->sig)[index];
    const MsTyKind kind = ms_ty_kind(types, param->ty);
    /* a label that names the parameter counts as supplying it even when the label is rejected (function values) */
    bool named = false;
    for (uint32_t at = 0; !written && at < call->u.call.args.len; at++) {
      named = call->u.call.args.ptr[at].has_name && call->u.call.args.ptr[at].name == target_param_name(body, target, index);
      if (named) {
        break;
      }
    }
    if (report && !named && matched->slot[index] < 0 && param->ty != MS_TY_NONE && kind != MS_TY_INVALID && !omittable(body, target, param, index)) {
      report_missing(body, target, call, matched, index);
    }
  }
}
