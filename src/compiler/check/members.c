/* compiler/check/members.c: the diagnostic for a member a value does not have.
 *
 * The message names the receiver, then the hint the oracle gives first of: an optional or result used as its
 * payload, a near miss, the members the type has (all of them when there are at most 40, else those that start
 * with the same letter). */
#include "compiler/syntax/parse.h"
#include "compiler/check/body.h"
#include "compiler/check/bounds.h"
#include "compiler/check/call_internal.h"
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
    if (ms_check_unify(&program->types, entry->receiver, receiver, entry->variables.ptr, entry->shared, bound.ptr) &&
        ms_check_bounds_satisfied(program, entry->variables.ptr, entry->shared, bound.ptr)) {
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
  ms_strbuild_append_text(out, optional ? "`if x != null { ... }` or `x or default`"
                                        : "`x?` inside a fn that returns Result, `if value := x { ... }` or x.get_or(default)");
  return true;
}

static bool name_in_list(MsSpan name, const char *const *names) {
  for (size_t index = 0; names[index] != NULL; index++) {
    if (ms_span_is_text(name, names[index])) {
      return true;
    }
  }
  return false;
}

#define NAME_IN(name, ...) name_in_list(name, (const char *const[]){__VA_ARGS__, NULL})

/* Habits from other languages, in the order the oracle tries them: a name the module declares as a function, an
 * optional or result read as in other languages, `is_none` on a value that cannot be none. */
static bool habit_before_payload(Body *body, MsTy receiver, MsName id, MsSpan name, MsStrBuild *out) {
  const MsTyTable *types = &body->program->types;
  const MsSymbol *symbol = body_find_symbol(body, id);
  if (symbol != NULL && symbol->kind == MS_SYMBOL_FN) {
    ms_strbuild_append_text(out, "; ");
    ms_strbuild_append(out, name);
    ms_strbuild_append_text(out, " is a function here, not a method of ");
    show(body, out, receiver);
    ms_strbuild_append_text(out, ": call it as ");
    ms_strbuild_append(out, name);
    ms_strbuild_append_text(out, "(value) with the value as an argument, or declare it as a method with `fn ");
    show(body, out, receiver);
    ms_strbuild_append_text(out, ".");
    ms_strbuild_append(out, name);
    ms_strbuild_append_text(out, "()`");
    return true;
  }
  const bool optional = ms_ty_is(types, receiver, MS_BUILTIN_Optional);
  const bool result = ms_ty_is(types, receiver, MS_BUILTIN_Result);
  const char *fix = NULL;
  if (optional && (NAME_IN(name, "unwrap", "expect", "value", "unwrap_or") || NAME_IN(name, "unwrap_or_else", "or_default", "unwrap_or_default"))) {
    fix = "read an Optional with x.get_or(default), x.get_or_else(create) for a lazy fallback, or `if value := x { ... }` to test and unwrap; x.get() with no default faults on null";
  } else if (optional && NAME_IN(name, "map_or", "is_some_and", "flatten", "filter")) {
    fix = "use map, and_then, is_some, or `if value := x { ... }`";
  } else if (result && (NAME_IN(name, "unwrap", "expect", "unwrap_or", "unwrap_or_else") || NAME_IN(name, "unwrap_or_default"))) {
    fix = "read a Result with `x?` inside a fn that returns Result, x.get_or(default), x.get_or_else(create) for a lazy fallback, or `if value := x { ... }`";
  } else if (result && NAME_IN(name, "unwrap_err", "err", "ok")) {
    fix = "inspect a Result with `if value := x { ... }` or is_error()";
  }
  if (fix != NULL) {
    ms_strbuild_append_text(out, "; ");
    ms_strbuild_append_text(out, fix);
    return true;
  }
  if (!optional && !result && NAME_IN(name, "is_none", "is_some")) {
    ms_strbuild_append_text(out, "; a value of type ");
    show(body, out, receiver);
    ms_strbuild_append_text(out, " is never null here. List.get(i) returns the element and faults when i is out of range: use xs.get_or(i, default) for a fallback, or check i against xs.length() first");
    return true;
  }
  return false;
}

static const char *const MEMBER_SYNONYMS[][4] = {
    {"byte_length", "length"}, {"len", "length", "scalar_length"}, {"size", "length", "scalar_length"},
    {"count", "length", "scalar_length"}, {"length", "scalar_length"}, {"push", "append", "add"}, {"add", "append"},
    {"insert", "append", "add"}, {"delete", "remove"}, {"decode", "to_string"}, {"toString", "to_string"},
    {"to_text", "to_string"}, {"includes", "contains"}, {"has", "contains"}, {"indexOf", "index_of"},
    {"find_index", "index_of"}, {"reduce", "fold"}, {"each", "for_each"}, {"substring", "slice", "view"},
    {"substr", "slice", "view"}, {"charAt", "scalar_at"}, {"char_at", "scalar_at"}, {"sort", "sorted"},
    {"trim_left", "trim_start"}, {"trim_right", "trim_end"}, {"to_upper", "upper"}, {"to_lower", "lower"},
    {"to_uppercase", "upper"}, {"to_lowercase", "lower"}, {"toUpperCase", "upper"}, {"toLowerCase", "lower"},
    {"trimStart", "trim_start"}, {"trimEnd", "trim_end"}, {"to_int", "parse_int", "truncate_to_int"},
    {"replace_all", "replace"}, {"replace_n", "replace", "replace_first"},
};

