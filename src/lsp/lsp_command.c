/* lsp/lsp_command.c: the language server session: framed JSON-RPC on standard input and output, one thread, every
 * document in memory. Each handler reads the checked program of the
 * open documents (lsp/lsp_analysis.c) and answers in LSP's UTF-16 positions. */
#include "lsp/lsp_command.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "base/arena.h"
#include "base/cstr.h"
#include "base/env.h"
#include "base/sort.h"
#include "tooling/json_value.h"
#include "lsp/lsp_actions.h"
#include "lsp/lsp_analysis.h"
#include "lsp/lsp_completion.h"
#include "lsp/lsp_input.h"
#include "lsp/lsp_internal.h"
#include "lsp/lsp_nav.h"
#include "lsp/lsp_semantic.h"
#include "lsp/lsp_signature.h"
#include "lsp/lsp_supervisor.h"
#include "lsp/lsp_sync.h"
#include "lsp/lsp_workspace.h"
#include "lsp/lsp_symbols.h"

enum { ERROR_PARSE = -32700, ERROR_INVALID_REQUEST = -32600, ERROR_NOT_FOUND = -32601, ERROR_INVALID_PARAMS = -32602,
       ERROR_NOT_INITIALIZED = -32002, ERROR_CANCELED = -32800 };

MS_LIST_DEFINE(RootList, root_list, MsString)

typedef struct Session {
  LspDocList docs;
  RootList roots;
  bool initialized, shutdown;
  bool snippets; /* the client takes snippet text in completions */
  bool unpublished; /* a change whose diagnostics wait for the changes queued behind it */
} Session;

static LspInput *input_queue; /* the reader thread's queue */
static const MsJson *current_request; /* the request being answered */

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

static bool id_canceled(const MsJson *id) {
  return id != NULL && id == current_request && (id->kind == MS_JSON_STRING || id->kind == MS_JSON_NUMBER) &&
         lsp_input_canceled(input_queue, id->kind == MS_JSON_STRING, id->text);
}

static void reply_error(const MsJson *id, int code, const char *message) {
  if (id_canceled(id)) {
    code = ERROR_CANCELED;
    message = "request canceled";
  }
  MsStrBuild out = ms_strbuild_new();
  response_head(&out, id);
  ms_strbuild_printf(&out, ",\"error\":{\"code\":%d,\"message\":", code);
  lsp_json_string(&out, ms_span_of_text(message));
  ms_strbuild_append_text(&out, "}}");
  send(&out);
}

static void reply_result(const MsJson *id, MsSpan result) {
  if (id_canceled(id)) {
    reply_error(id, ERROR_CANCELED, "request canceled");
    return;
  }
  MsStrBuild out = ms_strbuild_new();
  response_head(&out, id);
  ms_strbuild_append_text(&out, ",\"result\":");
  ms_strbuild_append(&out, result);
  ms_strbuild_append_byte(&out, '}');
  send(&out);
}

