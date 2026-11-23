/* cli/lsp_command.c: the language server session: framed JSON-RPC on standard input and output, one thread, every
 * document in memory. Port of the session in crates/ms-lsp/src/server.rs. Each handler reads the checked program of the
 * open documents (cli/lsp_analysis.c) and answers in LSP's UTF-16 positions. */
#include "cli/lsp_command.h"

#include <stdio.h>
#include <string.h>

#include "base/arena.h"
#include "base/cstr.h"
#include "base/sort.h"
#include "cli/json_value.h"
#include "cli/lsp_analysis.h"
#include "cli/lsp_internal.h"

enum { ERROR_PARSE = -32700, ERROR_INVALID_REQUEST = -32600, ERROR_NOT_FOUND = -32601, ERROR_INVALID_PARAMS = -32602,
       ERROR_NOT_INITIALIZED = -32002 };

MS_LIST_DEFINE(RootList, root_list, MsString)

typedef struct Session {
  LspDocList docs;
  RootList roots;
  bool initialized, shutdown;
} Session;

static void send(MsStrBuild *message) {
  lsp_write_frame(stdout, ms_strbuild_span(message));
  ms_strbuild_free(message);
}

/* `{"jsonrpc":"2.0","id":<id>,` for a response; the caller adds the member and the brace. */
static void response_head(MsStrBuild *out, const MsJson *id) {
  ms_strbuild_append_text(out, "{\"jsonrpc\":\"2.0\",\"id\":");
  if (id == NULL || id->kind == MS_JSON_NULL) {
    ms_strbuild_append_text(out, "null");
  } else if (id->kind == MS_JSON_STRING) {
    lsp_json_string(out, id->text);
  } else {
    ms_strbuild_append(out, id->text);
  }
}

static void reply_error(const MsJson *id, int code, const char *message) {
  MsStrBuild out = ms_strbuild_new();
  response_head(&out, id);
  ms_strbuild_printf(&out, ",\"error\":{\"code\":%d,\"message\":", code);
  lsp_json_string(&out, ms_span_of_text(message));
  ms_strbuild_append_text(&out, "}}");
  send(&out);
}

static void reply_result(const MsJson *id, MsSpan result) {
  MsStrBuild out = ms_strbuild_new();
  response_head(&out, id);
  ms_strbuild_append_text(&out, ",\"result\":");
  ms_strbuild_append(&out, result);
  ms_strbuild_append_byte(&out, '}');
  send(&out);
}

static const MsJson *member_kind(const MsJson *object, const char *key, MsJsonKind kind) {
  const MsJson *value = object != NULL && object->kind == MS_JSON_OBJECT ? ms_json_member(object, key) : NULL;
  return value != NULL && value->kind == kind ? value : NULL;
}

static bool json_integer(const MsJson *value, size_t *out) {
  if (value == NULL || value->kind != MS_JSON_NUMBER || value->text.len == 0 || value->text.len > 15) return false;
  size_t number = 0;
  for (size_t i = 0; i < value->text.len; i++) {
    if (value->text.ptr[i] < '0' || value->text.ptr[i] > '9') return false;
    number = number * 10 + (size_t)(value->text.ptr[i] - '0');
  }
  *out = number;
  return true;
}

static bool json_position(const MsJson *value, LspPosition *position) {
  return json_integer(member_kind(value, "line", MS_JSON_NUMBER), &position->line) &&
         json_integer(member_kind(value, "character", MS_JSON_NUMBER), &position->character);
}