/* Appends `'x'` for each name the receiver has that the written name is a habit for, joined by " or ". */
static bool synonym_hint(MsSpan name, const MsSpanList *names, MsStrBuild *out) {
  MsStrBuild snake = ms_strbuild_new();
  for (size_t index = 0; index < name.len; index++) {
    const char c = (char)name.ptr[index];
    if (c >= 'A' && c <= 'Z') {
      ms_strbuild_append_text(&snake, "_");
      const char lower[2] = {(char)(c - 'A' + 'a'), 0};
      ms_strbuild_append_text(&snake, lower);
    } else {
      const char same[2] = {c, 0};
      ms_strbuild_append_text(&snake, same);
    }
  }
  MsStrBuild found = ms_strbuild_new();
  size_t count = 0;
  const bool has_upper = ms_strbuild_length(&snake) != name.len;
  if (has_upper && has_name(names, ms_strbuild_span(&snake))) {
    ms_strbuild_append_text(&found, "'");
    ms_strbuild_append(&found, ms_strbuild_span(&snake));
    ms_strbuild_append_text(&found, "'");
    count++;
  }
  for (size_t row = 0; row < MS_COUNT_OF(MEMBER_SYNONYMS); row++) {
    if (!ms_span_is_text(name, MEMBER_SYNONYMS[row][0])) {
      continue;
    }
    for (size_t at = 1; at < 4 && MEMBER_SYNONYMS[row][at] != NULL; at++) {
      for (size_t index = 0; index < names->len; index++) {
        if (ms_span_is_text(names->ptr[index], MEMBER_SYNONYMS[row][at])) {
          ms_strbuild_append_text(&found, count++ == 0 ? "'" : " or '");
          ms_strbuild_append_text(&found, MEMBER_SYNONYMS[row][at]);
          ms_strbuild_append_text(&found, "'");
        }
      }
    }
  }
  if (count != 0) {
    ms_strbuild_append_text(out, "; did you mean ");
    ms_strbuild_append(out, ms_strbuild_span(&found));
    ms_strbuild_append_text(out, "?");
  }
  ms_strbuild_free(&snake);
  ms_strbuild_free(&found);
  return count != 0;
}

