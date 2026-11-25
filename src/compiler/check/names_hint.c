/* compiler/check/names_hint.c: the unknown-name diagnostic and its hints (see names_hint.h). */
#include "compiler/check/names_hint.h"

#include "base/chars.h"
#include "compiler/check/names_habit.h"
#include "compiler/check/std_exports.h"

typedef struct Hint {
  MsStrBuild text;     /* after the "unknown binding NAME" part, starting with "; " */
  const char *edit;    /* the spelling replacing the name, or NULL */
  MsStrBuild near_edit; /* the replacement of a "did you mean" hint */
  bool near;
  bool import;
  MsStrBuild statement; /* "import NAME from \"MODULE\"" for an import hint */
} Hint;

MS_LIST_DEFINE(SpanList, span_list, MsSpan)

static bool is_text(MsSpan name, const char *text) {
  return ms_span_is_text(name, text);
}

/* The two hints about `this`/`pass`, which no other lookup precedes. */
static bool keyword_hint(MsSpan name, bool has_self, Hint *hint) {
  if (is_text(name, "this")) {
    ms_strbuild_append_text(&hint->text, has_self ? "; the receiver in a method is 'self'; write self instead of this"
                                                  : "; there is no 'this'; inside a method the receiver is 'self'");
    hint->edit = has_self ? "self" : NULL;
    return true;
  }
  if (is_text(name, "pass")) {
    ms_strbuild_append_text(&hint->text, "; 'pass' is not a keyword, so write 'void' for an empty block or match arm");
    return true;
  }
  return false;
}

/* Whether the type `impl` extends declares a field `name`. */
static bool receiver_has_field(const MsCheckProgram *program, uint32_t module, const MsScopeSite *site,
                               MsName name) {
  if (site->impl == NULL || site->impl->u.impl.receiver == NULL) {
    return false;
  }
  const MsSymbolId *id = ms_scope_get(&program->modules.ptr[module].scope, site->impl->u.impl.receiver->name);
  if (id == NULL || program->symbols.ptr[*id].decl == NULL || program->symbols.ptr[*id].decl->kind != MS_D_TYPE) {
    return false;
  }
  const MsParams fields = program->symbols.ptr[*id].decl->u.type.fields;
  for (uint32_t index = 0; index < fields.len; index++) {
    if (fields.ptr[index]->name == name) {
      return true;
    }
  }
  return false;
}

static void collect_value_names(const MsCheckProgram *program, uint32_t module, const MsBindingList *scope,
                                SpanList *names) {
  for (size_t index = 0; index < scope->len; index++) {
    span_list_push(names, ms_names_span(program->names, scope->ptr[index].name));
  }
  const MsModuleInfo *info = &program->modules.ptr[module];
  size_t cursor = 0;
  MsName key = 0;
  MsSymbolId *id = NULL;
  while (ms_scope_next(&info->scope, &cursor, &key, &id)) {
    if (program->symbols.ptr[*id].kind == MS_SYMBOL_FN) {
      span_list_push(names, ms_names_span(program->names, key));
    }
  }
  cursor = 0;
  while (ms_scope_next(&info->imports, &cursor, &key, &id)) {
    if (*id != 0 && program->symbols.ptr[*id].kind == MS_SYMBOL_FN) {
      span_list_push(names, ms_names_span(program->names, key));
    }
  }
  span_list_push(names, ms_span_of_text("print"));
  span_list_push(names, ms_span_of_text("ok_or"));
}

static size_t edit_distance(MsSpan a, MsSpan b) {
  enum { LIMIT = 64 };
  if (a.len > LIMIT || b.len > LIMIT) {
    return LIMIT;
  }
  size_t row[LIMIT + 1];
  for (size_t j = 0; j <= b.len; j++) {
    row[j] = j;
  }
  for (size_t i = 1; i <= a.len; i++) {
    size_t diagonal = row[0];
    row[0] = i;
    for (size_t j = 1; j <= b.len; j++) {
      const size_t above = row[j];
      const size_t cost = ms_ascii_to_lower(a.ptr[i - 1]) != ms_ascii_to_lower(b.ptr[j - 1]) ? 1 : 0;
      size_t best = diagonal + cost;
      best = above + 1 < best ? above + 1 : best;
      best = row[j - 1] + 1 < best ? row[j - 1] + 1 : best;
      row[j] = best;
      diagonal = above;
    }
  }
  return row[b.len];
}

static bool starts_with_nocase(MsSpan text, MsSpan prefix) {
  if (text.len < prefix.len) {
    return false;
  }
  for (size_t index = 0; index < prefix.len; index++) {
    if (ms_ascii_to_lower(text.ptr[index]) != ms_ascii_to_lower(prefix.ptr[index])) {
      return false;
    }
  }
  return true;
}

typedef struct Best {
  MsSpan name;
  size_t distance;
  bool unrelated;
  bool found;
} Best;

static size_t min_size(size_t a, size_t b) {
  return a < b ? a : b;
}

static bool is_better(const Best *best, size_t distance, bool unrelated, MsSpan candidate) {
  if (!best->found || distance != best->distance) {
    return !best->found || distance < best->distance;
  }
  if (unrelated != best->unrelated) {
    return !unrelated;
  }
  return ms_span_compare(candidate, best->name) < 0;
}

