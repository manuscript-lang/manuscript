/* Owns search_project.h. The project in the working directory is the nearest ancestor `ms.toml` (a workspace root
 * stands for its members), else every `.ms` file below the working directory, each checked on its own. A project that
 * does not check yields nothing, as the language server indexes only what compiles. */
#include "driver/search_project.h"

#include <string.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/sort.h"
#include "base/strbuild.h"
#include "compiler/project/project.h"
#include "driver/checked_input.h"
#include "tooling/doc_comment.h"
#include "tooling/facts.h"
#include "tooling/inspect.h"
#include "tooling/occurrence.h"

typedef struct Analysis {
  MsCheckedInput checked;
  MsOccurrences index;
  MsInspection inspection;
} Analysis;

typedef struct Candidate {
  Analysis *analysis;
  const MsOccurrence *entry;
  MsSpan path; /* shown: relative to the working directory when below it */
  size_t line, column; /* zero-based; the column in UTF-16 units */
  int rank;
  int kind_number; /* the language-server symbol kind: type 5, enum 10, function 12, constant 14 */
  const char *kind;
} Candidate;

MS_AVEC(Candidates, candidates, Candidate)
MS_AVEC(Analyses, analyses, Analysis *)

static bool path_below(MsSpan path, MsSpan dir) {
  return dir.len > 0 && path.len > dir.len + 1 && ms_span_starts_with(path, dir) && path.ptr[dir.len] == '/';
}

static MsSpan shown_path(MsSpan path, MsSpan cwd) {
  return path_below(path, cwd) ? ms_span_of(path.ptr + cwd.len + 1, path.len - cwd.len - 1) : path;
}

/* ---- the analyses ---- */

static void analyze(MsArena *arena, MsSpan filename, Analyses *out) {
  Analysis *analysis = MS_ARENA_NEW_ARRAY(arena, Analysis, 1);
  *analysis = (Analysis){0};
  const MsLoadOptions options = {.tests = true, .project_sources = true};
  if (!ms_checked_input_load_with(arena, &analysis->checked, filename, MS_INPUT_ANALYSIS, &options)) {
    ms_checked_input_free(&analysis->checked);
    return;
  }
  analysis->index = ms_occurrence_index(arena, &analysis->checked.program);
  ms_inspect_collect(arena, &analysis->checked.program, false, &analysis->inspection);
  analyses_push(arena, out, analysis);
}

static void analyze_tree(MsArena *arena, MsSpan dir, Analyses *out) {
  MsDirEntryList entries = {0};
  if (!ms_dir_list(dir, &entries)) {
    return;
  }
  for (size_t i = 0; i < entries.len; i++) {
    const MsSpan name = ms_string_span(&entries.ptr[i].name);
    if (name.len == 0 || name.ptr[0] == '.') {
      continue;
    }
    const MsSpan path = ms_message_format(arena, "%S/%S", dir, name);
    if (entries.ptr[i].kind == MS_PATH_DIRECTORY) {
      analyze_tree(arena, path, out);
    } else if (entries.ptr[i].kind == MS_PATH_FILE && name.len > 3 && ms_span_ends_with(name, ms_span_of_text(".ms"))) {
      analyze(arena, path, out);
    }
  }
  ms_dir_entries_free(&entries);
}

/* The directory of the nearest `ms.toml` at or above `dir`, or an empty span. */
static MsSpan manifest_dir(MsArena *arena, MsSpan dir) {
  while (dir.len > 0) {
    if (ms_path_kind(ms_message_format(arena, "%S/ms.toml", dir, (MsSpan){0})) == MS_PATH_FILE) {
      return dir;
    }
    size_t cut = dir.len;
    while (cut > 0 && dir.ptr[cut - 1] != '/') {
      cut--;
    }
    dir = ms_span_of(dir.ptr, cut > 1 ? cut - 1 : 0);
  }
  return (MsSpan){0};
}

static void analyze_project(MsArena *arena, MsSpan cwd, Analyses *out) {
  const MsSpan root = manifest_dir(arena, cwd);
  if (root.len == 0) {
    analyze_tree(arena, cwd, out);
    return;
  }
  const MsSpan manifest = ms_message_format(arena, "%S/ms.toml", root, (MsSpan){0});
  MsSpanList members = {0};
  MsProjectError error = {0};
  bool found = false;
  if (ms_project_workspace_members(arena, manifest, &members, &found, &error) && found) {
    for (size_t i = 0; i < members.len; i++) {
      analyze(arena, members.ptr[i], out);
    }
    return;
  }
  analyze(arena, manifest, out);
}

/* ---- the matches ---- */