/* The renames and habits that follow the payload hint: `some`/`every`, `Map.set`, then synonyms. */
static bool habit_after_payload(Body *body, MsTy receiver, MsSpan name, const MsSpanList *names, MsStrBuild *out) {
  const MsTyTable *types = &body->program->types;
  const bool collection = ms_ty_is(types, receiver, MS_BUILTIN_List) || ms_ty_is(types, receiver, MS_BUILTIN_Map) ||
                          ms_ty_is(types, receiver, MS_BUILTIN_Set);
  if (collection && (ms_span_is_text(name, "some") || ms_span_is_text(name, "every"))) {
    ms_strbuild_append_text(out, "; ");
    ms_strbuild_append(out, name);
    ms_strbuild_append_text(out, "(predicate) is now ");
    ms_strbuild_append_text(out, ms_span_is_text(name, "some") ? "any" : "all");
    ms_strbuild_append_text(out, "(predicate)");
    return true;
  }
  if (ms_ty_is(types, receiver, MS_BUILTIN_Map) && ms_span_is_text(name, "set")) {
    ms_strbuild_append_text(out, "; write m[key] = value or m.add(key, value) to insert or replace a Map entry; "
                                 "available: ");
    ms_suggest_list(out, names, names->len);
    return true;
  }
  return synonym_hint(name, names, out);
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

/* A method of the receiver's type constructor whose implementation needs a bound the receiver's arguments lack:
 * "max requires Plain to be Comparable; ...". Appends the reason and returns true when it finds one. */
static bool unmet_member_bound(Body *body, MsTy receiver, MsName name, MsStrBuild *out) {
  MsCheckProgram *program = body->program;
  MsTyTable *types = &program->types;
  for (size_t index = 0; index < program->methods.len; index++) {
    const MsMethodEntry *entry = &program->methods.ptr[index];
    if (entry->name != name) {
      continue;
    }
    MsTyList bound = {0};
    for (uint32_t at = 0; at < entry->shared; at++) {
      ms_ty_list_push(&bound, MS_TY_NONE);
    }
    if (!ms_check_unify(types, entry->receiver, receiver, entry->variables.ptr, entry->shared, bound.ptr)) {
      ms_ty_list_free(&bound);
      continue;
    }
    for (uint32_t at = 0; at < entry->shared; at++) {
      const MsTy actual = bound.ptr[at];
      const MsTyVariable *record = ms_ty_variable(types, entry->variables.ptr[at]);
      for (size_t each = 0; actual != MS_TY_NONE && record != NULL && each < record->bounds.len; each++) {
        const MsTy wanted = ms_ty_subst(types, record->bounds.ptr[each], entry->variables.ptr, bound.ptr, entry->shared);
        if (ms_check_implements(program, actual, wanted)) {
          continue;
        }
        ms_strbuild_append_text(out, "; ");
        ms_strbuild_append(out, ms_names_span(program->names, name));
        ms_strbuild_append_text(out, " requires ");
        show(body, out, actual);
        ms_strbuild_append_text(out, " to be ");
        show(body, out, wanted);
        ms_strbuild_append_text(out, "; ");
        if (ms_ty_kind(types, actual) == MS_TY_VARIABLE) {
          ms_strbuild_append_text(out, "declare ");
          show(body, out, actual);
          ms_strbuild_append_text(out, ": ");
          show(body, out, wanted);
          ms_strbuild_append_text(out, " on the enclosing function");
        } else {
          ms_check_unsatisfied_message(program, actual, wanted, "use a type that implements it", out);
        }
        ms_ty_list_free(&bound);
        return true;
      }
    }
    ms_ty_list_free(&bound);
  }
  return false;
}

void body_report_unknown_member(Body *body, const MsExpr *member, MsTy receiver) {
  const MsTyTable *types = &body->program->types;
  if (!body_reports(body) || body->quiet || holds_invalid(types, receiver, 6) ||
      ms_ty_kind(types, receiver) == MS_TY_FUNCTION) {
    return;
  }
  const MsSpan name = ms_names_span(body->program->names, member->u.member.name);
  const MsTyVariable *variable =
      ms_ty_kind(types, receiver) == MS_TY_VARIABLE ? ms_ty_variable(&body->program->types, receiver) : NULL;
  MsStrBuild reason = ms_strbuild_new(); /* a method whose receiver bound is unmet is explained even if the name is standard */
  const bool unmet = unmet_member_bound(body, receiver, member->u.member.name, &reason);
  ms_strbuild_free(&reason);
  if (ms_span_is_text(name, MS_INDEX_SET)) { /* `data[0] = v` on a type with no `set` operation */
    ms_check_report(body->program, body->module, member->pos, MS_CHECK_TYPE,
                    ms_string_from_span(ms_span_of_text("index assignment requires a List[T] or Map[K, V]; Bytes and String are immutable, build a new value instead")));
    return;
  }
  if ((name.len != 0 && name.ptr[0] == '[') || (variable != NULL && variable->bounds.len != 0) ||
      (!unmet && ms_ty_kind(types, receiver) != MS_TY_PRIMITIVE && ms_check_standard_operation(body->program, member->u.member.name, receiver))) {
    return;
  }
  const char *removed = ms_ty_is(types, receiver, MS_BUILTIN_Optional) ? body_removed_nullable_method(name) : NULL;
  if (removed != NULL) {
    MsStrBuild gone = ms_strbuild_new();
    ms_strbuild_append_text(&gone, "a nullable has no method `");
    ms_strbuild_append(&gone, name);
    ms_strbuild_append_text(&gone, "`; write `");
    ms_strbuild_append_text(&gone, removed);
    ms_strbuild_append_text(&gone, "`");
    ms_check_report(body->program, body->module, member->pos, MS_CHECK_TYPE, ms_strbuild_finish(&gone));
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "unknown or ambiguous member ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, " on ");
  show(body, &text, receiver);
  MsSpanList names = {0};
  member_names(body, receiver, &names);
  if (unmet_member_bound(body, receiver, member->u.member.name, &text)) {
    /* the reason is the whole hint */
  } else if (habit_before_payload(body, receiver, member->u.member.name, name, &text)) {
    /* a habit from another language */
  } else if (!payload_hint(body, receiver, name, &text) && !habit_after_payload(body, receiver, name, &names, &text)) {
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
  /* An operation that returns its Result directly has nothing to wait for: drop `.wait()`. */
  const bool wait = ms_ty_is(types, receiver, MS_BUILTIN_Result) && ms_span_is_text(name, "wait");
  if (wait) {
    ms_strbuild_append_text(&text, "; this call returns its Result directly, not a Promise, so drop `.wait()`");
  }
  ms_check_report(body->program, body->module, member->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
  const MsSpan source = body->program->modules.ptr[body->module].source;
  const size_t after = (size_t)member->pos.offset + name.len;
  if (wait && member->pos.offset > 0 && after + 2 <= source.len && source.ptr[after] == '(' &&
      source.ptr[after + 1] == ')') {
    const MsPos from = {member->pos.offset - 1, member->pos.line, member->pos.column - 1};
    const MsPos to = {(uint32_t)after + 2, member->pos.line, member->pos.column + (uint32_t)name.len + 2};
    ms_check_attach_fix(body->program, from, to, ms_string_from_span(ms_span_of_text("")));
  }
}
