/* cli/lsp_analysis.c: open documents and their diagnostics. Each document is checked as the entry of its own graph, with
 * every open document's unsaved text in place of disk, and only the findings that sit in that document are shown. */
#include "cli/lsp_analysis.h"

#include <stdlib.h>
#include <string.h>

#include "base/arena.h"
#include "base/file.h"
#include "base/path.h"
#include "base/message.h"
#include "cli/checked_input.h"
#include "compiler/check/std_cache.h"
#include "cli/findings.h"
#include "cli/lsp_internal.h"
#include "compiler/syntax/diag.h"
#include "tooling/lint.h"

MsSpan lsp_path_uri(const LspDocList *docs, MsArena *arena, MsSpan path) {
  for (size_t i = 0; i < docs->len; i++) {
    if (ms_span_equal(ms_string_span(&docs->ptr[i].path), path)) return ms_arena_copy(arena, ms_string_span(&docs->ptr[i].uri));
  }
  MsStrBuild uri = ms_strbuild_new();
  lsp_file_uri(path, &uri);
  const MsSpan copy = ms_message_take_builder(arena, &uri);
  return copy;
}

/* Moves on whenever an open document changes, so cached analyses stop matching. */
static uint64_t generation = 1;

/* The files whose open text changed since the diagnostics were last published, one path per line, and whether
 * something unnamed changed. A document whose last diagnostics did not read any of them keeps its diagnostics. */
static MsStrBuild changed_files;
static bool everything_changed;

static void note_changed(MsSpan path) {
  ms_strbuild_append(&changed_files, path);
  ms_strbuild_append_byte(&changed_files, '\n');
}

/* Whether a line of `lines` equals `path`. */
static bool has_line(MsSpan lines, MsSpan path) {
  size_t start = 0;
  for (size_t i = 0; i <= lines.len; i++) {
    if (i < lines.len && lines.ptr[i] != '\n') continue;
    if (i - start == path.len && ms_span_equal((MsSpan){lines.ptr + start, i - start}, path)) return true;
    start = i + 1;
  }
  return false;
}

/* Whether the diagnostics of `doc` can have changed since they were published. */
static bool needs_analysis(const LspDoc *doc) {
  if (everything_changed || doc->dirty || ms_string_span(&doc->deps).len == 0) return true;
  const MsSpan deps = ms_string_span(&doc->deps);
  const MsSpan changed = ms_strbuild_span(&changed_files);
  size_t start = 0;
  for (size_t i = 0; i <= changed.len; i++) {
    if (i < changed.len && changed.ptr[i] != '\n') continue;
    if (i > start && has_line(deps, (MsSpan){changed.ptr + start, i - start})) return true;
    start = i + 1;
  }
  return false;
}

LspDoc *lsp_doc_find(const LspDocList *docs, MsSpan uri) {
  for (size_t i = 0; i < docs->len; i++) {
    if (ms_span_equal(ms_string_span(&docs->ptr[i].uri), uri)) return &docs->ptr[i];
  }
  return NULL;
}

void lsp_doc_set(LspDocList *docs, MsSpan uri, int64_t version, MsSpan text) {
  LspDoc *doc = lsp_doc_find(docs, uri);
  if (doc == NULL) {
    MsStrBuild path = ms_strbuild_new();
    if (lsp_uri_is_standard_library(uri)) {
      /* A bundled module is checked as a file of its own in the temporary directory, which exists on every host; its text
       * comes from the overlay. */
      MsString temp = ms_temp_dir();
      ms_strbuild_append(&path, ms_string_span(&temp));
      ms_string_release(&temp);
      ms_strbuild_append_text(&path, "/" LSP_BUNDLED_PREFIX);
      const MsSpan prefix = ms_span_of_text("manuscript-stdlib:///");
      if (ms_span_starts_with(uri, prefix)) {
        for (size_t i = prefix.len; i < uri.len; i++) ms_strbuild_append_byte(&path, uri.ptr[i] == '/' ? '-' : uri.ptr[i]);
      }
    } else {
      lsp_uri_filename(uri, &path);
    }
    lsp_doc_list_push(docs, (LspDoc){.uri = ms_string_from_span(uri), .path = ms_strbuild_finish(&path)});
    doc = &docs->ptr[docs->len - 1];
  }
  const MsString text_copy = ms_string_from_span(text); /* `text` may alias the old text */
  ms_string_release(&doc->text);
  doc->text = text_copy;
  doc->version = version;
  doc->dirty = true;
  note_changed(ms_string_span(&doc->path));
  generation++;
}

