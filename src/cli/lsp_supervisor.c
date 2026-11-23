/* cli/lsp_supervisor.c: the supervisor of `ms lsp` (see lsp_supervisor.h). Three kinds of thread feed one queue: the
 * client's input and each worker's output (tagged by worker generation). The supervisor forwards frames, remembers the
 * unanswered requests and the open documents, and replays them into a new worker after a crash. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "cli/lsp_supervisor.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <uv.h>

#include "base/alloc.h"
#include "base/arena.h"
#include "base/env.h"
#include "cli/json_value.h"
#include "cli/lsp_input.h"
#include "cli/lsp_sync.h"

enum { RESTART_LIMIT = 5, SOURCE_CLIENT = 0 };
#define RESTART_WINDOW_NS ((uint64_t)30 * 1000000000u)
#define REPLAY_ID "ms-lsp-replay"

typedef struct Inflight {
  MsString key;  /* the id's kind letter, then its text */
  MsString json; /* the id as written back to the client */
} Inflight;

MS_LIST_DEFINE(InflightList, inflight_list, Inflight)

typedef struct Worker {
  uv_process_t process;
  bool exited;
  int64_t status;
  bool signaled;
} Worker;

typedef struct Supervisor {
  LspInput *events;
  Worker *worker;
  FILE *to_worker, *from_worker;
  int generation;
  InflightList inflight;
  MsArena initialize_arena;
  MsJson *initialize; /* the client's `initialize` request, in initialize_arena */
  bool initialized, replay_pending, exiting;
  bool log; /* `MS_LSP_LOG` is set: report each worker start on standard error */
  bool draining; /* the client's input ended: answer what the worker still owes, then stop */
  LspDocList docs;
  uint64_t restarts[RESTART_LIMIT + 1];
  size_t restart_count;
} Supervisor;

/* ---- the worker process ---- */

static void worker_exited(uv_process_t *process, int64_t status, int signal_number) {
  Worker *worker = (Worker *)process;
  worker->exited = true;
  worker->status = status;
  worker->signaled = signal_number != 0;
  uv_close((uv_handle_t *)process, NULL);
}

/* `name=value` as a C string the caller frees. */
static char *environment_entry(const char *name, const char *value) {
  MsStrBuild entry = ms_strbuild_new();
  ms_strbuild_append_text(&entry, name);
  ms_strbuild_append_byte(&entry, '=');
  ms_strbuild_append_text(&entry, value);
  const MsSpan text = ms_strbuild_span(&entry);
  char *copy = ms_alloc(text.len + 1);
  for (size_t i = 0; i < text.len; i++) copy[i] = (char)text.ptr[i];
  copy[text.len] = 0;
  ms_strbuild_free(&entry);
  return copy;
}

/* The environment of this process plus `MS_LSP_WORKER=1`. */
static char **worker_environment(void) {
  uv_env_item_t *items;
  int count;
  if (uv_os_environ(&items, &count) != 0) return NULL;
  char **env = ms_alloc(((size_t)count + 2) * sizeof *env);
  size_t used = 0;
  for (int i = 0; i < count; i++) env[used++] = environment_entry(items[i].name, items[i].value);
  uv_os_free_environ(items, count);
  env[used++] = environment_entry("MS_LSP_WORKER", "1");
  env[used] = NULL;
  return env;
}

