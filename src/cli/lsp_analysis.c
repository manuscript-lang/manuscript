/* cli/lsp_analysis.c: open documents and their diagnostics. Each document is checked as the entry of its own graph, with
 * every open document's unsaved text in place of disk, and only the findings that sit in that document are shown. */
#include "cli/lsp_analysis.h"

#include <stdlib.h>
#include <string.h>

#include "base/arena.h"
#include "base/file.h"
#include "base/path.h"
#include "cli/checked_input.h"
#include "cli/findings.h"
#include "cli/lsp_internal.h"
#include "compiler/syntax/diag.h"

LspDoc *lsp_doc_find(LspDocList *docs, MsSpan uri) {
  for (size_t i = 0; i < docs->len; i++) {
    if (ms_span_equal(ms_string_span(&docs->ptr[i].uri), uri)) return &docs->ptr[i];
  }
  return NULL;
}

void lsp_doc_set(LspDocList *docs, MsSpan uri, int64_t version, MsSpan text) {
  LspDoc *doc = lsp_doc_find(docs, uri);
  if (doc == NULL) {
    MsStrBuild path = ms_strbuild_new();
    lsp_uri_filename(uri, &path);
    lsp_doc_list_push(docs, (LspDoc){.uri = ms_string_from_span(uri), .path = ms_strbuild_finish(&path)});
    doc = &docs->ptr[docs->len - 1];
  }
  const MsString text_copy = ms_string_from_span(text); /* `text` may alias the old text */
  ms_string_release(&doc->text);
  doc->text = text_copy;
  doc->version = version;
  doc->dirty = true;
}

void lsp_doc_remove(LspDocList *docs, MsSpan uri) {
  for (size_t i = 0; i < docs->len; i++) {
    LspDoc *doc = &docs->ptr[i];
    if (!ms_span_equal(ms_string_span(&doc->uri), uri)) continue;
    ms_string_release(&doc->uri);
    ms_string_release(&doc->path);
    ms_string_release(&doc->text);
    ms_string_release(&doc->published);
    memmove(doc, doc + 1, (docs->len - i - 1) * sizeof *doc);
    docs->len--;
    return;
  }
}

static MsSpan absolute_file(MsArena *arena, MsSpan source_root, MsSpan file) {
  if (ms_path_is_absolute(file) || source_root.len == 0) return file;
  MsStrBuild joined = ms_strbuild_new();
  ms_path_append_joined(&joined, source_root, file);
  const MsSpan result = ms_arena_copy(arena, ms_strbuild_span(&joined));
  ms_strbuild_free(&joined);
  return result;
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
static MsString diagnostics_of(const LspDoc *doc, const MsOverlay *overlay) {
  MsArena arena = ms_arena_new();
  MsCheckedInput checked = {0};
  const MsLoadOptions options = {.overlay = overlay};
  (void)ms_checked_input_load_with(&arena, &checked, ms_string_span(&doc->path), MS_INPUT_ANALYSIS, &options);
  MsStrBuild out = ms_strbuild_new();
  bool first = true;
  const MsSpan source = ms_string_span(&doc->text);
  for (size_t i = 0; i < checked.findings.len; i++) {
    const Finding *finding = &checked.findings.ptr[i];
    const MsSpan file = absolute_file(&arena, checked.graph.source_root, finding->file);
    if (!ms_span_equal(file, ms_string_span(&doc->path))) continue;
    append_diagnostic(&out, &first, source, finding);
  }
  ms_checked_input_free(&checked);
  ms_arena_free(&arena);
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
  MsOverlayFile *files = docs->len == 0 ? NULL : malloc(docs->len * sizeof *files);
  LspDoc **order = docs->len == 0 ? NULL : malloc(docs->len * sizeof *order);
  for (size_t i = 0; i < docs->len; i++) {
    files[i] = (MsOverlayFile){ms_string_span(&docs->ptr[i].path), ms_string_span(&docs->ptr[i].text)};
    order[i] = &docs->ptr[i];
  }
  if (docs->len > 1) qsort(order, docs->len, sizeof *order, compare_uri);
  const MsOverlay overlay = {files, docs->len};
  for (size_t i = 0; i < docs->len; i++) {
    LspDoc *doc = order[i];
    const bool library = lsp_uri_is_standard_library(ms_string_span(&doc->uri));
    MsString diagnostics = library ? ms_string_from_span(ms_span_of_text("")) : diagnostics_of(doc, &overlay);
    /* A changed document always republishes (its version moved); the others only when their findings changed. */
    const bool changed = !ms_string_equal(&diagnostics, &doc->published);
    if (changed || doc->dirty) {
      send_diagnostics(ms_string_span(&doc->uri), doc->version, true, ms_string_span(&diagnostics), send);
      ms_string_release(&doc->published);
      doc->published = diagnostics;
      doc->dirty = false;
    } else {
      ms_string_release(&diagnostics);
    }
  }
  free(files);
  free(order);
}

void lsp_publish_empty(MsSpan uri, void (*send)(MsStrBuild *message)) {
  send_diagnostics(uri, 0, false, ms_span_of_text(""), send);
}
