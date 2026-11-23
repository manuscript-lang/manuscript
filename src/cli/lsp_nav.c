/* cli/lsp_nav.c: definition, references, highlights and rename over the occurrence index of one checked graph. */
#include "cli/lsp_nav.h"

#include <stdlib.h>
#include <string.h>

#include "compiler/syntax/lex.h"
#include "tooling/doc_comment.h"
#include "tooling/inspect.h"

typedef struct Place {
  MsSpan uri;
  LspRange range;
} Place;

MS_LIST_DEFINE(PlaceList, place_list, Place)

static const MsOccurrence *occurrence_at(const LspAnalysis *analysis, const LspDoc *doc, size_t offset) {
  for (size_t i = 0; i < analysis->index.len; i++) {
    const MsOccurrence *entry = &analysis->index.ptr[i];
    if (offset >= entry->offset && offset < entry->end &&
        ms_span_equal(analysis->paths[entry->module], ms_string_span(&doc->path))) {
      return entry;
    }
  }
  return NULL;
}

static MsSpan source_of(const LspAnalysis *analysis, const MsOccurrence *entry) {
  return analysis->checked.program.modules.ptr[entry->module].source;
}

/* The URI an editor opened `path` under, else its `file:` URI (in the analysis arena). */
static MsSpan uri_of(LspAnalysis *analysis, const LspDocList *docs, MsSpan path) {
  for (size_t i = 0; i < docs->len; i++) {
    if (ms_span_equal(ms_string_span(&docs->ptr[i].path), path)) return ms_string_span(&docs->ptr[i].uri);
  }
  MsStrBuild uri = ms_strbuild_new();
  lsp_file_uri(path, &uri);
  const MsSpan copy = ms_arena_copy(&analysis->arena, ms_strbuild_span(&uri));
  ms_strbuild_free(&uri);
  return copy;
}

static void write_range(MsStrBuild *out, LspRange range) {
  ms_strbuild_printf(out, "{\"start\":{\"line\":%zu,\"character\":%zu},\"end\":{\"line\":%zu,\"character\":%zu}}",
                     range.start.line, range.start.character, range.end.line, range.end.character);
}

static void write_place(MsStrBuild *out, const Place *place) {
  ms_strbuild_append_text(out, "{\"uri\":");
  lsp_json_string(out, place->uri);
  ms_strbuild_append_text(out, ",\"range\":");
  write_range(out, place->range);
  ms_strbuild_append_byte(out, '}');
}

static Place place_of(LspAnalysis *analysis, const LspDocList *docs, const MsOccurrence *entry) {
  const MsSpan source = source_of(analysis, entry);
  return (Place){uri_of(analysis, docs, analysis->paths[entry->module]),
                 {lsp_position(source, entry->offset), lsp_position(source, entry->end)}};
}

/* Orders places by range (start line and character, then end), then URI. */
static int compare_place(const void *left, const void *right) {
  const Place *a = left, *b = right;
  const size_t x[4] = {a->range.start.line, a->range.start.character, a->range.end.line, a->range.end.character};
  const size_t y[4] = {b->range.start.line, b->range.start.character, b->range.end.line, b->range.end.character};
  for (size_t i = 0; i < 4; i++) {
    if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
  }
  const size_t common = a->uri.len < b->uri.len ? a->uri.len : b->uri.len;
  for (size_t i = 0; i < common; i++) {
    if (a->uri.ptr[i] != b->uri.ptr[i]) return a->uri.ptr[i] < b->uri.ptr[i] ? -1 : 1;
  }
  return a->uri.len < b->uri.len ? -1 : (a->uri.len > b->uri.len ? 1 : 0);
}

/* The places of every occurrence of the identity at `selected`, sorted and without repeats. */
static void collect_places(LspAnalysis *analysis, const LspDocList *docs, const MsOccurrence *selected, bool include,
                           bool same_file_only, const LspDoc *doc, PlaceList *places) {
  for (size_t i = 0; i < analysis->index.len; i++) {
    const MsOccurrence *entry = &analysis->index.ptr[i];
    if (!ms_span_equal(entry->key, selected->key) || (!include && entry->declaration)) continue;
    if (same_file_only && !ms_span_equal(analysis->paths[entry->module], ms_string_span(&doc->path))) continue;
    place_list_push(places, place_of(analysis, docs, entry));
  }
  if (places->len > 1) qsort(places->ptr, places->len, sizeof(Place), compare_place);
}

