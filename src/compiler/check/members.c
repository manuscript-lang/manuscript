/* compiler/check/members.c: the diagnostic for a member a value does not have.
 *
 * The message names the receiver, then the hint the oracle gives first of: an optional or result used as its
 * payload, a near miss, the members the type has (all of them when there are at most 40, else those that start
 * with the same letter). */
#include "compiler/check/body.h"
#include "compiler/check/methods.h"
#include "compiler/check/suggest.h"

/* The fields, operations and methods of `receiver`. */
static void member_names(Body *body, MsTy receiver, MsSpanList *out) {
  MsCheckProgram *program = body->program;
  const size_t first = out->len;
  const MsDef *def = body_def(body, receiver);
  if (def != NULL && ms_ty_kind(&program->types, receiver) == MS_TY_TYPE) {
    for (size_t index = 0; index < def->fields.len; index++) {
      ms_span_list_push(out, ms_names_span(program->names, def->fields.ptr[index].name));
    }
  }
  for (size_t index = 0; def != NULL && index < def->operations.len; index++) {
    ms_span_list_push(out, ms_names_span(program->names, def->operations.ptr[index].name));
  }
  ms_check_native_names(program, receiver, out);
  for (size_t index = 0; index < program->methods.len; index++) {
    const MsMethodEntry *entry = &program->methods.ptr[index];
    MsTyList bound = {0};
    for (uint32_t at = 0; at < entry->shared; at++) {
      ms_ty_list_push(&bound, MS_TY_NONE);
    }
    if (ms_check_unify(&program->types, entry->receiver, receiver, entry->variables.ptr, entry->shared, bound.ptr)) {
      ms_span_list_push(out, ms_names_span(program->names, entry->name));
    }
    ms_ty_list_free(&bound);
  }
  /* A primitive has no `clone` member (it is copied), and a String is its own text, so `to_string` is not listed. */
  const bool primitive = ms_ty_kind(&program->types, receiver) == MS_TY_PRIMITIVE;
  const bool text = ms_ty_is(&program->types, receiver, MS_BUILTIN_String);
  size_t kept = first;
  for (size_t index = first; index < out->len; index++) {
    if (!(primitive && ms_span_is_text(out->ptr[index], "clone")) &&
        !(text && ms_span_is_text(out->ptr[index], "to_string"))) {
      out->ptr[kept++] = out->ptr[index];
    }
  }
  out->len = kept;
}

/* Whether `names` holds `name`. */
static bool has_name(const MsSpanList *names, MsSpan name) {
  for (size_t index = 0; index < names->len; index++) {
    if (ms_span_equal(names->ptr[index], name)) {
      return true;
    }
  }
  return false;
}

static size_t unique_count(const MsSpanList *names) {
  size_t count = 0;
  for (size_t index = 0; index < names->len; index++) {
    bool seen = false;
    for (size_t at = 0; at < index && !seen; at++) {
      seen = ms_span_equal(names->ptr[at], names->ptr[index]);
    }
    count += seen ? 0 : 1;
  }
  return count;
}

static void show(const Body *body, MsStrBuild *out, MsTy ty) {
  ms_ty_show(out, body->program->names, &body->program->types, ty);
}

/* The hint for an optional or result whose payload has the member: unwrap it first. */
static bool payload_hint(Body *body, MsTy receiver, MsSpan name, MsStrBuild *out) {
  const MsTyTable *types = &body->program->types;
  const bool optional = ms_ty_is(types, receiver, MS_BUILTIN_Optional);
  if ((!optional && !ms_ty_is(types, receiver, MS_BUILTIN_Result)) || ms_ty_arg_count(types, receiver) == 0) {
    return false;
  }
  const MsTy payload = ms_ty_args(types, receiver)[0];
  MsSpanList names = {0};
  member_names(body, payload, &names);
  const bool has = has_name(&names, name);
  ms_span_list_free(&names);
  if (!has) {
    return false;
  }
  ms_strbuild_append_text(out, optional ? "; the value is an Optional of " : "; the value is a Result of ");
  show(body, out, payload);
  ms_strbuild_append_text(out, ", which has ");
  ms_strbuild_append(out, name);
  ms_strbuild_append_text(out, ": unwrap it first with ");
  ms_strbuild_append_text(out, optional ? "`if value := x:` or x.get_or(default)"
                                        : "`x?` inside a fn that returns Result, `if value := x:` or x.get_or(default)");
  return true;
}

static void append_available(MsStrBuild *out, const MsSpanList *names, MsSpan name) {
  const size_t total = unique_count(names);
  if (total <= 40) {
    ms_strbuild_append_text(out, "; available: ");
    ms_suggest_list(out, names, 40);
    return;
  }
  MsSpanList same = {0};
  for (size_t index = 0; index < names->len; index++) {
    if (name.len != 0 && names->ptr[index].len != 0 && names->ptr[index].ptr[0] == name.ptr[0]) {
      ms_span_list_push(&same, names->ptr[index]);
    }
  }
  if (same.len != 0) {
    ms_strbuild_append_text(out, "; available starting with '");
    ms_strbuild_append(out, (MsSpan){name.ptr, 1});
    ms_strbuild_append_text(out, "': ");
    ms_suggest_list(out, &same, same.len);
    ms_strbuild_printf(out, "; %zu members in total", total);
  } else {
    ms_strbuild_append_text(out, "; available: ");
    ms_suggest_list(out, names, 40);
  }
  ms_span_list_free(&same);
}

void body_report_unknown_member(Body *body, const MsExpr *member, MsTy receiver) {
  const MsTyTable *types = &body->program->types;
  if (body->module >= body->program->user_modules || body->quiet || holds_invalid(types, receiver, 6) ||
      ms_ty_kind(types, receiver) == MS_TY_FUNCTION) {
    return;
  }
  const MsSpan name = ms_names_span(body->program->names, member->u.member.name);
  const MsTyVariable *variable =
      ms_ty_kind(types, receiver) == MS_TY_VARIABLE ? ms_ty_variable(&body->program->types, receiver) : NULL;
  if ((name.len != 0 && name.ptr[0] == '[') || (variable != NULL && variable->bounds.len != 0) ||
      ms_check_standard_operation(body->program, member->u.member.name)) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "unknown or ambiguous member ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, " on ");
  show(body, &text, receiver);
  MsSpanList names = {0};
  member_names(body, receiver, &names);
  if (!payload_hint(body, receiver, name, &text)) {
    if (ms_suggest_did_you_mean(&text, name, &names)) {
      if (unique_count(&names) <= 40) {
        append_available(&text, &names, name);
      }
    } else if (names.len != 0) {
      append_available(&text, &names, name);
    } else {
      if (ms_ty_kind(types, receiver) == MS_TY_VARIABLE) {
        ms_strbuild_append_text(&text, "; ");
        show(body, &text, receiver);
        ms_strbuild_append_text(&text, " has no bound, so it has no operations: bound it where it is declared, as in "
                                       "`fn f[");
        show(body, &text, receiver);
        ms_strbuild_append_text(&text, ": Contract]` for a function or `fn var Repository[");
        show(body, &text, receiver);
        ms_strbuild_append_text(&text, ": Contract].add` for a method of a generic type");
      } else {
        ms_strbuild_append_text(&text, "; this type has no fields or operations");
      }
    }
  }
  ms_span_list_free(&names);
  ms_check_report(body->program, body->module, member->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
}