void lsp_doc_remove(LspDocList *docs, MsSpan uri) {
  for (size_t i = 0; i < docs->len; i++) {
    LspDoc *doc = &docs->ptr[i];
    if (!ms_span_equal(ms_string_span(&doc->uri), uri)) continue;
    MsString gone = doc->path;
    ms_string_release(&doc->uri);
    ms_string_release(&doc->text);
    ms_string_release(&doc->published);
    ms_string_release(&doc->deps);
    memmove(doc, doc + 1, (docs->len - i - 1) * sizeof *doc);
    docs->len--;
    note_changed(ms_string_span(&gone));
    ms_string_release(&gone);
    generation++;
    return;
  }
}

MsSpan lsp_absolute_file(MsArena *arena, MsSpan source_root, MsSpan file) {
  if (ms_path_is_absolute(file) || source_root.len == 0) return file;
  MsStrBuild joined = ms_strbuild_new();
  ms_path_append_joined(&joined, source_root, file);
  const MsSpan result = ms_message_take_builder(arena, &joined);
  return result;
}

/* The latest analyses, one per entry file, valid while no open document changed (`generation`). */
enum { CACHE_SLOTS = 8 };

typedef struct CacheSlot {
  LspAnalysis value;
  MsString path;
  uint64_t generation, used;
  bool valid;
} CacheSlot;

static CacheSlot cache[CACHE_SLOTS];
static uint64_t clock_tick;

void lsp_analysis_invalidate(void) {
  generation++;
  everything_changed = true;
}

void lsp_analyze(const LspDocList *docs, const LspDoc *doc, LspAnalysis *out) {
  CacheSlot *victim = &cache[0];
  for (size_t i = 0; i < CACHE_SLOTS; i++) {
    CacheSlot *slot = &cache[i];
    if (slot->valid && slot->generation == generation && ms_string_equal(&slot->path, &doc->path)) {
      slot->used = ++clock_tick;
      *out = slot->value;
      out->cached = true;
      return;
    }
    if (!slot->valid || (victim->valid && slot->used < victim->used)) victim = slot;
  }
  if (victim->valid) {
    lsp_analysis_release(&victim->value);
    ms_string_release(&victim->path);
  }
  lsp_analyze_changed(docs, doc, NULL, 0, &victim->value);
  victim->path = ms_string_from_span(ms_string_span(&doc->path));
  victim->generation = generation;
  victim->used = ++clock_tick;
  victim->valid = true;
  *out = victim->value;
  out->cached = true;
}

/* The bundled modules parsed once for the session: the editor checks after every keystroke, and parsing them was a fifth
 * of each check. The server analyzes on one thread, and the cache is never written once built. */
static const MsStdCache *lsp_std_cache(void) {
  static MsStdCache *std;
  if (std == NULL) {
    std = ms_std_cache_new();
  }
  return std;
}

void lsp_analyze_changed(const LspDocList *docs, const LspDoc *doc, const MsOverlayFile *changed, size_t count,
                         LspAnalysis *out) {
  *out = (LspAnalysis){.arena = malloc(sizeof *out->arena)};
  *out->arena = ms_arena_new();
  out->checked.std_cache = lsp_std_cache();
  MsOverlayFile *files = malloc((docs->len + count + 1) * sizeof *files);
  size_t total = 0;
  for (size_t i = 0; i < docs->len; i++) {
    files[total] = (MsOverlayFile){ms_string_span(&docs->ptr[i].path), ms_string_span(&docs->ptr[i].text)};
    for (size_t c = 0; c < count; c++) {
      if (ms_span_equal(changed[c].path, files[total].path)) files[total].text = changed[c].text;
    }
    total++;
  }
  for (size_t c = 0; c < count; c++) {
    bool open = false;
    for (size_t i = 0; i < docs->len; i++) open |= ms_span_equal(changed[c].path, ms_string_span(&docs->ptr[i].path));
    if (!open) files[total++] = changed[c];
  }
  out->overlay = files;
  const MsOverlay overlay = {files, total};
  const MsLoadOptions options = {.overlay = &overlay, .recover = true};
  (void)ms_checked_input_load_with(out->arena, &out->checked, ms_string_span(&doc->path), MS_INPUT_ANALYSIS, &options);
  if (!out->checked.checked) return;
  const MsCheckProgram *program = &out->checked.program;
  out->resolved = true;
  out->index = ms_occurrence_index_with_types(out->arena, &out->checked.program, &out->written);
  out->paths = MS_ARENA_NEW_ARRAY(out->arena, MsSpan, program->user_modules == 0 ? 1 : program->user_modules);
  for (uint32_t m = 0; m < program->user_modules; m++) {
    const MsSpan name = ms_names_span(program->names, program->modules.ptr[m].file);
    out->paths[m] = lsp_absolute_file(out->arena, out->checked.graph.source_root, name);
    for (size_t g = 0; g < out->checked.graph.count; g++) {
      if (ms_span_equal(out->checked.graph.modules[g].name, name)) out->paths[m] = out->checked.graph.modules[g].path;
    }
  }
}