static bool start_worker(Supervisor *s) {
  char exe[4096];
  size_t size = sizeof exe;
  if (uv_exepath(exe, &size) != 0) return false;
  uv_file to_child[2], from_child[2];
  if (uv_pipe(to_child, 0, 0) != 0) return false;
  if (uv_pipe(from_child, 0, 0) != 0) return false;
  char *args[] = {exe, (char *)"lsp", NULL};
  char **env = worker_environment();
  uv_stdio_container_t stdio[3];
  stdio[0].flags = UV_INHERIT_FD;
  stdio[0].data.fd = to_child[0];
  stdio[1].flags = UV_INHERIT_FD;
  stdio[1].data.fd = from_child[1];
  stdio[2].flags = UV_INHERIT_FD;
  stdio[2].data.fd = 2;
  uv_process_options_t options = {.exit_cb = worker_exited, .file = exe, .args = args, .env = env, .stdio_count = 3, .stdio = stdio};
  Worker *worker = ms_alloc(sizeof *worker);
  *worker = (Worker){0};
  const int started = uv_spawn(uv_default_loop(), &worker->process, &options);
  for (size_t i = 0; env != NULL && env[i] != NULL; i++) ms_free(env[i]);
  ms_free(env);
  uv_fs_t request;
  (void)uv_fs_close(NULL, &request, to_child[0], NULL);
  (void)uv_fs_close(NULL, &request, from_child[1], NULL);
  if (started != 0) {
    ms_free(worker);
    (void)uv_fs_close(NULL, &request, to_child[1], NULL);
    (void)uv_fs_close(NULL, &request, from_child[0], NULL);
    return false;
  }
  s->worker = worker;
  s->to_worker = fdopen(to_child[1], "wb");
  s->from_worker = fdopen(from_child[0], "rb");
  s->generation++;
  if (s->log) (void)fprintf(stderr, "ms-lsp: worker %d started\n", worker->process.pid);
  return s->to_worker != NULL && s->from_worker != NULL && lsp_input_attach(s->events, s->from_worker, s->generation, false);
}

/* Waits for the worker to end and releases it. Returns whether it ended with status 0. */
static bool reap_worker(Supervisor *s) {
  Worker *worker = s->worker;
  if (worker == NULL) return true;
  if (!worker->exited) (void)uv_process_kill(&worker->process, SIGKILL);
  while (!worker->exited) (void)uv_run(uv_default_loop(), UV_RUN_ONCE);
  (void)uv_run(uv_default_loop(), UV_RUN_NOWAIT);
  const bool clean = worker->status == 0 && !worker->signaled;
  ms_free(worker);
  s->worker = NULL;
  if (s->from_worker != NULL) (void)fclose(s->from_worker);
  s->from_worker = NULL;
  if (s->to_worker != NULL) (void)fclose(s->to_worker);
  s->to_worker = NULL;
  return clean;
}

static void send_worker(Supervisor *s, MsSpan body) {
  if (s->to_worker != NULL) lsp_write_frame(s->to_worker, body);
}

/* ---- what a restart replays ---- */

static MsString id_key(const MsJson *id) {
  MsStrBuild key = ms_strbuild_new();
  ms_strbuild_append_byte(&key, id->kind == MS_JSON_STRING ? 's' : 'n');
  ms_strbuild_append(&key, id->text);
  return ms_strbuild_finish(&key);
}

static void inflight_remove(Supervisor *s, MsSpan key) {
  for (size_t i = 0; i < s->inflight.len; i++) {
    if (!ms_span_equal(ms_string_span(&s->inflight.ptr[i].key), key)) continue;
    ms_string_release(&s->inflight.ptr[i].key);
    ms_string_release(&s->inflight.ptr[i].json);
    s->inflight.ptr[i] = s->inflight.ptr[--s->inflight.len];
    return;
  }
}

static void inflight_add(Supervisor *s, const MsJson *id) {
  MsString key = id_key(id);
  inflight_remove(s, ms_string_span(&key));
  MsStrBuild json = ms_strbuild_new();
  if (id->kind == MS_JSON_STRING) {
    lsp_json_string(&json, id->text);
  } else {
    ms_strbuild_append(&json, id->text);
  }
  inflight_list_push(&s->inflight, (Inflight){key, ms_strbuild_finish(&json)});
}