static void write_places(MsStrBuild *out, const PlaceList *places, const char *kind) {
  ms_strbuild_append_byte(out, '[');
  bool first = true;
  for (size_t i = 0; i < places->len; i++) {
    if (i > 0 && compare_place(&places->ptr[i - 1], &places->ptr[i]) == 0) continue;
    if (!first) ms_strbuild_append_byte(out, ',');
    first = false;
    if (kind == NULL) {
      write_place(out, &places->ptr[i]);
    } else {
      ms_strbuild_append_text(out, "{\"range\":");
      write_range(out, places->ptr[i].range);
      ms_strbuild_printf(out, ",\"kind\":%s}", kind);
    }
  }
  ms_strbuild_append_byte(out, ']');
}

/* Analyses `doc` and finds the occurrence at `position`; false when the document is not checked or names nothing. */
static bool select(const LspDocList *docs, const LspDoc *doc, LspPosition position, LspAnalysis *analysis,
                   const MsOccurrence **selected) {
  lsp_analyze(docs, doc, analysis);
  size_t offset;
  if (!analysis->resolved || !lsp_offset(ms_string_span(&doc->text), position, false, &offset)) return false;
  *selected = occurrence_at(analysis, doc, offset);
  return *selected != NULL;
}

/* The declaration occurrence of the identity `selected` names, or NULL when its source is not in the graph. */
static const MsOccurrence *declaration_of(const LspAnalysis *analysis, const MsOccurrence *selected) {
  for (size_t i = 0; i < analysis->index.len; i++) {
    const MsOccurrence *entry = &analysis->index.ptr[i];
    if (entry->declaration && ms_span_equal(entry->key, selected->key)) return entry;
  }
  return NULL;
}

/* The effects hover shows for a function declared at `line` (1-based) of `module`: what it reaches, what it permits. */
static void write_effects(MsStrBuild *out, const MsInspection *inspection, MsSpan file, size_t line, MsSpan name) {
  for (size_t i = 0; i < inspection->entities.len; i++) {
    const MsEntity *entity = &inspection->entities.ptr[i];
    if (!ms_span_equal(entity->file, file) || entity->pos.line != line || !ms_span_ends_with(entity->name, name)) continue;
    ms_strbuild_append_text(out, "\n\n");
    if (entity->effects.len == 0) {
      ms_strbuild_append_text(out, "effects: pure (ambient authority only)");
    } else {
      ms_strbuild_append_text(out, "effects: ");
      for (size_t e = 0; e < entity->effects.len; e++) {
        if (e > 0) ms_strbuild_append_text(out, ", ");
        ms_strbuild_append(out, entity->effects.ptr[e]);
      }
    }
    if (entity->permits.len > 0) {
      ms_strbuild_append_text(out, "  \npermits: ");
      for (size_t p = 0; p < entity->permits.len; p++) {
        if (p > 0) ms_strbuild_append_text(out, ", ");
        ms_strbuild_append(out, entity->permits.ptr[p]);
      }
    }
    return;
  }
}