bool lsp_rename_stays_checked(const LspDocList *docs, const LspDoc *doc, const MsOverlayFile *changed, size_t count,
                              MsStrBuild *error) {
  LspAnalysis before;
  lsp_analyze(docs, doc, &before);
  const bool clean = before.resolved && before.checked.findings.len == 0;
  lsp_analysis_release(&before);
  if (!clean) {
    ms_strbuild_printf(error, "rename requires a clean workspace: %.*s", (int)ms_string_length(&doc->path), (const char *)ms_string_span(&doc->path).ptr);
    return false;
  }
  LspAnalysis after;
  lsp_analyze_changed(docs, doc, changed, count, &after);
  const bool kept = after.resolved && after.checked.findings.len == 0;
  if (!kept) {
    const MsSpan message = after.checked.findings.len > 0 ? after.checked.findings.ptr[0].diag.message
                                                         : ms_span_of_text("unknown checking failure");
    ms_strbuild_printf(error, "rename would break %.*s: %.*s", (int)ms_string_length(&doc->path), (const char *)ms_string_span(&doc->path).ptr,
                       (int)message.len, (const char *)message.ptr);
  }
  lsp_analysis_release(&after);
  return kept;
}

void lsp_analysis_release(LspAnalysis *analysis) {
  if (analysis->cached) return;
  ms_checked_input_free(&analysis->checked);
  ms_arena_free(analysis->arena);
  free(analysis->arena);
  free(analysis->overlay);
}

static void append_diagnostic(MsStrBuild *out, bool *first, MsSpan source, const Finding *finding) {
  const LspRange range = lsp_diagnostic_range(source, finding->diag.pos.offset);
  if (!*first) ms_strbuild_append_byte(out, ',');
  *first = false;
  ms_strbuild_printf(out, "{\"range\":{\"start\":{\"line\":%zu,\"character\":%zu},\"end\":{\"line\":%zu,\"character\":%zu}},",
                     range.start.line, range.start.character, range.end.line, range.end.character);
  ms_strbuild_append_text(out, "\"severity\":1,\"source\":\"manuscript\",\"code\":");
  lsp_json_string(out, ms_span_of_text(finding_code(finding)));
  ms_strbuild_append_text(out, ",\"message\":");
  lsp_json_string(out, finding->diag.message);
  ms_strbuild_append_byte(out, '}');
}