static void handle_initialize(Session *session, const MsJson *id, const MsJson *params) {
  session->initialized = true;
  const MsJson *root = member_kind(params, "rootUri", MS_JSON_STRING);
  if (root != NULL && root->text.len > 0 && !lsp_uri_is_malformed_file(root->text)) {
    MsStrBuild path = ms_strbuild_new();
    lsp_uri_filename(root->text, &path);
    root_list_push(&session->roots, ms_string_from_span(ms_strbuild_span(&path)));
    ms_strbuild_free(&path);
  }
  const MsJson *folders = member_kind(params, "workspaceFolders", MS_JSON_ARRAY);
  for (size_t i = 0; folders != NULL && i < folders->count; i++) {
    const MsJson *uri = member_kind(folders->items[i], "uri", MS_JSON_STRING);
    if (uri == NULL || lsp_uri_is_malformed_file(uri->text)) continue;
    MsStrBuild path = ms_strbuild_new();
    lsp_uri_filename(uri->text, &path);
    root_list_push(&session->roots, ms_string_from_span(ms_strbuild_span(&path)));
    ms_strbuild_free(&path);
  }
  MsStrBuild result = ms_strbuild_new();
  ms_strbuild_append_text(&result, "{\"capabilities\":{\"textDocumentSync\":2,\"positionEncoding\":\"utf-16\"},");
  ms_strbuild_append_text(&result, "\"serverInfo\":{\"name\":\"manuscript\",\"version\":\"" MS_VERSION "\"}}");
  reply_result(id, ms_strbuild_span(&result));
  ms_strbuild_free(&result);
}

/* Publishes the diagnostics of every open document whose set changed, in URI order. */
static void publish(Session *session) {
  lsp_publish_diagnostics(&session->docs, send);
}