/* The candidate closest to `name` that is a plausible misspelling of it. */
static bool closest(MsSpan name, const SpanList *candidates, MsSpan *out) {
  if (name.len < 3) {
    return false;
  }
  const size_t limit = min_size((name.len + 1) / 3, 3);
  const size_t prefix_limit = min_size((name.len + 2) / 3, 3);
  Best best = {0};
  for (size_t index = 0; index < candidates->len; index++) {
    const MsSpan candidate = candidates->ptr[index];
    if (ms_span_equal(candidate, name)) {
      continue;
    }
    const size_t distance = edit_distance(name, candidate);
    const bool related = starts_with_nocase(name, candidate) || starts_with_nocase(candidate, name);
    if (distance <= (related ? prefix_limit : limit) && is_better(&best, distance, !related, candidate)) {
      best = (Best){.name = candidate, .distance = distance, .unrelated = !related, .found = true};
    }
  }
  *out = best.name;
  return best.found;
}

static void free_hint(Hint *hint) {
  ms_strbuild_free(&hint->text);
  ms_strbuild_free(&hint->near_edit);
  ms_strbuild_free(&hint->statement);
}

/* Fills the hint after the habits and keywords: receiver field, standard import, near spelling, advice. */
static void lookup_hint(MsCheckProgram *program, uint32_t module, MsName name, const MsBindingList *scope,
                        const MsScopeSite *site, Hint *hint) {
  const MsSpan text = ms_names_span(program->names, name);
  if (ms_scope_lookup(scope, ms_names_intern(program->names, ms_span_of_text("self"))) != NULL &&
      receiver_has_field(program, module, site, name)) {
    ms_strbuild_printf(&hint->text, "; %.*s is a field of this method's receiver, so write self.%.*s",
                       (int)text.len, (const char *)text.ptr, (int)text.len, (const char *)text.ptr);
    ms_strbuild_append_text(&hint->near_edit, "self.");
    ms_strbuild_append(&hint->near_edit, text);
    hint->near = true;
    return;
  }
  MsStrBuild module_path = ms_strbuild_new();
  if (ms_std_exporter(program, text, false, &module_path)) {
    ms_strbuild_append_text(&hint->text, "; add: import ");
    ms_strbuild_append(&hint->text, text);
    ms_strbuild_append_text(&hint->text, " from \"");
    ms_strbuild_append(&hint->text, ms_strbuild_span(&module_path));
    ms_strbuild_append_text(&hint->text, "\"");
    hint->import = true;
    ms_strbuild_append_text(&hint->statement, "import ");
    ms_strbuild_append(&hint->statement, text);
    ms_strbuild_append_text(&hint->statement, " from \"");
    ms_strbuild_append(&hint->statement, ms_strbuild_span(&module_path));
    ms_strbuild_append_text(&hint->statement, "\"\n");
    ms_strbuild_free(&module_path);
    return;
  }
  ms_strbuild_free(&module_path);
  SpanList candidates = {0};
  collect_value_names(program, module, scope, &candidates);
  MsSpan near_name = {0};
  if (closest(text, &candidates, &near_name)) {
    ms_strbuild_append_text(&hint->text, "; did you mean '");
    ms_strbuild_append(&hint->text, near_name);
    ms_strbuild_append_text(&hint->text, "'?");
    ms_strbuild_append(&hint->near_edit, near_name);
    hint->near = true;
  } else {
    ms_strbuild_printf(&hint->text, "; declare it with '%.*s := ...' before use, define 'fn %.*s(...) T { ... }', or import it from a module",
                       (int)text.len, (const char *)text.ptr, (int)text.len, (const char *)text.ptr);
  }
  span_list_free(&candidates);
}

static void attach_edit(MsCheckProgram *program, MsPos pos, MsSpan name, const Hint *hint) {
  const MsPos end = {.offset = pos.offset + (uint32_t)name.len, .line = pos.line, .column = pos.column + (uint32_t)name.len};
  if (hint->edit != NULL) {
    ms_check_attach_fix(program, pos, end, ms_string_from_span(ms_span_of_text(hint->edit)));
  } else if (hint->near) {
    ms_check_attach_fix(program, pos, end, ms_string_from_span(ms_strbuild_span(&hint->near_edit)));
  } else if (hint->import) {
    const MsPos start = {.offset = 0, .line = 1, .column = 1};
    ms_check_attach_fix(program, start, start, ms_string_from_span(ms_strbuild_span(&hint->statement)));
  }
}

void ms_unknown_name_report(MsCheckProgram *program, uint32_t module, MsPos pos, MsName name,
                            const MsBindingList *scope, const MsScopeSite *site) {
  const MsSpan text = ms_names_span(program->names, name);
  Hint hint = {.text = ms_strbuild_new(), .near_edit = ms_strbuild_new(), .statement = ms_strbuild_new()};
  const bool has_self =
      ms_scope_lookup(scope, ms_names_intern(program->names, ms_span_of_text("self"))) != NULL;
  MsStrBuild habit = ms_strbuild_new();
  if (keyword_hint(text, has_self, &hint)) {
    /* nothing more */
  } else if (ms_name_habit(text, &habit, &hint.edit)) {
    ms_strbuild_append_text(&hint.text, "; ");
    ms_strbuild_append(&hint.text, ms_strbuild_span(&habit));
  } else {
    lookup_hint(program, module, name, scope, site, &hint);
  }
  ms_strbuild_free(&habit);
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "unknown binding ");
  ms_strbuild_append(&message, text);
  ms_strbuild_append(&message, ms_strbuild_span(&hint.text));
  ms_check_report(program, module, pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&message));
  attach_edit(program, pos, text, &hint);
  free_hint(&hint);
}
