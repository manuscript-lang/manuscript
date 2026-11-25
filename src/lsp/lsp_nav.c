/* lsp/lsp_nav.c: definition, references, highlights and rename over the occurrence index of one checked graph. */
#include "lsp/lsp_nav.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "compiler/syntax/lex.h"
#include "tooling/doc_comment.h"
#include "base/file.h"
#include "base/path.h"
#include "lsp/lsp_nav_fallback.h"
#include "lsp/lsp_workspace.h"
#include "compiler/check/std_cache.h"
#include "compiler/project/project.h"
#include "tooling/facts.h"
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

static MsSpan uri_of(LspAnalysis *analysis, const LspDocList *docs, MsSpan path) {
  return lsp_path_uri(docs, analysis->arena, path);
}

static void write_place(MsStrBuild *out, const Place *place) {
  ms_strbuild_append_text(out, "{\"uri\":");
  lsp_json_string(out, place->uri);
  ms_strbuild_append_text(out, ",\"range\":");
  lsp_json_range(out, place->range);
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
      lsp_json_range(out, places->ptr[i].range);
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

/* A bundled declaration `selected` names (`symbol:@std/core.ms:<offset>` or `method:...`): the module's source and where the
 * declared name starts. The index lists only the user's modules, so these have no declaration occurrence. */
typedef struct StdDeclaration {
  MsSpan file, source; /* the module below `@std/`, and its text */
  size_t at;           /* the byte offset of the declared name */
} StdDeclaration;

static bool std_declaration(const LspAnalysis *analysis, const MsOccurrence *selected, StdDeclaration *out) {
  const MsSpan key = selected->key;
  size_t skip;
  if (ms_span_starts_with(key, ms_span_of_text("symbol:@std/"))) skip = 12;
  else if (ms_span_starts_with(key, ms_span_of_text("method:@std/"))) skip = 12;
  else return false;
  size_t colon = key.len;
  while (colon > skip && key.ptr[colon - 1] != ':') colon--;
  if (colon <= skip || colon == key.len) return false;
  size_t offset = 0;
  for (size_t i = colon; i < key.len; i++) {
    if (key.ptr[i] < '0' || key.ptr[i] > '9') return false;
    offset = offset * 10 + (size_t)(key.ptr[i] - '0');
  }
  const MsSpan file = ms_span_of(key.ptr + skip, colon - 1 - skip);
  const MsCheckProgram *program = &analysis->checked.program;
  for (size_t i = program->user_modules; i < program->modules.len; i++) {
    const MsSpan name = ms_names_span(program->names, program->modules.ptr[i].file);
    if (!ms_span_starts_with(name, ms_span_of_text("@std/")) || !ms_span_equal(ms_span_of(name.ptr + 5, name.len - 5), file)) continue;
    const MsSpan source = program->modules.ptr[i].source;
    size_t at;
    if (!lsp_header(source, offset, selected->name, &at)) return false;
    *out = (StdDeclaration){file, source, at};
    return true;
  }
  return false;
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

/* Hover on a literal or operator, which the occurrence index does not hold. Appends the reply and returns true when one
 * applies. */
static bool hover_expression(const LspAnalysis *analysis, const LspDoc *doc, size_t offset, MsStrBuild *out) {
  const MsCheckProgram *program = &analysis->checked.program;
  for (uint32_t m = 0; m < program->user_modules; m++) {
    if (!ms_span_equal(analysis->paths[m], ms_string_span(&doc->path))) continue;
    LspHoverFallback found;
    if (!lsp_hover_fallback(program->names, program->modules.ptr[m].tree, offset, &found)) return false;
    const MsTy ty = ms_facts_type(&program->modules.ptr[m].facts, found.node);
    const bool never = ty == MS_TY_NONE && lsp_match_never(found.expr);
    if (!never && (ty == MS_TY_NONE || ms_ty_is_invalid(&program->types, ty))) return false;
    MsStrBuild shown = ms_strbuild_new();
    if (never) ms_strbuild_append_text(&shown, "Never");
    else ms_ty_show_plain(&shown, program->names, &program->types, ty);
    MsStrBuild value = ms_strbuild_new();
    ms_strbuild_append_text(&value, "```manuscript\n");
    ms_strbuild_append(&value, found.text);
    ms_strbuild_append_text(&value, " ");
    ms_strbuild_append(&value, ms_strbuild_span(&shown));
    ms_strbuild_append_text(&value, "\n```");
    const MsSpan text = program->modules.ptr[m].source;
    ms_strbuild_append_text(out, "{\"contents\":{\"kind\":\"markdown\",\"value\":");
    lsp_json_string(out, ms_strbuild_span(&value));
    ms_strbuild_append_text(out, "},\"range\":");
    lsp_json_range(out, (LspRange){lsp_position(text, found.offset), lsp_position(text, found.end)});
    ms_strbuild_append_byte(out, '}');
    ms_strbuild_free(&shown);
    ms_strbuild_free(&value);
    return true;
  }
  return false;
}

/* The keyword a declared type is introduced with, or NULL when the occurrence is not a type. */
static const char *type_keyword(const MsCheckProgram *program, const MsOccurrence *selected) {
  if (selected->symbol == 0 || selected->symbol >= program->symbols.len) return NULL;
  const MsSymbol *symbol = &program->symbols.ptr[selected->symbol];
  if (symbol->kind != MS_SYMBOL_TYPE || symbol->decl == NULL) return NULL;
  switch (symbol->decl->kind) {
  case MS_D_ENUM: return "enum";
  case MS_D_INTERFACE: return "interface";
  case MS_D_TYPE:
  case MS_D_ALIAS: return "type";
  default: return NULL;
  }
}

void lsp_nav_hover(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out) {
  LspAnalysis analysis;
  const MsOccurrence *selected;
  if (!select(docs, doc, position, &analysis, &selected)) {
    size_t offset;
    if (analysis.resolved && lsp_offset(ms_string_span(&doc->text), position, false, &offset) &&
        hover_expression(&analysis, doc, offset, out)) {
      lsp_analysis_release(&analysis);
      return;
    }
    goto none;
  }
  const MsCheckProgram *program = &analysis.checked.program;
  if (selected->ty == MS_TY_NONE || ms_ty_is_invalid(&program->types, selected->ty)) goto none;
  MsStrBuild shown = ms_strbuild_new();
  ms_ty_show_plain(&shown, program->names, &program->types, selected->ty);
  MsStrBuild value = ms_strbuild_new();
  ms_strbuild_append_text(&value, "```manuscript\n");
  const char *keyword = type_keyword(program, selected);
  if (keyword != NULL) {
    /* A declared type reads as its declaration (`type List[T]`), not as a name followed by itself. */
    ms_strbuild_append_text(&value, keyword);
    ms_strbuild_append_text(&value, " ");
    ms_strbuild_append(&value, ms_strbuild_span(&shown));
  } else {
    ms_strbuild_append(&value, selected->name);
    ms_strbuild_append_text(&value, " ");
    ms_strbuild_append(&value, ms_strbuild_span(&shown));
  }
  ms_strbuild_append_text(&value, "\n```");
  const MsOccurrence *declaration = declaration_of(&analysis, selected);
  StdDeclaration bundled;
  if (declaration == NULL && std_declaration(&analysis, selected, &bundled)) {
    const size_t line = lsp_position(bundled.source, bundled.at).line + 1;
    if (ms_span_starts_with(ms_strbuild_span(&shown), ms_span_of_text("fn("))) {
      const MsInspection *inspection = lsp_inspection(&analysis, true);
      MsStrBuild file = ms_strbuild_new();
      ms_strbuild_append_text(&file, "@std/");
      ms_strbuild_append(&file, bundled.file);
      write_effects(&value, inspection, ms_strbuild_span(&file), line, selected->name);
      ms_strbuild_free(&file);
    }
    const MsSpan docs_text = ms_declaration_comment(analysis.arena, bundled.source, bundled.at, (uint32_t)line);
    if (docs_text.len > 0) {
      ms_strbuild_append_text(&value, "\n\n");
      ms_strbuild_append(&value, docs_text);
    }
  }
  if (declaration != NULL) {
    const MsSpan source = source_of(&analysis, declaration);
    const size_t line = lsp_position(source, declaration->offset).line + 1;
    if (ms_span_starts_with(ms_strbuild_span(&shown), ms_span_of_text("fn("))) {
      const MsInspection *inspection = lsp_inspection(&analysis, false);
      write_effects(&value, inspection,
                    ms_names_span(program->names, program->modules.ptr[declaration->module].file), line, selected->name);
    }
    const MsSpan docs_text = ms_declaration_comment(analysis.arena, source, declaration->offset, (uint32_t)line);
    if (docs_text.len > 0) {
      ms_strbuild_append_text(&value, "\n\n");
      ms_strbuild_append(&value, docs_text);
    }
  }
  const MsSpan text = source_of(&analysis, selected);
  ms_strbuild_append_text(out, "{\"contents\":{\"kind\":\"markdown\",\"value\":");
  lsp_json_string(out, ms_strbuild_span(&value));
  ms_strbuild_append_text(out, "},\"range\":");
  lsp_json_range(out, (LspRange){lsp_position(text, selected->offset), lsp_position(text, selected->end)});
  ms_strbuild_append_byte(out, '}');
  ms_strbuild_free(&shown);
  ms_strbuild_free(&value);
  lsp_analysis_release(&analysis);
  return;
none:
  ms_strbuild_append_text(out, "null");
  lsp_analysis_release(&analysis);
}

/* The start of the file an `import ... from "path"` names, when the cursor is inside the path's quotes. */
static bool import_path_definition(LspAnalysis *analysis, const LspDocList *docs, const LspDoc *doc, size_t cursor,
                                   MsStrBuild *out) {
  const MsCheckProgram *program = &analysis->checked.program;
  const MsSpan text = ms_string_span(&doc->text);
  for (uint32_t m = 0; m < program->user_modules; m++) {
    if (!ms_span_equal(analysis->paths[m], ms_string_span(&doc->path))) continue;
    const MsModule *tree = program->modules.ptr[m].tree;
    for (uint32_t i = 0; i < tree->nimports; i++) {
      size_t open = tree->imports[i].clause.offset;
      while (open < text.len && text.ptr[open] != '"') open++;
      size_t close = open + 1;
      while (close < text.len && text.ptr[close] != '"') close++;
      if (open >= text.len || close >= text.len || cursor <= open || cursor > close) continue;
      const MsSpan written = ms_span_of(text.ptr + open + 1, close - open - 1);
      if (ms_span_starts_with(written, ms_span_of_text("@std/"))) {
        ms_strbuild_append_text(out, "[{\"uri\":\"manuscript-stdlib:///");
        ms_strbuild_append(out, ms_span_of(written.ptr + 5, written.len - 5));
        ms_strbuild_append_text(out, "\",\"range\":");
        lsp_json_range(out, (LspRange){{0, 0}, {0, 0}});
        ms_strbuild_append_text(out, "}]");
        return true;
      }
      MsStrBuild joined = ms_strbuild_new();
      ms_path_join(ms_path_parent(ms_string_span(&doc->path)), ms_span_of(text.ptr + open + 1, close - open - 1), &joined);
      MsStrBuild cleaned = ms_strbuild_new();
      ms_path_clean(&cleaned, ms_strbuild_span(&joined));
      bool found = false;
      for (size_t g = 0; g < analysis->checked.graph.count && !found; g++) {
        const MsSpan target = analysis->checked.graph.modules[g].path;
        if (!ms_span_equal(target, ms_strbuild_span(&cleaned))) continue;
        bool exists = analysis->checked.graph.modules[g].source.len > 0;
        for (size_t d = 0; d < docs->len && !exists; d++) exists = ms_span_equal(target, ms_string_span(&docs->ptr[d].path));
        if (!exists) continue; /* an import of a file that is not there stands for it with an empty module */
        found = true;
        ms_strbuild_append_text(out, "[{\"uri\":");
        lsp_json_string(out, uri_of(analysis, docs, target));
        ms_strbuild_append_text(out, ",\"range\":");
        lsp_json_range(out, (LspRange){{0, 0}, {0, 0}});
        ms_strbuild_append_text(out, "}]");
      }
      ms_strbuild_free(&joined);
      ms_strbuild_free(&cleaned);
      return found;
    }
  }
  return false;
}

/* `self` has no occurrence of its own; the oracle sends it to the start of the name of the method it is written in. */
static bool self_definition(LspAnalysis *analysis, const LspDocList *docs, const LspDoc *doc, size_t cursor, MsStrBuild *out) {
  const MsSpan text = ms_string_span(&doc->text);
  size_t start = cursor, end = cursor;
  while (start > 0 && (isalnum(text.ptr[start - 1]) || text.ptr[start - 1] == '_')) start--;
  while (end < text.len && (isalnum(text.ptr[end]) || text.ptr[end] == '_')) end++;
  if (!ms_span_is_text(ms_span_of(text.ptr + start, end - start), "self")) return false;
  const MsCheckProgram *program = &analysis->checked.program;
  for (uint32_t m = 0; m < program->user_modules; m++) {
    if (!ms_span_equal(analysis->paths[m], ms_string_span(&doc->path))) continue;
    const MsModule *tree = program->modules.ptr[m].tree;
    const MsMethod *enclosing = NULL;
    for (uint32_t d = 0; d < tree->ndecls; d++) {
      const MsDecl *decl = tree->decls[d];
      if (decl->kind != MS_D_IMPL) continue;
      for (uint32_t i = 0; i < decl->u.impl.methods.len; i++) {
        const MsMethod *method = decl->u.impl.methods.ptr[i];
        if (method->pos.offset <= start && (enclosing == NULL || method->pos.offset > enclosing->pos.offset)) enclosing = method;
      }
    }
    size_t at;
    if (enclosing == NULL || !lsp_header(text, enclosing->pos.offset, ms_names_span(program->names, enclosing->func.name), &at)) return false;
    const LspPosition place = lsp_position(text, at);
    ms_strbuild_append_text(out, "[{\"uri\":");
    lsp_json_string(out, uri_of(analysis, docs, ms_string_span(&doc->path)));
    ms_strbuild_append_text(out, ",\"range\":");
    lsp_json_range(out, (LspRange){place, place});
    ms_strbuild_append_text(out, "}]");
    return true;
  }
  return false;
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
    StdDeclaration bundled;
    if (std_declaration(&analysis, selected, &bundled)) {
      ms_strbuild_append_text(out, "[{\"uri\":\"manuscript-stdlib:///");
      ms_strbuild_append(out, bundled.file);
      ms_strbuild_append_text(out, "\",\"range\":");
      lsp_json_range(out, (LspRange){lsp_position(bundled.source, bundled.at), lsp_position(bundled.source, bundled.at + selected->name.len)});
      ms_strbuild_append_text(out, "}]");
      lsp_analysis_release(&analysis);
      return;
    }
  }
  size_t cursor;
  if (analysis.resolved && lsp_offset(ms_string_span(&doc->text), position, false, &cursor) &&
      (import_path_definition(&analysis, docs, doc, cursor, out) || self_definition(&analysis, docs, doc, cursor, out))) {
    lsp_analysis_release(&analysis);
    return;
  }
  ms_strbuild_append_text(out, "null");
  lsp_analysis_release(&analysis);
}

/* Whether uses of `selected` can sit in files outside the document's own graph: not a local, not a private function. */
static bool crosses_files(const LspAnalysis *analysis, const MsOccurrence *selected) {
  if (ms_span_starts_with(selected->key, ms_span_of_text("binding:")) || ms_span_starts_with(selected->key, ms_span_of_text("parameter:"))) {
    return false;
  }
  const MsCheckProgram *program = &analysis->checked.program;
  if (selected->symbol != 0 && program->symbols.ptr[selected->symbol].kind == MS_SYMBOL_FN && !program->symbols.ptr[selected->symbol].exported) {
    return false;
  }
  return true;
}

/* Adds the places of `selected`'s identity found by checking every other file of the project that mentions its name. */
static void workspace_places(LspAnalysis *analysis, const LspDocList *docs, const LspDoc *doc, const MsOccurrence *selected, bool include,
                             PlaceList *places) {
  MsSpanList paths = {0};
  lsp_workspace_files(analysis->arena, ms_string_span(&doc->path), &paths);
  for (size_t i = 0; i < paths.len; i++) {
    if (ms_span_equal(paths.ptr[i], ms_string_span(&doc->path))) continue;
    MsBytes bytes = {0};
    MsSpan text = {0};
    for (size_t d = 0; d < docs->len; d++) {
      if (ms_span_equal(ms_string_span(&docs->ptr[d].path), paths.ptr[i])) text = ms_string_span(&docs->ptr[d].text);
    }
    const bool on_disk = text.ptr == NULL && ms_file_read(paths.ptr[i], &bytes);
    if (on_disk) text = ms_bytes_span(&bytes);
    const bool mentions = text.ptr != NULL && lsp_text_mentions(text, selected->name);
    if (on_disk) ms_bytes_free(&bytes);
    if (!mentions) continue;
    LspDoc entry = {.path = ms_string_from_span(paths.ptr[i])};
    LspAnalysis other;
    lsp_analyze_scan(docs, &entry, &other);
    for (size_t e = 0; other.resolved && e < other.index.len; e++) {
      const MsOccurrence *candidate = &other.index.ptr[e];
      if (!ms_span_equal(candidate->key, selected->key) || (!include && candidate->declaration)) continue;
      const MsSpan source = source_of(&other, candidate);
      place_list_push(places, (Place){uri_of(analysis, docs, other.paths[candidate->module]),
                                      {lsp_position(source, candidate->offset), lsp_position(source, candidate->end)}});
    }
    lsp_analysis_release(&other);
    ms_string_release(&entry.path);
  }
  ms_span_list_free(&paths);
}

/* The import clauses in the bundled modules that name the std symbol `selected`: the parsed-std cache holds every bundled
 * module, so this reads trees already built and loads nothing. Uses inside those modules are not indexed. */
static void std_import_places(LspAnalysis *analysis, const MsOccurrence *selected, PlaceList *places) {
  StdDeclaration bundled;
  const MsStdCache *cache = analysis->checked.std_cache;
  if (cache == NULL || !std_declaration(analysis, selected, &bundled)) return;
  MsStrBuild want = ms_strbuild_new();
  ms_strbuild_append_text(&want, "@std/");
  ms_strbuild_append(&want, bundled.file);
  size_t count = 0;
  const MsStdSource *sources = ms_std_sources(&count);
  const MsNames *names = ms_std_cache_names(cache);
  for (size_t i = 0; i < count; i++) {
    MsStrBuild path = ms_strbuild_new();
    ms_strbuild_append_text(&path, "@std/");
    ms_strbuild_append(&path, sources[i].name);
    MsName file;
    const bool known = ms_names_find(names, ms_strbuild_span(&path), &file);
    ms_strbuild_free(&path);
    const MsModule *tree = known ? ms_std_cache_tree(cache, file) : NULL;
    for (uint32_t n = 0; tree != NULL && n < tree->nimports; n++) {
      const MsImport *import = &tree->imports[n];
      if (!ms_span_equal(import->path, ms_strbuild_span(&want)) ||
          !ms_span_equal(ms_names_span(names, import->name), selected->name))
        continue;
      MsStrBuild uri = ms_strbuild_new();
      ms_strbuild_append_text(&uri, "manuscript-stdlib:///");
      ms_strbuild_append(&uri, sources[i].name);
      const MsSpan text = ms_arena_copy(analysis->arena, ms_strbuild_span(&uri));
      ms_strbuild_free(&uri);
      place_list_push(places, (Place){text,
                                      {lsp_position(sources[i].text, import->name_pos.offset),
                                       lsp_position(sources[i].text, import->name_pos.offset + selected->name.len)}});
    }
  }
  ms_strbuild_free(&want);
}

void lsp_nav_references(const LspDocList *docs, const LspDoc *doc, LspPosition position, bool include_declaration,
                        MsStrBuild *out) {
  LspAnalysis analysis;
  const MsOccurrence *selected;
  PlaceList places = {0};
  if (select(docs, doc, position, &analysis, &selected)) {
    collect_places(&analysis, docs, selected, include_declaration, false, doc, &places);
    if (crosses_files(&analysis, selected)) workspace_places(&analysis, docs, doc, selected, include_declaration, &places);
    std_import_places(&analysis, selected, &places);
    if (places.len > 1) qsort(places.ptr, places.len, sizeof(Place), compare_place);
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

typedef struct RenameFile {
  MsSpan path, uri, source;
  EditList edits;
} RenameFile;

MS_LIST_DEFINE(RenameFileList, rename_file_list, RenameFile)

typedef struct RenameEntry {
  MsSpan path;
} RenameEntry;

MS_LIST_DEFINE(RenameEntryList, rename_entry_list, RenameEntry)

static RenameFile *rename_file(RenameFileList *files, MsSpan path) {
  for (size_t i = 0; i < files->len; i++) {
    if (ms_span_equal(files->ptr[i].path, path)) return &files->ptr[i];
  }
  rename_file_list_push(files, (RenameFile){.path = path});
  return &files->ptr[files->len - 1];
}

static void add_edit(RenameFile *file, const MsOccurrence *entry) {
  for (size_t e = 0; e < file->edits.len; e++) {
    if (file->edits.ptr[e].start == entry->offset) return;
  }
  edit_list_push(&file->edits, (Edit){entry->offset, entry->end});
}

static int compare_rename_file(const void *left, const void *right) {
  const RenameFile *a = left, *b = right;
  const int64_t order = ms_span_compare(a->uri, b->uri);
  return order == 0 ? 0 : (order < 0 ? -1 : 1);
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
  if (ms_span_find(selected->key, ms_span_of_text(":@std/"), &(size_t){0}) || ms_span_starts_with(selected->key, ms_span_of_text("native:"))) {
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
    lsp_json_range(out, (LspRange){lsp_position(source, selected->offset), lsp_position(source, selected->end)});
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
  /* The files holding the identity: those of the document's graph, then the other files of the project that name it. */
  RenameFileList files = {0};
  for (size_t i = 0; i < analysis.index.len; i++) {
    const MsOccurrence *entry = &analysis.index.ptr[i];
    if (!ms_span_equal(entry->key, selected->key)) continue;
    RenameFile *file = rename_file(&files, analysis.paths[entry->module]);
    if (file->source.ptr == NULL) {
      file->source = source_of(&analysis, entry);
      file->uri = uri_of(&analysis, docs, file->path);
    }
    add_edit(file, entry);
  }
  RenameEntryList entries = {0};
  if (crosses_files(&analysis, selected)) {
    MsSpanList paths = {0};
    lsp_workspace_files(analysis.arena, ms_string_span(&doc->path), &paths);
    for (size_t i = 0; i < paths.len; i++) {
      if (ms_span_equal(paths.ptr[i], ms_string_span(&doc->path))) continue;
      MsBytes bytes = {0};
      MsSpan text = {0};
      for (size_t d = 0; d < docs->len; d++) {
        if (ms_span_equal(ms_string_span(&docs->ptr[d].path), paths.ptr[i])) text = ms_string_span(&docs->ptr[d].text);
      }
      const bool on_disk = text.ptr == NULL && ms_file_read(paths.ptr[i], &bytes);
      if (on_disk) text = ms_bytes_span(&bytes);
      const bool mentions = text.ptr != NULL && lsp_text_mentions(text, selected->name);
      if (on_disk) ms_bytes_free(&bytes);
      if (!mentions) continue;
      LspDoc entry_doc = {.path = ms_string_from_span(paths.ptr[i])};
      LspAnalysis other;
      lsp_analyze_scan(docs, &entry_doc, &other);
      bool affected = false;
      for (size_t e = 0; other.resolved && e < other.index.len; e++) {
        const MsOccurrence *candidate = &other.index.ptr[e];
        if (!ms_span_equal(candidate->key, selected->key)) continue;
        affected = true;
        const MsSpan path = ms_arena_copy(analysis.arena, other.paths[candidate->module]);
        RenameFile *file = rename_file(&files, path);
        if (file->source.ptr == NULL) {
          file->source = ms_arena_copy(analysis.arena, source_of(&other, candidate));
          file->uri = uri_of(&analysis, docs, path);
        }
        add_edit(file, candidate);
      }
      if (affected) {
        /* The file this scan checked on its own must check cleanly after the rename too. */
        rename_entry_list_push(&entries, (RenameEntry){ms_arena_copy(analysis.arena, ms_string_span(&entry_doc.path))});
      }
      lsp_analysis_release(&other);
      ms_string_release(&entry_doc.path);
    }
    ms_span_list_free(&paths);
  }
  qsort(files.ptr, files.len, sizeof(RenameFile), compare_rename_file);
  /* Apply the edits to a copy of every file, so the result can be checked before it is proposed. */
  MsOverlayFile *changed = MS_ARENA_NEW_ARRAY(analysis.arena, MsOverlayFile, files.len + 1);
  MsStrBuild body = ms_strbuild_new();
  ms_strbuild_append_text(&body, "{\"documentChanges\":[");
  for (size_t f = 0; f < files.len; f++) {
    RenameFile *file = &files.ptr[f];
    const MsSpan source = file->source;
    if (occurs(source, new_name)) {
      ms_strbuild_printf(error, "%.*s already occurs in %.*s; rename could capture another binding", (int)new_name.len,
                         new_name.ptr, (int)file->path.len, file->path.ptr);
      ms_strbuild_free(&body);
      goto release;
    }
    EditList edits = file->edits;
    qsort(edits.ptr, edits.len, sizeof(Edit), compare_edit_descending);
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append(&text, source);
    if (f > 0) ms_strbuild_append_byte(&body, ',');
    ms_strbuild_append_text(&body, "{\"textDocument\":{\"uri\":");
    lsp_json_string(&body, file->uri);
    ms_strbuild_append_text(&body, ",\"version\":");
    const LspDoc *opened = lsp_doc_find(docs, file->uri);
    if (opened != NULL) ms_strbuild_printf(&body, "%lld", (long long)opened->version);
    else ms_strbuild_append_text(&body, "null");
    ms_strbuild_append_text(&body, "},\"edits\":[");
    for (size_t e = 0; e < edits.len; e++) {
      if (edits.ptr[e].end > source.len) {
        refuse(error, "source revision changed");
        ms_strbuild_free(&body);
        ms_strbuild_free(&text);
        goto release;
      }
      if (e > 0) ms_strbuild_append_byte(&body, ',');
      ms_strbuild_append_text(&body, "{\"range\":");
      lsp_json_range(&body, (LspRange){lsp_position(source, edits.ptr[e].start), lsp_position(source, edits.ptr[e].end)});
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
    changed[f] = (MsOverlayFile){file->path, ms_arena_copy(analysis.arena, ms_strbuild_span(&text))};
    ms_strbuild_free(&text);
  }
  ms_strbuild_append_text(&body, "]}");
  ok = lsp_rename_stays_checked(docs, doc, changed, files.len, error);
  for (size_t i = 0; ok && i < entries.len; i++) {
    LspDoc entry_doc = {.path = ms_string_from_span(entries.ptr[i].path)};
    ok = lsp_rename_stays_checked(docs, &entry_doc, changed, files.len, error);
    ms_string_release(&entry_doc.path);
  }
  if (ok) ms_strbuild_append(out, ms_strbuild_span(&body));
  ms_strbuild_free(&body);
release:
  for (size_t f = 0; f < files.len; f++) edit_list_free(&files.ptr[f].edits);
  rename_file_list_free(&files);
  rename_entry_list_free(&entries);
done:
  lsp_analysis_release(&analysis);
  return ok;
}

void lsp_nav_type_definition(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out) {
  LspAnalysis analysis;
  const MsOccurrence *selected;
  if (select(docs, doc, position, &analysis, &selected) && selected->ty != MS_TY_NONE) {
    const MsCheckProgram *program = &analysis.checked.program;
    const MsTyRow *row = ms_ty_row(&program->types, selected->ty);
    if (row->def != 0 && row->kind != MS_TY_VARIABLE) {
      const MsSymbolId symbol = ms_defs_get(&program->defs, row->def)->symbol;
      for (size_t i = 0; i < analysis.index.len; i++) {
        const MsOccurrence *entry = &analysis.index.ptr[i];
        if (!entry->declaration || entry->symbol != symbol) continue;
        const Place place = place_of(&analysis, docs, entry);
        ms_strbuild_append_byte(out, '[');
        write_place(out, &place);
        ms_strbuild_append_byte(out, ']');
        lsp_analysis_release(&analysis);
        return;
      }
      /* A type of the bundled library has no occurrence in the index: point into its module. */
      const MsSymbol *declared = &program->symbols.ptr[symbol];
      const MsSpan file = ms_names_span(program->names, program->modules.ptr[declared->module].file);
      size_t at;
      if (declared->module >= program->user_modules && declared->decl != NULL && ms_span_starts_with(file, ms_span_of_text("@std/")) &&
          lsp_header(program->modules.ptr[declared->module].source, declared->decl->pos.offset, ms_names_span(program->names, declared->name), &at)) {
        const MsSpan source = program->modules.ptr[declared->module].source;
        const size_t name_length = ms_names_span(program->names, declared->name).len;
        ms_strbuild_append_text(out, "[{\"uri\":\"manuscript-stdlib:///");
        ms_strbuild_append(out, ms_span_of(file.ptr + 5, file.len - 5));
        ms_strbuild_append_text(out, "\",\"range\":");
        lsp_json_range(out, (LspRange){lsp_position(source, at), lsp_position(source, at + name_length)});
        ms_strbuild_append_text(out, "}]");
        lsp_analysis_release(&analysis);
        return;
      }
    }
  }
  ms_strbuild_append_text(out, "null");
  lsp_analysis_release(&analysis);
}

typedef struct Hint {
  LspPosition at;
  MsSpan label;
} Hint;

MS_LIST_DEFINE(HintList, hint_list, Hint)

static int compare_hint(const void *left, const void *right) {
  const Hint *a = left, *b = right;
  if (a->at.line != b->at.line) return a->at.line < b->at.line ? -1 : 1;
  return a->at.character == b->at.character ? 0 : (a->at.character < b->at.character ? -1 : 1);
}

/* Whether the text after a binding's name starts a plain binding (`:=` or `=`), which has no written type. */
static bool binds_inferred(MsSpan source, size_t end) {
  while (end < source.len && (source.ptr[end] == ' ' || source.ptr[end] == '\t')) end++;
  if (end >= source.len) return false;
  if (source.ptr[end] == ':') return end + 1 < source.len && source.ptr[end + 1] == '=';
  return source.ptr[end] == '=' && !(end + 1 < source.len && source.ptr[end + 1] == '=');
}

void lsp_nav_inlay_hints(const LspDocList *docs, const LspDoc *doc, LspRange range, MsStrBuild *out) {
  LspAnalysis analysis;
  lsp_analyze(docs, doc, &analysis);
  HintList hints = {0};
  const MsCheckProgram *program = &analysis.checked.program;
  for (size_t i = 0; analysis.resolved && i < analysis.index.len; i++) {
    const MsOccurrence *entry = &analysis.index.ptr[i];
    if (!entry->declaration || !ms_span_starts_with(entry->key, ms_span_of_text("binding:")) ||
        ms_span_starts_with(entry->key, ms_span_of_text("binding:typeparam:")) ||
        !ms_span_equal(analysis.paths[entry->module], ms_string_span(&doc->path))) {
      continue;
    }
    const MsSpan source = source_of(&analysis, entry);
    if (entry->ty == MS_TY_NONE || ms_ty_is_invalid(&program->types, entry->ty) || !binds_inferred(source, entry->end)) continue;
    const LspPosition at = lsp_position(source, entry->end);
    const bool after_start = at.line > range.start.line || (at.line == range.start.line && at.character >= range.start.character);
    const bool before_end = at.line < range.end.line || (at.line == range.end.line && at.character <= range.end.character);
    if (!after_start || !before_end) continue;
    MsStrBuild label = ms_strbuild_new();
    ms_strbuild_append_text(&label, " ");
    ms_ty_show_plain(&label, program->names, &program->types, entry->ty);
    hint_list_push(&hints, (Hint){at, ms_arena_copy(analysis.arena, ms_strbuild_span(&label))});
    ms_strbuild_free(&label);
  }
  if (hints.len > 1) qsort(hints.ptr, hints.len, sizeof(Hint), compare_hint);
  ms_strbuild_append_byte(out, '[');
  for (size_t i = 0; i < hints.len; i++) {
    if (i > 0) ms_strbuild_append_byte(out, ',');
    ms_strbuild_printf(out, "{\"position\":{\"line\":%zu,\"character\":%zu},\"label\":", hints.ptr[i].at.line,
                       hints.ptr[i].at.character);
    lsp_json_string(out, hints.ptr[i].label);
    ms_strbuild_append_text(out, ",\"kind\":1,\"paddingLeft\":false,\"paddingRight\":false}");
  }
  ms_strbuild_append_byte(out, ']');
  hint_list_free(&hints);
  lsp_analysis_release(&analysis);
}