void lsp_nav_hover(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out) {
  LspAnalysis analysis;
  const MsOccurrence *selected;
  if (!select(docs, doc, position, &analysis, &selected)) goto none;
  const MsCheckProgram *program = &analysis.checked.program;
  if (selected->ty == MS_TY_NONE || ms_ty_is_invalid(&program->types, selected->ty)) goto none;
  MsStrBuild shown = ms_strbuild_new();
  ms_ty_show(&shown, program->names, &program->types, selected->ty);
  MsStrBuild value = ms_strbuild_new();
  ms_strbuild_append_text(&value, "```manuscript\n");
  ms_strbuild_append(&value, selected->name);
  ms_strbuild_append_text(&value, ": ");
  ms_strbuild_append(&value, ms_strbuild_span(&shown));
  ms_strbuild_append_text(&value, "\n```");
  const MsOccurrence *declaration = declaration_of(&analysis, selected);
  if (declaration != NULL) {
    const MsSpan source = source_of(&analysis, declaration);
    const size_t line = lsp_position(source, declaration->offset).line + 1;
    if (ms_span_starts_with(ms_strbuild_span(&shown), ms_span_of_text("fn("))) {
      MsInspection inspection = {0};
      ms_inspect_collect(&analysis.arena, program, false, &inspection);
      write_effects(&value, &inspection,
                    ms_names_span(program->names, program->modules.ptr[declaration->module].file), line, selected->name);
    }
    const MsSpan docs_text = ms_declaration_comment(&analysis.arena, source, declaration->offset, (uint32_t)line);
    if (docs_text.len > 0) {
      ms_strbuild_append_text(&value, "\n\n");
      ms_strbuild_append(&value, docs_text);
    }
  }
  const MsSpan text = source_of(&analysis, selected);
  ms_strbuild_append_text(out, "{\"contents\":{\"kind\":\"markdown\",\"value\":");
  lsp_json_string(out, ms_strbuild_span(&value));
  ms_strbuild_append_text(out, "},\"range\":");
  write_range(out, (LspRange){lsp_position(text, selected->offset), lsp_position(text, selected->end)});
  ms_strbuild_append_byte(out, '}');
  ms_strbuild_free(&shown);
  ms_strbuild_free(&value);
  lsp_analysis_release(&analysis);
  return;
none:
  ms_strbuild_append_text(out, "null");
  lsp_analysis_release(&analysis);
}

void lsp_nav_definition(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out) {
  LspAnalysis analysis;
  const MsOccurrence *selected;
  if (select(docs, doc, position, &analysis, &selected)) {
    for (size_t i = 0; i < analysis.index.len; i++) {
      const MsOccurrence *entry = &analysis.index.ptr[i];
      if (!entry->declaration || !ms_span_equal(entry->key, selected->key)) continue;
      const Place place = place_of(&analysis, docs, entry);
      ms_strbuild_append_byte(out, '[');
      write_place(out, &place);
      ms_strbuild_append_byte(out, ']');
      lsp_analysis_release(&analysis);
      return;
    }
  }
  ms_strbuild_append_text(out, "null");
  lsp_analysis_release(&analysis);
}

void lsp_nav_references(const LspDocList *docs, const LspDoc *doc, LspPosition position, bool include_declaration,
                        MsStrBuild *out) {
  LspAnalysis analysis;
  const MsOccurrence *selected;
  PlaceList places = {0};
  if (select(docs, doc, position, &analysis, &selected)) {
    collect_places(&analysis, docs, selected, include_declaration, false, doc, &places);
  }
  write_places(out, &places, NULL);
  place_list_free(&places);
  lsp_analysis_release(&analysis);
}

void lsp_nav_highlight(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out) {
  LspAnalysis analysis;
  const MsOccurrence *selected;
  PlaceList places = {0};
  if (select(docs, doc, position, &analysis, &selected)) {
    collect_places(&analysis, docs, selected, true, true, doc, &places);
  }
  write_places(out, &places, "2");
  place_list_free(&places);
  lsp_analysis_release(&analysis);
}

/* ---- rename ---- */

static bool is_identifier(MsSpan name) {
  MsArena arena = ms_arena_new();
  MsLexed lexed;
  MsDiag diag;
  bool ok = ms_lex(&arena, name, &lexed, &diag) && lexed.ntokens > 0 && lexed.tokens[0].kind == MS_T_Name &&
            lexed.tokens[0].lo == 0 && lexed.tokens[0].hi == name.len;
  ms_arena_free(&arena);
  return ok;
}

/* Whether `name` occurs as a word in `source` (the capture check: a rename may not land on a name already used). */
static bool occurs(MsSpan source, MsSpan name) {
  size_t from = 0, at;
  while (from <= source.len && ms_span_find(ms_span_of(source.ptr + from, source.len - from), name, &at)) {
    const size_t start = from + at, end = start + name.len;
    const bool before = start > 0 && (source.ptr[start - 1] == '_' || (source.ptr[start - 1] | 32) - 'a' < 26u ||
                                       source.ptr[start - 1] - '0' < 10u);
    const bool after = end < source.len && (source.ptr[end] == '_' || (source.ptr[end] | 32) - 'a' < 26u ||
                                             source.ptr[end] - '0' < 10u);
    if (!before && !after) return true;
    from = start + 1;
  }
  return false;
}

