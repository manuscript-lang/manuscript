/* lsp/lsp_sync.c: message JSON helpers and document synchronization. */
#include "lsp/lsp_sync.h"

#include "compiler/project/project.h"

const MsJson *lsp_json_member(const MsJson *object, const char *key, MsJsonKind kind) {
  const MsJson *value = object != NULL && object->kind == MS_JSON_OBJECT ? ms_json_member(object, key) : NULL;
  return value != NULL && value->kind == kind ? value : NULL;
}

bool lsp_json_integer(const MsJson *value, size_t *out) {
  if (value == NULL || value->kind != MS_JSON_NUMBER || value->text.len == 0 || value->text.len > 15) return false;
  size_t number = 0;
  for (size_t i = 0; i < value->text.len; i++) {
    if (value->text.ptr[i] < '0' || value->text.ptr[i] > '9') return false;
    number = number * 10 + (size_t)(value->text.ptr[i] - '0');
  }
  *out = number;
  return true;
}

bool lsp_json_position(const MsJson *value, LspPosition *position) {
  return lsp_json_integer(lsp_json_member(value, "line", MS_JSON_NUMBER), &position->line) &&
         lsp_json_integer(lsp_json_member(value, "character", MS_JSON_NUMBER), &position->character);
}


static bool apply_change(LspDoc *doc, const MsJson *change, MsStrBuild *text) {
  const MsJson *body = lsp_json_member(change, "text", MS_JSON_STRING);
  if (body == NULL) return false;
  const MsJson *range = lsp_json_member(change, "range", MS_JSON_OBJECT);
  if (range == NULL) {
    ms_strbuild_clear(text);
    ms_strbuild_append(text, body->text);
    return true;
  }
  LspPosition from, to;
  size_t start, end;
  const MsSpan current = ms_strbuild_span(text);
  if (!lsp_json_position(ms_json_member(range, "start"), &from) || !lsp_json_position(ms_json_member(range, "end"), &to) ||
      !lsp_offset(current, from, true, &start) || !lsp_offset(current, to, true, &end) || end < start) {
    return false;
  }
  MsStrBuild next = ms_strbuild_new();
  ms_strbuild_append(&next, ms_span_of(current.ptr, start));
  ms_strbuild_append(&next, body->text);
  ms_strbuild_append(&next, ms_span_of(current.ptr + end, current.len - end));
  ms_strbuild_free(text);
  *text = next;
  (void)doc;
  return true;
}

bool lsp_sync_change(LspDocList *docs, bool open, const MsJson *params) {
  const MsJson *document = lsp_json_member(params, "textDocument", MS_JSON_OBJECT);
  const MsJson *uri = lsp_json_member(document, "uri", MS_JSON_STRING);
  if (uri == NULL) return false;
  size_t version = 0;
  (void)lsp_json_integer(lsp_json_member(document, "version", MS_JSON_NUMBER), &version);
  const bool bundled = lsp_uri_is_standard_library(uri->text);
  if (bundled && !open) return true; /* a bundled module is read-only */
  if (open && bundled) {
    /* The client's text is not trusted: the module is what this executable carries. */
    MsSpan name = {0};
    MsStdSource source;
    if (!lsp_uri_standard_module(uri->text, &name) || !ms_std_source_find(name, &source)) {
      return true;
    }
    lsp_doc_set(docs, uri->text, (int64_t)version, source.text);
    return true;
  }
  if (open) {
    const MsJson *text = lsp_json_member(document, "text", MS_JSON_STRING);
    if (text == NULL) return false;
    lsp_doc_set(docs, uri->text, (int64_t)version, text->text);
    return true;
  }
  LspDoc *old = lsp_doc_find(docs, uri->text);
  const MsJson *changes = lsp_json_member(params, "contentChanges", MS_JSON_ARRAY);
  if (old == NULL || changes == NULL || changes->count == 0 || (int64_t)version <= old->version) return true;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, ms_string_span(&old->text));
  for (size_t i = 0; i < changes->count; i++) {
    if (!apply_change(old, changes->items[i], &text)) {
      ms_strbuild_free(&text);
      return true;
    }
  }
  lsp_doc_set(docs, uri->text, (int64_t)version, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return true;
}