static void on_client(Supervisor *s, MsSpan frame) {
  MsArena arena = ms_arena_new();
  const MsJson *message = ms_json_parse(&arena, frame);
  if (message != NULL && message->kind == MS_JSON_OBJECT) {
    const MsJson *method = lsp_json_member(message, "method", MS_JSON_STRING);
    const MsJson *id = ms_json_member(message, "id");
    const MsJson *params = ms_json_member(message, "params");
    if (method != NULL && id != NULL && (id->kind == MS_JSON_STRING || id->kind == MS_JSON_NUMBER)) inflight_add(s, id);
    if (method != NULL && ms_span_is_text(method->text, "initialize")) {
      ms_arena_free(&s->initialize_arena);
      s->initialize_arena = ms_arena_new();
      /* numbers and words in the tree point into the text, so the text lives as long as the tree */
      s->initialize = ms_json_parse(&s->initialize_arena, ms_arena_copy(&s->initialize_arena, frame));
    } else if (method != NULL && ms_span_is_text(method->text, "initialized")) {
      s->initialized = true;
    } else if (method != NULL && ms_span_is_text(method->text, "exit")) {
      s->exiting = true;
    } else if (method != NULL && (ms_span_is_text(method->text, "textDocument/didOpen") ||
                                  ms_span_is_text(method->text, "textDocument/didChange"))) {
      (void)lsp_sync_change(&s->docs, ms_span_is_text(method->text, "textDocument/didOpen"), params);
    } else if (method != NULL && ms_span_is_text(method->text, "textDocument/didClose")) {
      const MsJson *uri = lsp_json_member(lsp_json_member(params, "textDocument", MS_JSON_OBJECT), "uri", MS_JSON_STRING);
      if (uri != NULL) lsp_doc_remove(&s->docs, uri->text);
    }
  }
  ms_arena_free(&arena);
  send_worker(s, frame);
}

/* Passes a worker message to the client, dropping the answer to the replayed `initialize`. */
static void on_worker(Supervisor *s, MsSpan frame) {
  MsArena arena = ms_arena_new();
  const MsJson *message = ms_json_parse(&arena, frame);
  if (message != NULL && message->kind == MS_JSON_OBJECT && ms_json_member(message, "method") == NULL) {
    const MsJson *id = ms_json_member(message, "id");
    if (id != NULL && id->kind == MS_JSON_STRING && s->replay_pending && ms_span_is_text(id->text, REPLAY_ID)) {
      s->replay_pending = false;
      ms_arena_free(&arena);
      return;
    }
    if (id != NULL && (id->kind == MS_JSON_STRING || id->kind == MS_JSON_NUMBER)) {
      MsString key = id_key(id);
      inflight_remove(s, ms_string_span(&key));
      ms_string_release(&key);
    }
  }
  ms_arena_free(&arena);
  lsp_write_frame(stdout, frame);
}

