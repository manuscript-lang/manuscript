/* cli/lsp_workspace.c: the files of a project and workspace symbols. */
#include "cli/lsp_workspace.h"

#include <stdlib.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "cli/lsp_analysis.h"
#include "tooling/facts.h"

enum { MAX_FILES = 4000 };

static uint8_t lower(uint8_t byte) { return byte >= 'A' && byte <= 'Z' ? (uint8_t)(byte + 32) : byte; }

bool lsp_text_mentions(MsSpan text, MsSpan needle) {
  if (needle.len == 0) return true;
  for (size_t i = 0; i + needle.len <= text.len; i++) {
    size_t k = 0;
    while (k < needle.len && lower(text.ptr[i + k]) == lower(needle.ptr[k])) k++;
    if (k == needle.len) return true;
  }
  return false;
}

static void walk(MsArena *arena, MsSpan dir, MsSpanList *out) {
  MsDirEntryList entries = {0};
  if (!ms_dir_list(dir, &entries)) return;
  for (size_t i = 0; i < entries.len && out->len < MAX_FILES; i++) {
    const MsSpan name = ms_string_span(&entries.ptr[i].name);
    if (name.len == 0 || name.ptr[0] == '.') continue;
    const MsSpan path = ms_message_format(arena, "%S/%S", dir, name);
    if (entries.ptr[i].kind == MS_PATH_DIRECTORY) {
      walk(arena, path, out);
    } else if (entries.ptr[i].kind == MS_PATH_FILE && name.len > 3 && ms_span_ends_with(name, ms_span_of_text(".ms"))) {
      ms_span_list_push(out, path);
    }
  }
  ms_dir_entries_free(&entries);
}

static int compare_path(const void *left, const void *right) {
  return (int)ms_span_compare(*(const MsSpan *)left, *(const MsSpan *)right);
}

/* The nearest ancestor directory of `dir` that holds `ms.toml`, or `dir` itself. */
MsSpan lsp_project_root(MsArena *arena, MsSpan dir) {
  MsSpan at = dir;
  while (at.len > 0) {
    if (ms_path_kind(ms_message_format(arena, "%S/ms.toml", at, (MsSpan){0})) == MS_PATH_FILE) return at;
    size_t cut = at.len;
    while (cut > 0 && at.ptr[cut - 1] != '/') cut--;
    at = ms_span_of(at.ptr, cut > 1 ? cut - 1 : 0);
  }
  return dir;
}

void lsp_workspace_files(MsArena *arena, MsSpan file, MsSpanList *out) {
  MsStrBuild dir = ms_strbuild_new();
  ms_path_dir(file, &dir);
  const MsSpan start = ms_arena_copy(arena, ms_strbuild_span(&dir));
  ms_strbuild_free(&dir);
  const size_t first = out->len;
  walk(arena, lsp_project_root(arena, start), out);
  if (out->len - first > 1) qsort(out->ptr + first, out->len - first, sizeof(MsSpan), compare_path);
}

/* ---- workspace symbols ---- */

typedef struct Symbol {
  MsSpan name, uri;
  int kind;
  LspRange range;
} Symbol;

MS_LIST_DEFINE(SymbolList, symbol_list, Symbol)

static int compare_symbol(const void *left, const void *right) {
  const Symbol *a = left, *b = right;
  if (a->kind != b->kind) return a->kind < b->kind ? -1 : 1;
  const int64_t by_uri = ms_span_compare(a->uri, b->uri);
  if (by_uri != 0) return by_uri < 0 ? -1 : 1;
  if (a->range.start.line != b->range.start.line) return a->range.start.line < b->range.start.line ? -1 : 1;
  if (a->range.start.character != b->range.start.character) return a->range.start.character < b->range.start.character ? -1 : 1;
  const int64_t by_name = ms_span_compare(a->name, b->name);
  return by_name == 0 ? 0 : (by_name < 0 ? -1 : 1);
}

static int symbol_kind(const MsCheckProgram *program, const MsOccurrence *entry) {
  if (entry->symbol == 0 || program->symbols.ptr[entry->symbol].decl == NULL) return 12;
  switch (program->symbols.ptr[entry->symbol].decl->kind) {
    case MS_D_TYPE:
    case MS_D_ALIAS:
    case MS_D_INTERFACE:
      return 5;
    case MS_D_ENUM:
      return 10;
    case MS_D_CONST:
      return 14;
    default:
      return 12;
  }
}