static bool apply_change(LspDoc *doc, const MsJson *change, MsStrBuild *text) {
  const MsJson *body = member_kind(change, "text", MS_JSON_STRING);
  if (body == NULL) return false;
  const MsJson *range = member_kind(change, "range", MS_JSON_OBJECT);
  if (range == NULL) {
    ms_strbuild_clear(text);
    ms_strbuild_append(text, body->text);
    return true;
  }
  LspPosition from, to;
  size_t start, end;
  const MsSpan current = ms_strbuild_span(text);
  if (!json_position(ms_json_member(range, "start"), &from) || !json_position(ms_json_member(range, "end"), &to) ||
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

/* Stores an opened or edited document. Stale, empty or malformed edits are ignored. */
static bool handle_change(Session *session, bool open, const MsJson *params) {
  const MsJson *document = member_kind(params, "textDocument", MS_JSON_OBJECT);
  const MsJson *uri = member_kind(document, "uri", MS_JSON_STRING);
  if (uri == NULL) return false;
  size_t version = 0;
  (void)json_integer(member_kind(document, "version", MS_JSON_NUMBER), &version);
  if (open) {
    const MsJson *text = member_kind(document, "text", MS_JSON_STRING);
    if (text == NULL) return false;
    lsp_doc_set(&session->docs, uri->text, (int64_t)version, text->text);
    publish(session);
    return true;
  }
  LspDoc *old = lsp_doc_find(&session->docs, uri->text);
  const MsJson *changes = member_kind(params, "contentChanges", MS_JSON_ARRAY);
  if (old == NULL || changes == NULL || changes->count == 0 || (int64_t)version <= old->version) return true;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, ms_string_span(&old->text));
  for (size_t i = 0; i < changes->count; i++) {
    if (!apply_change(old, changes->items[i], &text)) {
      ms_strbuild_free(&text);
      return true;
    }
  }
  lsp_doc_set(&session->docs, uri->text, (int64_t)version, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  publish(session);
  return true;
}

static void handle_close(Session *session, const MsJson *params) {
  const MsJson *document = member_kind(params, "textDocument", MS_JSON_OBJECT);
  const MsJson *uri = member_kind(document, "uri", MS_JSON_STRING);
  if (uri == NULL) return;
  lsp_doc_remove(&session->docs, uri->text);
  publish(session);
  lsp_publish_empty(uri->text, send);
}

/* One message. Returns -1 to continue, or the process status when the session ends. */
static int handle_message(Session *session, MsSpan body) {
  MsArena arena = ms_arena_new();
  int status = -1;
  const MsJson *message = ms_json_parse(&arena, body);
  if (message == NULL) {
    reply_error(NULL, ERROR_PARSE, "invalid JSON");
    goto done;
  }
  const MsJson *id = message->kind == MS_JSON_OBJECT ? ms_json_member(message, "id") : NULL;
  const MsJson *jsonrpc = message->kind == MS_JSON_OBJECT ? ms_json_member(message, "jsonrpc") : NULL;
  const MsJson *method = message->kind == MS_JSON_OBJECT ? ms_json_member(message, "method") : NULL;
  const bool well_formed = message->kind == MS_JSON_OBJECT &&
                           (jsonrpc == NULL || jsonrpc->kind == MS_JSON_NULL || jsonrpc->kind == MS_JSON_STRING) &&
                           (method == NULL || method->kind == MS_JSON_NULL || method->kind == MS_JSON_STRING);
  if (!well_formed) {
    reply_error(NULL, ERROR_INVALID_REQUEST, "invalid request");
    goto done;
  }
  if (jsonrpc == NULL || jsonrpc->kind != MS_JSON_STRING || !ms_span_is_text(jsonrpc->text, "2.0") || method == NULL ||
      method->kind != MS_JSON_STRING || method->text.len == 0) {
    reply_error(NULL, ERROR_INVALID_REQUEST, "invalid request");
    goto done;
  }
  const MsJson *params = ms_json_member(message, "params");
  const bool is_exit = ms_span_is_text(method->text, "exit");
  if (session->shutdown && !is_exit) {
    if (id != NULL) reply_error(id, ERROR_INVALID_REQUEST, "server has shut down");
    goto done;
  }
  if (!session->initialized && !ms_span_is_text(method->text, "initialize") && !is_exit) {
    if (id != NULL) reply_error(id, ERROR_NOT_INITIALIZED, "server not initialized");
    goto done;
  }
  if (ms_span_is_text(method->text, "initialize")) {
    handle_initialize(session, id, params);
  } else if (ms_span_is_text(method->text, "shutdown")) {
    session->shutdown = true;
    if (id != NULL) reply_result(id, ms_span_of_text("null"));
  } else if (is_exit) {
    if (!session->shutdown) {
      (void)fputs("ms-lsp: exit before shutdown\n", stderr);
      status = 1;
    } else {
      status = 0;
    }
  } else if (ms_span_is_text(method->text, "textDocument/didOpen") ||
             ms_span_is_text(method->text, "textDocument/didChange")) {
    if (!handle_change(session, ms_span_is_text(method->text, "textDocument/didOpen"), params) && id != NULL) {
      reply_error(id, ERROR_INVALID_PARAMS, "invalid parameters");
    } else if (id != NULL) {
      reply_result(id, ms_span_of_text("null"));
    }
  } else if (ms_span_is_text(method->text, "textDocument/didClose")) {
    handle_close(session, params);
    if (id != NULL) reply_result(id, ms_span_of_text("null"));
  } else if (id != NULL) {
    if (ms_span_starts_with(method->text, ms_span_of_text("textDocument/"))) {
      reply_result(id, ms_span_of_text("null"));
    } else if (ms_span_is_text(method->text, "initialized")) {
      reply_result(id, ms_span_of_text("null"));
    } else {
      reply_error(id, ERROR_NOT_FOUND, "method not supported");
    }
  }
done:
  ms_arena_free(&arena);
  return status;
}

int ms_lsp_command(int argc, char **argv) {
  (void)argv;
  if (argc > 0) {
    (void)fprintf(stderr, "ms lsp: takes no arguments; it speaks LSP on standard input and output\n");
    return 2;
  }
  Session session = {0};
  MsStrBuild body = ms_strbuild_new();
  int status = 0;
  for (;;) {
    const char *error = "";
    const LspFrameStatus frame = lsp_read_frame(stdin, &body, &error);
    if (frame == LSP_FRAME_EOF) break;
    if (frame == LSP_FRAME_FAILED) {
      (void)fprintf(stderr, "ms-lsp: %s\n", error);
      status = 1;
      break;
    }
    const int done = handle_message(&session, ms_strbuild_span(&body));
    if (done >= 0) {
      status = done;
      break;
    }
  }
  ms_strbuild_free(&body);
  return status;
}