typedef struct Edit {
  size_t start, end;
} Edit;

MS_LIST_DEFINE(EditList, edit_list, Edit)

static int compare_edit_descending(const void *left, const void *right) {
  const Edit *a = left, *b = right;
  return a->start == b->start ? 0 : (a->start < b->start ? 1 : -1);
}

static void refuse(MsStrBuild *error, const char *message) {
  ms_strbuild_append_text(error, message);
}

bool lsp_nav_rename(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsSpan new_name, MsStrBuild *out,
                    MsStrBuild *error) {
  LspAnalysis analysis;
  const MsOccurrence *selected;
  bool ok = false;
  if (!select(docs, doc, position, &analysis, &selected)) {
    refuse(error, "select a name that refers to a source declaration");
    goto done;
  }
  const MsCheckProgram *program = &analysis.checked.program;
  if (ms_span_find(selected->key, ms_span_of_text(":@std/"), &(size_t){0})) {
    refuse(error, "standard-library declarations are read-only");
    goto done;
  }
  if (ms_span_is_text(selected->name, "main") && selected->symbol != 0 &&
      program->symbols.ptr[selected->symbol].decl != NULL && program->symbols.ptr[selected->symbol].decl->kind == MS_D_FN) {
    refuse(error, "main is the program entry point; the run command looks it up by name");
    goto done;
  }
  bool has_declaration = false;
  for (size_t i = 0; i < analysis.index.len; i++) {
    has_declaration |= analysis.index.ptr[i].declaration && ms_span_equal(analysis.index.ptr[i].key, selected->key);
  }
  if (new_name.len == 0) {
    if (!has_declaration) {
      refuse(error, "declaration is external or has no editable source");
      goto done;
    }
    const MsSpan source = source_of(&analysis, selected);
    ms_strbuild_append_text(out, "{\"range\":");
    write_range(out, (LspRange){lsp_position(source, selected->offset), lsp_position(source, selected->end)});
    ms_strbuild_append_text(out, ",\"placeholder\":");
    lsp_json_string(out, selected->name);
    ms_strbuild_append_byte(out, '}');
    ok = true;
    goto done;
  }
  if (!has_declaration) {
    refuse(error, "declaration is external or has no editable source");
    goto done;
  }
  if (!is_identifier(new_name)) {
    refuse(error, "new name must be a Manuscript identifier");
    goto done;
  }
  if (ms_span_equal(new_name, selected->name)) {
    ms_strbuild_append_text(out, "{\"documentChanges\":[]}");
    ok = true;
    goto done;
  }
  /* The files holding the identity, in path order, each with its edits from the last to the first. */
  MsSpan *files = MS_ARENA_NEW_ARRAY(&analysis.arena, MsSpan, program->user_modules + 1);
  uint32_t *modules = MS_ARENA_NEW_ARRAY(&analysis.arena, uint32_t, program->user_modules + 1);
  size_t file_count = 0;
  for (size_t i = 0; i < analysis.index.len; i++) {
    const MsOccurrence *entry = &analysis.index.ptr[i];
    if (!ms_span_equal(entry->key, selected->key)) continue;
    bool known = false;
    for (size_t f = 0; f < file_count; f++) known |= modules[f] == entry->module;
    if (known) continue;
    modules[file_count] = entry->module;
    files[file_count++] = uri_of(&analysis, docs, analysis.paths[entry->module]);
  }
  for (size_t a = 1; a < file_count; a++) { /* insertion sort by URI */
    for (size_t b = a; b > 0; b--) {
      const MsSpan x = files[b - 1], y = files[b];
      const size_t common = x.len < y.len ? x.len : y.len;
      int order = 0;
      for (size_t k = 0; k < common && order == 0; k++) order = x.ptr[k] == y.ptr[k] ? 0 : (x.ptr[k] < y.ptr[k] ? -1 : 1);
      if (order == 0) order = x.len > y.len ? 1 : 0;
      if (order <= 0) break;
      const MsSpan swap_uri = files[b - 1];
      files[b - 1] = files[b];
      files[b] = swap_uri;
      const uint32_t swap_module = modules[b - 1];
      modules[b - 1] = modules[b];
      modules[b] = swap_module;
    }
  }
  /* Apply the edits to a copy of every file, so the result can be checked before it is proposed. */
  MsOverlayFile *changed = MS_ARENA_NEW_ARRAY(&analysis.arena, MsOverlayFile, file_count + 1);
  MsStrBuild body = ms_strbuild_new();
  ms_strbuild_append_text(&body, "{\"documentChanges\":[");
  for (size_t f = 0; f < file_count; f++) {
    const MsSpan source = program->modules.ptr[modules[f]].source;
    if (occurs(source, new_name)) {
      ms_strbuild_printf(error, "%.*s already occurs in %.*s; rename could capture another binding", (int)new_name.len,
                         new_name.ptr, (int)analysis.paths[modules[f]].len, analysis.paths[modules[f]].ptr);
      ms_strbuild_free(&body);
      goto done;
    }
    EditList edits = {0};
    for (size_t i = 0; i < analysis.index.len; i++) {
      const MsOccurrence *entry = &analysis.index.ptr[i];
      if (entry->module != modules[f] || !ms_span_equal(entry->key, selected->key)) continue;
      bool repeated = false;
      for (size_t e = 0; e < edits.len; e++) repeated |= edits.ptr[e].start == entry->offset;
      if (!repeated) edit_list_push(&edits, (Edit){entry->offset, entry->end});
    }
    qsort(edits.ptr, edits.len, sizeof(Edit), compare_edit_descending);
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append(&text, source);
    if (f > 0) ms_strbuild_append_byte(&body, ',');
    ms_strbuild_append_text(&body, "{\"textDocument\":{\"uri\":");
    lsp_json_string(&body, files[f]);
    ms_strbuild_append_text(&body, ",\"version\":");
    const LspDoc *opened = lsp_doc_find(docs, files[f]);
    if (opened != NULL) ms_strbuild_printf(&body, "%lld", (long long)opened->version);
    else ms_strbuild_append_text(&body, "null");
    ms_strbuild_append_text(&body, "},\"edits\":[");
    for (size_t e = 0; e < edits.len; e++) {
      if (edits.ptr[e].end > source.len) {
        refuse(error, "source revision changed");
        ms_strbuild_free(&body);
        ms_strbuild_free(&text);
        edit_list_free(&edits);
        goto done;
      }
      if (e > 0) ms_strbuild_append_byte(&body, ',');
      ms_strbuild_append_text(&body, "{\"range\":");
      write_range(&body, (LspRange){lsp_position(source, edits.ptr[e].start), lsp_position(source, edits.ptr[e].end)});
      ms_strbuild_append_text(&body, ",\"newText\":");
      lsp_json_string(&body, new_name);
      ms_strbuild_append_byte(&body, '}');
      MsStrBuild next = ms_strbuild_new();
      const MsSpan current = ms_strbuild_span(&text);
      ms_strbuild_append(&next, ms_span_of(current.ptr, edits.ptr[e].start));
      ms_strbuild_append(&next, new_name);
      ms_strbuild_append(&next, ms_span_of(current.ptr + edits.ptr[e].end, current.len - edits.ptr[e].end));
      ms_strbuild_free(&text);
      text = next;
    }
    ms_strbuild_append_text(&body, "]}");
    changed[f] = (MsOverlayFile){analysis.paths[modules[f]], ms_arena_copy(&analysis.arena, ms_strbuild_span(&text))};
    ms_strbuild_free(&text);
    edit_list_free(&edits);
  }
  ms_strbuild_append_text(&body, "]}");
  ok = lsp_rename_stays_checked(docs, doc, changed, file_count, error);
  if (ok) ms_strbuild_append(out, ms_strbuild_span(&body));
  ms_strbuild_free(&body);
done:
  lsp_analysis_release(&analysis);
  return ok;
}
