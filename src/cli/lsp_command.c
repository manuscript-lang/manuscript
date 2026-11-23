/* cli/lsp_command.c: the language server session: framed JSON-RPC on standard input and output, one thread, every
 * document in memory. Port of the session in crates/ms-lsp/src/server.rs. Each handler reads the checked program of the
 * open documents (cli/lsp_analysis.c) and answers in LSP's UTF-16 positions. */
#include "cli/lsp_command.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "base/arena.h"
#include "base/cstr.h"
#include "base/sort.h"
#include "cli/json_value.h"
#include "cli/lsp_actions.h"
#include "cli/lsp_analysis.h"
#include "cli/lsp_completion.h"
#include "cli/lsp_internal.h"
#include "cli/lsp_nav.h"
#include "cli/lsp_semantic.h"
#include "cli/lsp_signature.h"
#include "cli/lsp_workspace.h"
#include "cli/lsp_symbols.h"

enum { ERROR_PARSE = -32700, ERROR_INVALID_REQUEST = -32600, ERROR_NOT_FOUND = -32601, ERROR_INVALID_PARAMS = -32602,
       ERROR_NOT_INITIALIZED = -32002 };

MS_LIST_DEFINE(RootList, root_list, MsString)

typedef struct Session {
  LspDocList docs;
  RootList roots;
  bool initialized, shutdown;
  bool snippets; /* the client takes snippet text in completions */
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
  const MsJson *capabilities = member_kind(params, "capabilities", MS_JSON_OBJECT);
  const MsJson *text_document = member_kind(capabilities, "textDocument", MS_JSON_OBJECT);
  const MsJson *completion = member_kind(text_document, "completion", MS_JSON_OBJECT);
  const MsJson *completion_item = member_kind(completion, "completionItem", MS_JSON_OBJECT);
  const MsJson *snippet_support = member_kind(completion_item, "snippetSupport", MS_JSON_BOOL);
  session->snippets = snippet_support != NULL && ms_span_is_text(snippet_support->text, "true");
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
  ms_strbuild_append_text(&result, "{\"capabilities\":{\"textDocumentSync\":2,\"renameProvider\":{\"prepareProvider\":true},\"referencesProvider\":true,\"documentHighlightProvider\":true,\"documentSymbolProvider\":true,\"documentFormattingProvider\":true,\"typeDefinitionProvider\":true,\"inlayHintProvider\":true,\"semanticTokensProvider\":{\"legend\":{\"tokenTypes\":[" LSP_TOKEN_LEGEND "],\"tokenModifiers\":[]},\"full\":true},\"foldingRangeProvider\":true,\"workspaceSymbolProvider\":true,\"completionProvider\":{\"triggerCharacters\":[\".\",\":\",\"/\"]},\"codeActionProvider\":{\"codeActionKinds\":[\"source.fixAll.manuscript\",\"quickfix\",\"source.organizeImports\"]},\"signatureHelpProvider\":{\"triggerCharacters\":[\"(\",\",\",\":\"],\"retriggerCharacters\":[\",\"]},\"hoverProvider\":true,\"definitionProvider\":true,\"positionEncoding\":\"utf-16\"},");
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

/* The textDocument requests that read one document at a position. Returns false for a method it does not serve. */
static bool handle_document_request(Session *session, const MsJson *id, MsSpan method, const MsJson *params) {
  static const char *const SERVED[] = {"hover", "definition", "references", "documentHighlight", "documentSymbol", "formatting", "foldingRange", "typeDefinition", "inlayHint", "signatureHelp", "codeAction", "completion", "semanticTokens/full", "prepareRename", "rename"};
  bool served = false;
  for (size_t i = 0; i < sizeof SERVED / sizeof SERVED[0]; i++) {
    MsStrBuild name = ms_strbuild_new();
    ms_strbuild_append_text(&name, "textDocument/");
    ms_strbuild_append_text(&name, SERVED[i]);
    served |= ms_span_equal(ms_strbuild_span(&name), method);
    ms_strbuild_free(&name);
  }
  if (!served) return false;
  const MsJson *document = member_kind(params, "textDocument", MS_JSON_OBJECT);
  const MsJson *uri = member_kind(document, "uri", MS_JSON_STRING);
  LspPosition position = {0};
  const MsSpan requested = ms_span_of(method.ptr + 13, method.len - 13);
  const bool outline = ms_span_is_text(requested, "documentSymbol") || ms_span_is_text(requested, "formatting") ||
                       ms_span_is_text(requested, "foldingRange") ||
                       ms_span_is_text(requested, "semanticTokens/full") ||
                       ms_span_is_text(requested, "inlayHint") || ms_span_is_text(requested, "codeAction");
  if (uri == NULL || (!outline && !json_position(ms_json_member(params, "position"), &position))) {
    if (id != NULL) reply_error(id, ERROR_INVALID_PARAMS, "invalid parameters");
    return true;
  }
  const LspDoc *doc = lsp_doc_find(&session->docs, uri->text);
  if (id == NULL) return true;
  const MsSpan kind = ms_span_of(method.ptr + 13, method.len - 13);
  MsStrBuild result = ms_strbuild_new();
  if (doc == NULL || lsp_uri_is_standard_library(uri->text)) {
    const bool list = ms_span_is_text(kind, "documentSymbol");
    if (ms_span_is_text(kind, "prepareRename") || ms_span_is_text(kind, "rename")) {
      reply_error(id, ERROR_INVALID_PARAMS, "select a name that refers to a source declaration");
    } else {
      reply_result(id, ms_span_of_text(list ? "[]" : "null"));
    }
    ms_strbuild_free(&result);
    return true;
  }
  if (ms_span_is_text(kind, "hover")) {
    lsp_nav_hover(&session->docs, doc, position, &result);
  } else if (ms_span_is_text(kind, "definition")) {
    lsp_nav_definition(&session->docs, doc, position, &result);
  } else if (ms_span_is_text(kind, "references")) {
    const MsJson *context = member_kind(params, "context", MS_JSON_OBJECT);
    const MsJson *include = member_kind(context, "includeDeclaration", MS_JSON_BOOL);
    lsp_nav_references(&session->docs, doc, position, include != NULL && ms_span_is_text(include->text, "true"), &result);
  } else if (ms_span_is_text(kind, "documentSymbol")) {
    lsp_document_symbols(&session->docs, doc, &result);
  } else if (ms_span_is_text(kind, "typeDefinition")) {
    lsp_nav_type_definition(&session->docs, doc, position, &result);
  } else if (ms_span_is_text(kind, "inlayHint")) {
    const MsJson *range = member_kind(params, "range", MS_JSON_OBJECT);
    LspRange wanted = {{0, 0}, {(size_t)-1, (size_t)-1}};
    if (range != NULL) {
      LspPosition start, end;
      if (json_position(ms_json_member(range, "start"), &start) && json_position(ms_json_member(range, "end"), &end)) {
        wanted = (LspRange){start, end};
      }
    }
    lsp_nav_inlay_hints(&session->docs, doc, wanted, &result);
  } else if (ms_span_is_text(kind, "completion")) {
    lsp_completion(&session->docs, doc, position, session->snippets, &result);
  } else if (ms_span_is_text(kind, "codeAction")) {
    LspRange wanted = {{0, 0}, {(size_t)-1, (size_t)-1}};
    const MsJson *range = member_kind(params, "range", MS_JSON_OBJECT);
    LspPosition start, end;
    if (range != NULL && json_position(ms_json_member(range, "start"), &start) && json_position(ms_json_member(range, "end"), &end)) {
      wanted = (LspRange){start, end};
    }
    const MsJson *context = member_kind(params, "context", MS_JSON_OBJECT);
    const MsJson *only = member_kind(context, "only", MS_JSON_ARRAY);
    MsSpan kinds[16];
    size_t kind_count = 0;
    for (size_t i = 0; only != NULL && i < only->count && kind_count < 16; i++) {
      if (only->items[i]->kind == MS_JSON_STRING) kinds[kind_count++] = only->items[i]->text;
    }
    lsp_code_actions(&session->docs, doc, wanted, kinds, kind_count, &result);
  } else if (ms_span_is_text(kind, "signatureHelp")) {
    lsp_signature_help(&session->docs, doc, position, &result);
  } else if (ms_span_is_text(kind, "semanticTokens/full")) {
    lsp_semantic_tokens(&session->docs, doc, &result);
  } else if (ms_span_is_text(kind, "foldingRange")) {
    lsp_folding_ranges(doc, &result);
  } else if (ms_span_is_text(kind, "formatting")) {
    MsStrBuild error = ms_strbuild_new();
    if (!lsp_format_document(doc, &result, &error)) {
      ms_strbuild_append_byte(&error, 0);
      reply_error(id, ERROR_INVALID_PARAMS, (const char *)ms_strbuild_span(&error).ptr);
      ms_strbuild_free(&error);
      ms_strbuild_free(&result);
      return true;
    }
    ms_strbuild_free(&error);
  } else if (ms_span_is_text(kind, "documentHighlight")) {
    lsp_nav_highlight(&session->docs, doc, position, &result);
  } else {
    const bool prepare = ms_span_is_text(kind, "prepareRename");
    const MsJson *name = member_kind(params, "newName", MS_JSON_STRING);
    const MsSpan new_name = prepare || name == NULL ? (MsSpan){0} : name->text;
    MsStrBuild error = ms_strbuild_new();
    if (!prepare && new_name.len == 0) {
      reply_error(id, ERROR_INVALID_PARAMS, "new name is empty");
    } else if (lsp_nav_rename(&session->docs, doc, position, new_name, &result, &error)) {
      reply_result(id, ms_strbuild_span(&result));
    } else {
      MsStrBuild message = ms_strbuild_new();
      ms_strbuild_append(&message, ms_strbuild_span(&error));
      ms_strbuild_append_byte(&message, 0);
      reply_error(id, ERROR_INVALID_PARAMS, (const char *)ms_strbuild_span(&message).ptr);
      ms_strbuild_free(&message);
    }
    ms_strbuild_free(&error);
    ms_strbuild_free(&result);
    return true;
  }
  reply_result(id, ms_strbuild_span(&result));
  ms_strbuild_free(&result);
  return true;
}

/* The source of a bundled module by its `manuscript-stdlib:` URI. */
static void handle_standard_library_source(const MsJson *id, const MsJson *params) {
  const MsJson *document = member_kind(params, "textDocument", MS_JSON_OBJECT);
  const MsJson *uri = member_kind(document, "uri", MS_JSON_STRING);
  const MsSpan prefix = ms_span_of_text("manuscript-stdlib:///");
  if (uri == NULL || !ms_span_starts_with(uri->text, prefix) || ms_span_find(uri->text, ms_span_of_text("?"), &(size_t){0}) ||
      ms_span_find(uri->text, ms_span_of_text("#"), &(size_t){0})) {
    reply_error(id, ERROR_INVALID_PARAMS, "invalid standard-library URI");
    return;
  }
  MsStdSource source;
  if (!ms_std_source_find(ms_span_of(uri->text.ptr + prefix.len, uri->text.len - prefix.len), &source)) {
    reply_error(id, ERROR_INVALID_PARAMS, "unknown standard-library module");
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  lsp_json_string(&text, source.text);
  reply_result(id, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
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
  } else if (ms_span_is_text(method->text, "manuscript/standardLibrarySource")) {
    if (id != NULL) handle_standard_library_source(id, params);
  } else if (ms_span_is_text(method->text, "workspace/symbol")) {
    if (id != NULL) {
      const MsJson *query = member_kind(params, "query", MS_JSON_STRING);
      MsSpan *roots = session->roots.len == 0 ? NULL : malloc(session->roots.len * sizeof *roots);
      for (size_t i = 0; i < session->roots.len; i++) roots[i] = ms_string_span(&session->roots.ptr[i]);
      MsStrBuild result = ms_strbuild_new();
      lsp_workspace_symbols(&session->docs, roots, session->roots.len, query != NULL ? query->text : (MsSpan){0}, &result);
      reply_result(id, ms_strbuild_span(&result));
      ms_strbuild_free(&result);
      free(roots);
    }
  } else if (handle_document_request(session, id, method->text, params)) {
    /* answered */
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