static void replay(Supervisor *s) {
  if (s->initialize == NULL) return;
  static MsJson replay_id = {.kind = MS_JSON_STRING};
  replay_id.text = ms_span_of_text(REPLAY_ID);
  for (size_t i = 0; i < s->initialize->count; i++) {
    if (ms_span_is_text(s->initialize->keys[i], "id")) s->initialize->items[i] = &replay_id;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_json_write(&text, s->initialize, 0);
  s->replay_pending = true;
  send_worker(s, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  if (s->initialized) send_worker(s, ms_span_of_text("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"));
  for (size_t i = 0; i < s->docs.len; i++) {
    const LspDoc *doc = &s->docs.ptr[i];
    MsStrBuild open = ms_strbuild_new();
    ms_strbuild_append_text(&open, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":");
    lsp_json_string(&open, ms_string_span(&doc->uri));
    ms_strbuild_printf(&open, ",\"languageId\":\"manuscript\",\"version\":%lld,\"text\":", (long long)doc->version);
    lsp_json_string(&open, ms_string_span(&doc->text));
    ms_strbuild_append_text(&open, "}}}");
    send_worker(s, ms_strbuild_span(&open));
    ms_strbuild_free(&open);
  }
}

/* Fails the unanswered requests, starts a new worker and replays the state. False when it keeps crashing. */
static bool crashed(Supervisor *s) {
  (void)reap_worker(s);
  const uint64_t now = uv_hrtime();
  size_t kept = 0;
  for (size_t i = 0; i < s->restart_count; i++) {
    if (now - s->restarts[i] <= RESTART_WINDOW_NS) s->restarts[kept++] = s->restarts[i];
  }
  s->restart_count = kept;
  if (s->restart_count == RESTART_LIMIT + 1) {
    for (size_t i = 1; i < s->restart_count; i++) s->restarts[i - 1] = s->restarts[i];
    s->restart_count--;
  }
  s->restarts[s->restart_count++] = now;
  for (size_t i = 0; i < s->inflight.len; i++) {
    MsStrBuild failure = ms_strbuild_new();
    ms_strbuild_append_text(&failure, "{\"jsonrpc\":\"2.0\",\"id\":");
    ms_strbuild_append(&failure, ms_string_span(&s->inflight.ptr[i].json));
    ms_strbuild_append_text(&failure, ",\"error\":{\"code\":-32603,\"message\":\"language server crashed and was restarted\"}}");
    lsp_write_frame(stdout, ms_strbuild_span(&failure));
    ms_strbuild_free(&failure);
    ms_string_release(&s->inflight.ptr[i].key);
    ms_string_release(&s->inflight.ptr[i].json);
  }
  s->inflight.len = 0;
  if (s->restart_count > RESTART_LIMIT) {
    (void)fputs("ms-lsp: language server keeps crashing\n", stderr);
    return false;
  }
  if (!start_worker(s)) {
    (void)fputs("ms-lsp: cannot start the worker\n", stderr);
    return false;
  }
  replay(s);
  return true;
}

/* Closes the worker's input and waits for it. After the client's `exit` a failing worker fails the session. */
static int finish(Supervisor *s) {
  if (s->to_worker != NULL) {
    (void)fclose(s->to_worker);
    s->to_worker = NULL;
  }
  const bool clean = reap_worker(s);
  return s->exiting && !clean ? 1 : 0;
}

_Noreturn void lsp_supervise(void) {
#ifndef _WIN32
  (void)signal(SIGPIPE, SIG_IGN); /* a dead worker is noticed through its closed output */
#endif
  MsString log_setting;
  Supervisor s = {.events = lsp_input_create(), .log = ms_env_get("MS_LSP_LOG", &log_setting)};
  ms_string_release(&log_setting);
  if (s.events == NULL || !lsp_input_attach(s.events, stdin, SOURCE_CLIENT, false) || !start_worker(&s)) {
    (void)fputs("ms-lsp: cannot start the worker\n", stderr);
    lsp_input_exit(1);
  }
  MsStrBuild body = ms_strbuild_new();
  int status = 0;
  for (;;) {
    const char *error = "";
    int source;
    const LspFrameStatus frame = lsp_input_next(s.events, &body, &error, &source);
    if (source == SOURCE_CLIENT) {
      if (frame == LSP_FRAME_OK) {
        on_client(&s, ms_strbuild_span(&body));
        continue;
      }
      if (frame == LSP_FRAME_FAILED) {
        (void)fprintf(stderr, "ms-lsp: %s\n", error);
        status = 1;
      }
      if (status != 0) {
        (void)finish(&s);
        break;
      }
      /* The worker sees the end of its input too, answers what it holds and ends. */
      s.draining = true;
      if (s.to_worker != NULL) (void)fclose(s.to_worker);
      s.to_worker = NULL;
      continue;
    }
    if (source != s.generation) continue; /* a worker already replaced */
    if (frame == LSP_FRAME_OK) {
      on_worker(&s, ms_strbuild_span(&body));
    } else if (s.exiting || s.draining) {
      status = finish(&s);
      break;
    } else if (!crashed(&s)) {
      status = 1;
      (void)finish(&s);
      break;
    }
  }
  ms_strbuild_free(&body);
  lsp_input_exit(status);
}