static MsSpan module_path(const Analysis *a, uint32_t module, MsSpan cwd) {
  const MsCheckProgram *program = &a->checked.program;
  const MsSpan file = ms_names_span(program->names, program->modules.ptr[module].file);
  for (size_t i = 0; i < a->checked.graph.count; i++) {
    if (ms_span_equal(a->checked.graph.modules[i].name, file)) {
      return shown_path(a->checked.graph.modules[i].path, cwd);
    }
  }
  return file;
}

static void classify(const MsCheckProgram *program, const MsOccurrence *entry, Candidate *out) {
  out->kind = "fn";
  out->kind_number = 12;
  if (entry->symbol == 0 || program->symbols.ptr[entry->symbol].decl == NULL) {
    return;
  }
  switch (program->symbols.ptr[entry->symbol].decl->kind) {
  case MS_D_TYPE:
  case MS_D_ALIAS:
    out->kind = "type";
    out->kind_number = 5;
    break;
  case MS_D_INTERFACE:
    out->kind = "type";
    out->kind_number = 11;
    break;
  case MS_D_ENUM:
    out->kind = "enum";
    out->kind_number = 10;
    break;
  case MS_D_CONST:
    out->kind = "const";
    out->kind_number = 14;
    break;
  default:
    break;
  }
}

static void collect(MsArena *arena, Analysis *a, MsSpan query, MsSpan cwd, Candidates *out) {
  const MsCheckProgram *program = &a->checked.program;
  for (size_t i = 0; i < a->index.len; i++) {
    const MsOccurrence *entry = &a->index.ptr[i];
    if (!entry->declaration || (entry->symbol == 0 && !entry->method)) {
      continue;
    }
    const int rank = ms_symbol_name_rank(arena, entry->name, query);
    if (rank < 0) {
      continue;
    }
    Candidate candidate = {.analysis = a, .entry = entry, .rank = rank, .path = module_path(a, entry->module, cwd)};
    ms_source_position(program->modules.ptr[entry->module].source, entry->offset, &candidate.line, &candidate.column);
    classify(program, entry, &candidate);
    candidates_push(arena, out, candidate);
  }
}

static int64_t compare_candidate(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const Candidate *a = (const Candidate *)(const void *)left;
  const Candidate *b = (const Candidate *)(const void *)right;
  if (a->rank != b->rank) {
    return a->rank - b->rank;
  }
  const int64_t by_name = ms_span_compare(a->entry->name, b->entry->name);
  if (by_name != 0) {
    return by_name;
  }
  if (a->kind_number != b->kind_number) {
    return a->kind_number - b->kind_number;
  }
  const int64_t by_path = ms_span_compare(a->path, b->path);
  if (by_path != 0) {
    return by_path;
  }
  if (a->line != b->line) {
    return a->line < b->line ? -1 : 1;
  }
  return a->column == b->column ? 0 : (a->column < b->column ? -1 : 1);
}

static bool same_place(const Candidate *a, const Candidate *b) {
  return ms_span_equal(a->path, b->path) && a->line == b->line && a->column == b->column &&
         ms_span_equal(a->entry->name, b->entry->name);
}

static MsSpan place(MsArena *arena, MsSpan path, size_t line, size_t column) {
  return ms_message_format(arena, "%S:%z:%z", path, line + 1, column + 1);
}

typedef struct Use {
  MsSpan path;
  size_t line, column;
} Use;
MS_AVEC(UseList, use_list, Use)

static int64_t compare_use(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const Use *a = (const Use *)(const void *)left;
  const Use *b = (const Use *)(const void *)right;
  const int64_t by_path = ms_span_compare(a->path, b->path);
  if (by_path != 0) {
    return by_path;
  }
  if (a->line != b->line) {
    return a->line < b->line ? -1 : 1;
  }
  return a->column == b->column ? 0 : (a->column < b->column ? -1 : 1);
}

static MsSpans uses_of(MsArena *arena, const Candidate *c, MsSpan cwd) {
  const Analysis *a = c->analysis;
  UseList found = {0};
  for (size_t i = 0; i < a->index.len; i++) {
    const MsOccurrence *entry = &a->index.ptr[i];
    if (!ms_span_equal(entry->key, c->entry->key) || entry == c->entry) {
      continue;
    }
    Use use = {.path = module_path(a, entry->module, cwd)};
    ms_source_position(a->checked.program.modules.ptr[entry->module].source, entry->offset, &use.line, &use.column);
    if (entry->declaration && ms_span_equal(use.path, c->path) && use.line == c->line && use.column == c->column) {
      continue;
    }
    use_list_push(arena, &found, use);
  }
  if (found.len > 1) {
    ms_sort((uint8_t *)found.ptr, found.len, sizeof(Use), compare_use, NULL);
  }
  MsSpans uses = {0};
  for (size_t i = 0; i < found.len; i++) {
    if (i > 0 && compare_use(NULL, (const uint8_t *)(const void *)&found.ptr[i - 1], (const uint8_t *)(const void *)&found.ptr[i]) == 0) {
      continue;
    }
    ms_spans_push(arena, &uses, place(arena, found.ptr[i].path, found.ptr[i].line, found.ptr[i].column));
  }
  return uses;
}