/* The diagnostics of `doc` as the elements of a JSON array. */
static MsString diagnostics_of(LspDoc *doc, const LspDocList *docs) {
  LspAnalysis analysis;
  lsp_analyze(docs, doc, &analysis);
  /* The files these diagnostics are computed from; unknown when the program did not load. */
  ms_string_release(&doc->deps);
  doc->deps = ms_string_from_span(ms_span_of_text(""));
  if (analysis.resolved) {
    MsStrBuild deps = ms_strbuild_new();
    for (size_t g = 0; g < analysis.checked.graph.count; g++) {
      ms_strbuild_append(&deps, analysis.checked.graph.modules[g].path);
      ms_strbuild_append_byte(&deps, '\n');
    }
    ms_strbuild_append(&deps, ms_string_span(&doc->path));
    ms_strbuild_append_byte(&deps, '\n');
    ms_string_release(&doc->deps);
    doc->deps = ms_strbuild_finish(&deps);
  }
  MsStrBuild out = ms_strbuild_new();
  bool first = true;
  const MsSpan source = ms_string_span(&doc->text);
  for (size_t i = 0; i < analysis.checked.findings.len; i++) {
    const Finding *finding = &analysis.checked.findings.ptr[i];
    const MsSpan file = lsp_absolute_file(analysis.arena, analysis.checked.graph.source_root, finding->file);
    if (!ms_span_equal(file, ms_string_span(&doc->path))) continue;
    append_diagnostic(&out, &first, source, finding);
  }
  /* The advisories: the lint rules over the checked program, or the lexical ones alone when it did not load. */
  MsLintFindingList lint = {0};
  if (analysis.resolved) {
    ms_lint_modules(analysis.arena, &analysis.checked.program, &lint);
  } else {
    ms_lint_source(analysis.arena, ms_string_span(&doc->path), source, &lint);
  }
  for (size_t i = 0; i < lint.len; i++) {
    const MsLintFinding *item = &lint.ptr[i];
    const MsSpan file = lsp_absolute_file(analysis.arena, analysis.checked.graph.source_root, item->file);
    if (!ms_span_equal(file, ms_string_span(&doc->path))) continue;
    const LspRange range = lsp_diagnostic_range(source, item->pos.offset);
    if (!first) ms_strbuild_append_byte(&out, ',');
    first = false;
    ms_strbuild_printf(&out,
                       "{\"range\":{\"start\":{\"line\":%zu,\"character\":%zu},\"end\":{\"line\":%zu,\"character\":%zu}},"
                       "\"severity\":%d,\"source\":\"manuscript-lint\",\"code\":",
                       range.start.line, range.start.character, range.end.line, range.end.character,
                       item->severity == MS_LINT_ERROR ? 1 : 2);
    lsp_json_string(&out, ms_span_of_text(item->code));
    ms_strbuild_append_text(&out, ",\"message\":");
    lsp_json_string(&out, item->message);
    ms_strbuild_append_byte(&out, '}');
  }
  ms_lint_finding_list_free(&lint);
  lsp_analysis_release(&analysis);
  return ms_strbuild_finish(&out);
}

static void send_diagnostics(MsSpan uri, int64_t version, bool has_version, MsSpan diagnostics,
                             void (*send)(MsStrBuild *message)) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":");
  lsp_json_string(&out, uri);
  if (has_version) ms_strbuild_printf(&out, ",\"version\":%lld", (long long)version);
  ms_strbuild_append_text(&out, ",\"diagnostics\":[");
  ms_strbuild_append(&out, diagnostics);
  ms_strbuild_append_text(&out, "]}}");
  send(&out);
}

static int compare_uri(const void *left, const void *right) {
  const MsSpan a = ms_string_span(&(*(LspDoc *const *)left)->uri), b = ms_string_span(&(*(LspDoc *const *)right)->uri);
  const size_t common = a.len < b.len ? a.len : b.len;
  for (size_t i = 0; i < common; i++) {
    if (a.ptr[i] != b.ptr[i]) return a.ptr[i] < b.ptr[i] ? -1 : 1;
  }
  return a.len < b.len ? -1 : (a.len > b.len ? 1 : 0);
}

void lsp_publish_diagnostics(LspDocList *docs, void (*send)(MsStrBuild *message)) {
  LspDoc **order = docs->len == 0 ? NULL : malloc(docs->len * sizeof *order);
  for (size_t i = 0; i < docs->len; i++) order[i] = &docs->ptr[i];
  if (docs->len > 1) qsort(order, docs->len, sizeof *order, compare_uri);
  for (size_t i = 0; i < docs->len; i++) {
    LspDoc *doc = order[i];
    const bool library = lsp_uri_is_standard_library(ms_string_span(&doc->uri));
    /* A document that reads none of the files changed since the last publish keeps its diagnostics unanalysed. */
    if (!library && !needs_analysis(doc)) continue;
    MsString diagnostics = library ? ms_string_from_span(ms_span_of_text("")) : diagnostics_of(doc, docs);
    /* A changed document always republishes (its version moved); the others only when their findings changed. */
    if (doc->dirty || !ms_string_equal(&diagnostics, &doc->published)) {
      send_diagnostics(ms_string_span(&doc->uri), doc->version, true, ms_string_span(&diagnostics), send);
      ms_string_release(&doc->published);
      doc->published = diagnostics;
      doc->dirty = false;
    } else {
      ms_string_release(&diagnostics);
    }
  }
  free(order);
  ms_strbuild_clear(&changed_files);
  everything_changed = false;
}

void lsp_publish_empty(MsSpan uri, void (*send)(MsStrBuild *message)) {
  send_diagnostics(uri, 0, false, ms_span_of_text(""), send);
}