static void handle_initialize(Session *session, const MsJson *id, const MsJson *params) {
  session->initialized = true;
  const MsJson *capabilities = lsp_json_member(params, "capabilities", MS_JSON_OBJECT);
  const MsJson *text_document = lsp_json_member(capabilities, "textDocument", MS_JSON_OBJECT);
  const MsJson *completion = lsp_json_member(text_document, "completion", MS_JSON_OBJECT);
  const MsJson *completion_item = lsp_json_member(completion, "completionItem", MS_JSON_OBJECT);
  const MsJson *snippet_support = lsp_json_member(completion_item, "snippetSupport", MS_JSON_BOOL);
  session->snippets = snippet_support != NULL && ms_span_is_text(snippet_support->text, "true");
  const MsJson *root = lsp_json_member(params, "rootUri", MS_JSON_STRING);
  if (root != NULL && root->text.len > 0 && !lsp_uri_is_malformed_file(root->text)) {
    MsStrBuild path = ms_strbuild_new();
    lsp_uri_filename(root->text, &path);
    root_list_push(&session->roots, ms_string_from_span(ms_strbuild_span(&path)));
    ms_strbuild_free(&path);
  }
  const MsJson *folders = lsp_json_member(params, "workspaceFolders", MS_JSON_ARRAY);
  for (size_t i = 0; folders != NULL && i < folders->count; i++) {
    const MsJson *uri = lsp_json_member(folders->items[i], "uri", MS_JSON_STRING);
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
  session->unpublished = false;
  lsp_publish_diagnostics(&session->docs, send);
}

/* Stores an opened or edited document. Stale, empty or malformed edits are ignored. */
static bool handle_change(Session *session, bool open, const MsJson *params) {
  if (!lsp_sync_change(&session->docs, open, params)) return false;
  if (open) {
    publish(session);
  } else {
    session->unpublished = true;
  }
  return true;
}

static void handle_close(Session *session, const MsJson *params) {
  const MsJson *document = lsp_json_member(params, "textDocument", MS_JSON_OBJECT);
  const MsJson *uri = lsp_json_member(document, "uri", MS_JSON_STRING);
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
  const MsJson *document = lsp_json_member(params, "textDocument", MS_JSON_OBJECT);
  const MsJson *uri = lsp_json_member(document, "uri", MS_JSON_STRING);
  LspPosition position = {0};
  const MsSpan requested = ms_span_of(method.ptr + 13, method.len - 13);
  const bool outline = ms_span_is_text(requested, "documentSymbol") || ms_span_is_text(requested, "formatting") ||
                       ms_span_is_text(requested, "foldingRange") ||
                       ms_span_is_text(requested, "semanticTokens/full") ||
                       ms_span_is_text(requested, "inlayHint") || ms_span_is_text(requested, "codeAction");
  if (uri == NULL || (!outline && !lsp_json_position(ms_json_member(params, "position"), &position))) {
    if (id != NULL) reply_error(id, ERROR_INVALID_PARAMS, "invalid parameters");
    return true;
  }
  const LspDoc *doc = lsp_doc_find(&session->docs, uri->text);
  if (id == NULL) return true;
  const MsSpan kind = ms_span_of(method.ptr + 13, method.len - 13);
  MsStrBuild result = ms_strbuild_new();
  if (doc == NULL) {
    const bool list = ms_span_is_text(kind, "documentSymbol");
    if (ms_span_is_text(kind, "prepareRename") || ms_span_is_text(kind, "rename")) {
      reply_error(id, ERROR_INVALID_PARAMS, "select a name that refers to a source declaration");
    } else {
      reply_result(id, ms_span_of_text(list ? "[]" : "null"));
    }
    ms_strbuild_free(&result);
    return true;
  }
  if (lsp_uri_is_standard_library(uri->text) &&
      (ms_span_is_text(kind, "codeAction") || ms_span_is_text(kind, "formatting") || ms_span_is_text(kind, "prepareRename") ||
       ms_span_is_text(kind, "rename"))) {
    /* A bundled module is read-only: nothing to fix, format or rename. */
    if (ms_span_is_text(kind, "prepareRename") || ms_span_is_text(kind, "rename")) {
      reply_error(id, ERROR_INVALID_PARAMS, "select a name that refers to a source declaration");
    } else {
      reply_result(id, ms_span_of_text("[]"));
    }
    ms_strbuild_free(&result);
    return true;
  }
  if (ms_span_is_text(kind, "hover")) {
    lsp_nav_hover(&session->docs, doc, position, &result);
  } else if (ms_span_is_text(kind, "definition")) {
    lsp_nav_definition(&session->docs, doc, position, &result);
  } else if (ms_span_is_text(kind, "references")) {
    const MsJson *context = lsp_json_member(params, "context", MS_JSON_OBJECT);
    const MsJson *include = lsp_json_member(context, "includeDeclaration", MS_JSON_BOOL);
    lsp_nav_references(&session->docs, doc, position, include != NULL && ms_span_is_text(include->text, "true"), &result);
  } else if (ms_span_is_text(kind, "documentSymbol")) {
    lsp_document_symbols(&session->docs, doc, &result);
  } else if (ms_span_is_text(kind, "typeDefinition")) {
    lsp_nav_type_definition(&session->docs, doc, position, &result);
  } else if (ms_span_is_text(kind, "inlayHint")) {
    const MsJson *range = lsp_json_member(params, "range", MS_JSON_OBJECT);
    LspRange wanted = {{0, 0}, {(size_t)-1, (size_t)-1}};
    if (range != NULL) {
      LspPosition start, end;
      if (lsp_json_position(ms_json_member(range, "start"), &start) && lsp_json_position(ms_json_member(range, "end"), &end)) {
        wanted = (LspRange){start, end};
      }
    }
    lsp_nav_inlay_hints(&session->docs, doc, wanted, &result);
  } else if (ms_span_is_text(kind, "completion")) {
    lsp_completion(&session->docs, doc, position, session->snippets, &result);
  } else if (ms_span_is_text(kind, "codeAction")) {
    LspRange wanted = {{0, 0}, {(size_t)-1, (size_t)-1}};
    const MsJson *range = lsp_json_member(params, "range", MS_JSON_OBJECT);
    LspPosition start, end;
    if (range != NULL && lsp_json_position(ms_json_member(range, "start"), &start) && lsp_json_position(ms_json_member(range, "end"), &end)) {
      wanted = (LspRange){start, end};
    }
    const MsJson *context = lsp_json_member(params, "context", MS_JSON_OBJECT);
    const MsJson *only = lsp_json_member(context, "only", MS_JSON_ARRAY);
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
    const MsJson *name = lsp_json_member(params, "newName", MS_JSON_STRING);
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
  const MsJson *document = lsp_json_member(params, "textDocument", MS_JSON_OBJECT);
  const MsJson *uri = lsp_json_member(document, "uri", MS_JSON_STRING);
  MsSpan name = {0};
  if (uri == NULL || !lsp_uri_standard_module(uri->text, &name) || ms_span_find(uri->text, ms_span_of_text("?"), &(size_t){0}) ||
      ms_span_find(uri->text, ms_span_of_text("#"), &(size_t){0})) {
    reply_error(id, ERROR_INVALID_PARAMS, "invalid standard-library URI");
    return;
  }
  MsStdSource source;
  if (!ms_std_source_find(name, &source)) {
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
  const MsJson *id = NULL;
  MsJson *message = ms_json_parse(&arena, body);
  if (message == NULL) {
    reply_error(NULL, ERROR_PARSE, "invalid JSON");
    goto done;
  }
  lsp_normalize_uris(&arena, message);
  id = message->kind == MS_JSON_OBJECT ? ms_json_member(message, "id") : NULL;
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
  current_request = id;
  if (id != NULL && !is_exit && id_canceled(id)) {
    reply_error(id, ERROR_CANCELED, "request canceled");
  } else if (ms_span_is_text(method->text, "initialize") && session->initialized) {
    if (id != NULL) reply_error(id, ERROR_INVALID_REQUEST, "server already initialized");
  } else if (ms_span_is_text(method->text, "initialize")) {
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
  } else if (ms_span_is_text(method->text, "workspace/didChangeWatchedFiles")) {
    lsp_analysis_invalidate();
    publish(session);
    if (id != NULL) reply_result(id, ms_span_of_text("null"));
  } else if (ms_span_is_text(method->text, "textDocument/didClose")) {
    handle_close(session, params);
    if (id != NULL) reply_result(id, ms_span_of_text("null"));
  } else if (ms_span_is_text(method->text, "manuscript/standardLibrarySource")) {
    if (id != NULL) handle_standard_library_source(id, params);
  } else if (ms_span_is_text(method->text, "workspace/symbol")) {
    if (id != NULL) {
      const MsJson *query = lsp_json_member(params, "query", MS_JSON_STRING);
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
    if (ms_span_starts_with_text(method->text, "textDocument/")) {
      reply_result(id, ms_span_of_text("null"));
    } else if (ms_span_is_text(method->text, "initialized")) {
      reply_result(id, ms_span_of_text("null"));
    } else {
      reply_error(id, ERROR_NOT_FOUND, "method not supported");
    }
  }
done:
  /* A run of edits is answered once, after the last, and a completion waiting behind an edit is answered first. */
  if (session->unpublished && !lsp_input_next_defers_publish(input_queue)) publish(session);
  if (id != NULL && (id->kind == MS_JSON_STRING || id->kind == MS_JSON_NUMBER)) lsp_input_done(input_queue, id->kind == MS_JSON_STRING, id->text);
  current_request = NULL;
  ms_arena_free(&arena);
  return status;
}

int ms_lsp_command(int argc, char **argv) {
  (void)argv;
  if (argc > 0) {
    (void)fprintf(stderr, "ms lsp: takes no arguments; it speaks LSP on standard input and output\n");
    return 2;
  }
  MsString worker;
  if (!ms_env_get("MS_LSP_WORKER", &worker)) lsp_supervise();
  ms_string_release(&worker);
  Session session = {0};
  input_queue = lsp_input_start(stdin);
  if (input_queue == NULL) {
    (void)fputs("ms-lsp: cannot start the reader thread\n", stderr);
    lsp_input_exit(1);
  }
  MsStrBuild body = ms_strbuild_new();
  int status = 0;
  for (;;) {
    const char *error = "";
    const LspFrameStatus frame = lsp_input_next(input_queue, &body, &error, NULL);
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
  lsp_input_exit(status);
}