static MsSpan first_sentence(MsSpan doc) {
  size_t at = 0;
  if (ms_span_find(doc, ms_span_of_text(". "), &at)) {
    return ms_span_of(doc.ptr, at + 1);
  }
  return doc;
}

static MsSpan effects_of(MsArena *arena, const Candidate *c) {
  const MsCheckProgram *program = &c->analysis->checked.program;
  const MsSpan file = ms_names_span(program->names, program->modules.ptr[c->entry->module].file);
  const MsInspection *inspection = &c->analysis->inspection;
  for (size_t i = 0; i < inspection->entities.len; i++) {
    const MsEntity *entity = &inspection->entities.ptr[i];
    if (!ms_span_equal(entity->file, file) || entity->pos.line != c->line + 1 || !ms_span_ends_with(entity->name, c->entry->name)) {
      continue;
    }
    MsStrBuild out = ms_strbuild_new();
    if (entity->effects.len == 0) {
      ms_strbuild_append_text(&out, "effects: pure (ambient authority only)");
    } else {
      ms_strbuild_append_text(&out, "effects: ");
      for (size_t e = 0; e < entity->effects.len; e++) {
        ms_strbuild_append_text(&out, e > 0 ? ", " : "");
        ms_strbuild_append(&out, entity->effects.ptr[e]);
      }
    }
    if (entity->permits.len > 0) {
      ms_strbuild_append_text(&out, "  permits: ");
      for (size_t p = 0; p < entity->permits.len; p++) {
        ms_strbuild_append_text(&out, p > 0 ? ", " : "");
        ms_strbuild_append(&out, entity->permits.ptr[p]);
      }
    }
    const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(&out));
    ms_strbuild_free(&out);
    return text;
  }
  return (MsSpan){0};
}

static MsSymbolMatch describe(MsArena *arena, const Candidate *c, MsSpan cwd) {
  const MsCheckProgram *program = &c->analysis->checked.program;
  MsSymbolMatch match = {.name = c->entry->name, .kind = ms_span_of_text(c->kind), .rank = (size_t)c->rank, .project = true,
                         .definition = place(arena, c->path, c->line, c->column)};
  if (c->entry->ty != MS_TY_NONE && !ms_ty_is_invalid(&program->types, c->entry->ty)) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append(&text, c->entry->name);
    ms_strbuild_append_text(&text, ": ");
    ms_ty_show(&text, program->names, &program->types, c->entry->ty);
    match.type = ms_arena_copy(arena, ms_strbuild_span(&text));
    ms_strbuild_free(&text);
    if (ms_span_starts_with(match.type, ms_message_format(arena, "%S: fn(", c->entry->name, (MsSpan){0}))) {
      match.effects = effects_of(arena, c);
    }
  }
  match.doc = first_sentence(ms_declaration_comment(arena, program->modules.ptr[c->entry->module].source, c->entry->offset,
                                                    (uint32_t)(c->line + 1)));
  match.uses = uses_of(arena, c, cwd);
  return match;
}

MsSymbolMatches ms_search_project(MsArena *arena, MsSpan query, size_t limit, size_t *total) {
  MsSymbolMatches matches = {0};
  *total = 0;
  MsString current = {0};
  if (!ms_dir_current(&current)) {
    return matches;
  }
  const MsSpan cwd = ms_arena_copy(arena, ms_string_span(&current));
  ms_string_release(&current);
  Analyses analyses = {0};
  analyze_project(arena, cwd, &analyses);
  Candidates candidates = {0};
  for (size_t i = 0; i < analyses.len; i++) {
    collect(arena, analyses.ptr[i], query, cwd, &candidates);
  }
  if (candidates.len > 1) {
    ms_sort((uint8_t *)candidates.ptr, candidates.len, sizeof(Candidate), compare_candidate, NULL);
  }
  size_t kept = 0;
  for (size_t i = 0; i < candidates.len; i++) {
    if (kept > 0 && same_place(&candidates.ptr[kept - 1], &candidates.ptr[i])) {
      continue;
    }
    candidates.ptr[kept++] = candidates.ptr[i];
  }
  *total = kept;
  for (size_t i = 0; i < kept && i < limit; i++) {
    ms_symbol_matches_push(arena, &matches, describe(arena, &candidates.ptr[i], cwd));
  }
  for (size_t i = 0; i < analyses.len; i++) {
    ms_checked_input_free(&analyses.ptr[i]->checked);
  }
  return matches;
}