static bool listed(const MsSpanList *paths, MsSpan path) {
  for (size_t i = 0; i < paths->len; i++) {
    if (ms_span_equal(paths->ptr[i], path)) return true;
  }
  return false;
}

void lsp_workspace_symbols(const LspDocList *docs, const MsSpan *roots, size_t root_count, MsSpan query, MsStrBuild *out) {
  MsArena arena = ms_arena_new();
  MsSpanList paths = {0};
  for (size_t i = 0; i < docs->len; i++) {
    MsSpanList project = {0};
    lsp_workspace_files(&arena, ms_string_span(&docs->ptr[i].path), &project);
    for (size_t p = 0; p < project.len; p++) {
      if (!listed(&paths, project.ptr[p])) ms_span_list_push(&paths, project.ptr[p]);
    }
    ms_span_list_free(&project);
  }
  for (size_t i = 0; i < root_count; i++) {
    MsSpanList project = {0};
    lsp_workspace_files(&arena, ms_message_format(&arena, "%S/__workspace_index.ms", roots[i], (MsSpan){0}), &project);
    for (size_t p = 0; p < project.len; p++) {
      if (!listed(&paths, project.ptr[p])) ms_span_list_push(&paths, project.ptr[p]);
    }
    ms_span_list_free(&project);
  }
  SymbolList found = {0};
  for (size_t i = 0; i < paths.len; i++) {
    const LspDoc *open = NULL;
    for (size_t d = 0; d < docs->len && open == NULL; d++) {
      if (ms_span_equal(ms_string_span(&docs->ptr[d].path), paths.ptr[i])) open = &docs->ptr[d];
    }
    MsBytes bytes = {0};
    MsSpan text;
    if (open != NULL) {
      text = ms_string_span(&open->text);
    } else if (ms_file_read(paths.ptr[i], &bytes)) {
      text = ms_bytes_span(&bytes);
    } else {
      continue;
    }
    const bool mentions = lsp_text_mentions(text, query);
    if (open == NULL) ms_bytes_free(&bytes);
    if (!mentions) continue;
    LspDoc entry = {.path = ms_string_from_span(paths.ptr[i])};
    LspAnalysis analysis;
    lsp_analyze(docs, &entry, &analysis);
    const MsCheckProgram *program = &analysis.checked.program;
    for (size_t e = 0; analysis.resolved && e < analysis.index.len; e++) {
      const MsOccurrence *occurrence = &analysis.index.ptr[e];
      if (!occurrence->declaration || (occurrence->symbol == 0 && !occurrence->method) || !lsp_text_mentions(occurrence->name, query)) continue;
      const MsSpan source = program->modules.ptr[occurrence->module].source;
      Symbol symbol = {.name = ms_arena_copy(&arena, occurrence->name), .uri = lsp_path_uri(docs, &arena, analysis.paths[occurrence->module]),
                       .kind = symbol_kind(program, occurrence),
                       .range = {lsp_position(source, occurrence->offset), lsp_position(source, occurrence->end)}};
      bool duplicate = false;
      for (size_t k = 0; k < found.len && !duplicate; k++) duplicate = compare_symbol(&found.ptr[k], &symbol) == 0;
      if (!duplicate) symbol_list_push(&found, symbol);
    }
    lsp_analysis_release(&analysis);
    ms_string_release(&entry.path);
  }
  if (found.len > 1) qsort(found.ptr, found.len, sizeof(Symbol), compare_symbol);
  ms_strbuild_append_byte(out, '[');
  for (size_t i = 0; i < found.len; i++) {
    const Symbol *symbol = &found.ptr[i];
    if (i > 0) ms_strbuild_append_byte(out, ',');
    ms_strbuild_append_text(out, "{\"name\":");
    lsp_json_string(out, symbol->name);
    ms_strbuild_printf(out, ",\"kind\":%d,\"location\":{\"uri\":", symbol->kind);
    lsp_json_string(out, symbol->uri);
    ms_strbuild_printf(out, ",\"range\":{\"start\":{\"line\":%zu,\"character\":%zu},\"end\":{\"line\":%zu,\"character\":%zu}}}}",
                       symbol->range.start.line, symbol->range.start.character, symbol->range.end.line, symbol->range.end.character);
  }
  ms_strbuild_append_byte(out, ']');
  symbol_list_free(&found);
  ms_span_list_free(&paths);
  ms_arena_free(&arena);
}
