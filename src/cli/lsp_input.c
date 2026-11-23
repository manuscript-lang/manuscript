/* cli/lsp_input.c: the reader thread of `ms lsp`. It owns standard input, queues frames for the session and answers
 * `$/cancelRequest` itself by marking the request pending in a table the session reads. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "cli/lsp_input.h"

#include <stdlib.h>
#include <uv.h>

#include "base/alloc.h"
#include "base/arena.h"
#include "cli/json_value.h"

enum { QUEUE_CAPACITY = 256 };

typedef struct Entry {
  MsString body;
  LspFrameStatus status;
  const char *error;
  bool change;
  int source;
} Entry;

typedef struct Pending {
  MsString key; /* the id's kind letter, then its text */
  bool canceled;
} Pending;

MS_LIST_DEFINE(PendingList, pending_list, Pending)

struct LspInput {
  uv_mutex_t lock;
  uv_cond_t readable, writable;
  Entry queue[QUEUE_CAPACITY];
  size_t head, count;
  PendingList pending;
};

static MsString id_key(bool is_string, MsSpan id) {
  MsStrBuild key = ms_strbuild_new();
  ms_strbuild_append_byte(&key, is_string ? 's' : 'n');
  ms_strbuild_append(&key, id);
  return ms_strbuild_finish(&key);
}

static Pending *find_pending(LspInput *input, MsSpan key) {
  for (size_t i = 0; i < input->pending.len; i++) {
    if (ms_span_equal(ms_string_span(&input->pending.ptr[i].key), key)) return &input->pending.ptr[i];
  }
  return NULL;
}

/* Records a request's id, or marks the canceled one. Returns true for a cancellation, which is not queued. */
static bool note_message(LspInput *input, MsSpan body, bool *change) {
  *change = false;
  MsArena arena = ms_arena_new();
  const MsJson *message = ms_json_parse(&arena, body);
  bool canceled = false;
  if (message != NULL && message->kind == MS_JSON_OBJECT) {
    const MsJson *method = ms_json_member(message, "method");
    const MsJson *id = ms_json_member(message, "id");
    const MsJson *jsonrpc = ms_json_member(message, "jsonrpc");
    const bool is_method = method != NULL && method->kind == MS_JSON_STRING;
    if (is_method && ms_span_is_text(method->text, "$/cancelRequest")) {
      const MsJson *params = ms_json_member(message, "params");
      const MsJson *target = params != NULL && params->kind == MS_JSON_OBJECT ? ms_json_member(params, "id") : NULL;
      if (target != NULL && (target->kind == MS_JSON_STRING || target->kind == MS_JSON_NUMBER)) {
        MsString key = id_key(target->kind == MS_JSON_STRING, target->text);
        uv_mutex_lock(&input->lock);
        Pending *entry = find_pending(input, ms_string_span(&key));
        if (entry != NULL) entry->canceled = true;
        uv_mutex_unlock(&input->lock);
        ms_string_release(&key);
      }
      canceled = true;
    } else {
      if (id != NULL && (id->kind == MS_JSON_STRING || id->kind == MS_JSON_NUMBER)) {
        uv_mutex_lock(&input->lock);
        Pending fresh = {id_key(id->kind == MS_JSON_STRING, id->text), false};
        Pending *known = find_pending(input, ms_string_span(&fresh.key));
        if (known != NULL) {
          known->canceled = false;
          ms_string_release(&fresh.key);
        } else {
          pending_list_push(&input->pending, fresh);
        }
        uv_mutex_unlock(&input->lock);
      }
      *change = id == NULL && is_method && jsonrpc != NULL && jsonrpc->kind == MS_JSON_STRING &&
                ms_span_is_text(jsonrpc->text, "2.0") && ms_span_is_text(method->text, "textDocument/didChange");
    }
  }
  ms_arena_free(&arena);
  return canceled;
}

static void enqueue(LspInput *input, Entry entry) {
  uv_mutex_lock(&input->lock);
  while (input->count == QUEUE_CAPACITY) uv_cond_wait(&input->writable, &input->lock);
  input->queue[(input->head + input->count) % QUEUE_CAPACITY] = entry;
  input->count++;
  uv_cond_signal(&input->readable);
  uv_mutex_unlock(&input->lock);
}

typedef struct Reader {
  LspInput *input;
  FILE *file;
  int source;
  bool track;
  uv_thread_t thread;
} Reader;

static void read_loop(void *argument) {
  Reader *reader = argument;
  LspInput *input = reader->input;
  MsStrBuild body = ms_strbuild_new();
  for (;;) {
    const char *error = "";
    const LspFrameStatus status = lsp_read_frame(reader->file, &body, &error);
    if (status != LSP_FRAME_OK) {
      enqueue(input, (Entry){.status = status, .error = error, .source = reader->source});
      break;
    }
    bool change = false;
    if (reader->track && note_message(input, ms_strbuild_span(&body), &change)) continue;
    enqueue(input, (Entry){.body = ms_string_from_span(ms_strbuild_span(&body)), .status = LSP_FRAME_OK, .change = change,
                           .source = reader->source});
  }
  ms_strbuild_free(&body);
}

LspInput *lsp_input_create(void) {
  LspInput *input = ms_alloc(sizeof *input);
  *input = (LspInput){0};
  if (uv_mutex_init(&input->lock) != 0) {
    ms_free(input);
    return NULL;
  }
  (void)uv_cond_init(&input->readable);
  (void)uv_cond_init(&input->writable);
  return input;
}

bool lsp_input_attach(LspInput *input, FILE *file, int source, bool track) {
  Reader *reader = ms_alloc(sizeof *reader);
  *reader = (Reader){.input = input, .file = file, .source = source, .track = track};
  if (uv_thread_create(&reader->thread, read_loop, reader) != 0) {
    ms_free(reader);
    return false;
  }
  return true;
}

LspInput *lsp_input_start(FILE *file) {
  LspInput *input = lsp_input_create();
  if (input != NULL && !lsp_input_attach(input, file, 0, true)) return NULL;
  return input;
}

LspFrameStatus lsp_input_next(LspInput *input, MsStrBuild *body, const char **error, int *source) {
  uv_mutex_lock(&input->lock);
  while (input->count == 0) uv_cond_wait(&input->readable, &input->lock);
  Entry entry = input->queue[input->head];
  input->head = (input->head + 1) % QUEUE_CAPACITY;
  input->count--;
  uv_cond_signal(&input->writable);
  uv_mutex_unlock(&input->lock);
  if (source != NULL) *source = entry.source;
  ms_strbuild_clear(body);
  if (entry.status == LSP_FRAME_OK) {
    ms_strbuild_append(body, ms_string_span(&entry.body));
    ms_string_release(&entry.body);
  } else {
    *error = entry.error;
  }
  return entry.status;
}

bool lsp_input_next_is_change(LspInput *input) {
  uv_mutex_lock(&input->lock);
  const bool change = input->count > 0 && input->queue[input->head].status == LSP_FRAME_OK && input->queue[input->head].change;
  uv_mutex_unlock(&input->lock);
  return change;
}

bool lsp_input_canceled(LspInput *input, bool is_string, MsSpan id) {
  MsString key = id_key(is_string, id);
  uv_mutex_lock(&input->lock);
  const Pending *entry = find_pending(input, ms_string_span(&key));
  const bool canceled = entry != NULL && entry->canceled;
  uv_mutex_unlock(&input->lock);
  ms_string_release(&key);
  return canceled;
}

void lsp_input_done(LspInput *input, bool is_string, MsSpan id) {
  MsString key = id_key(is_string, id);
  uv_mutex_lock(&input->lock);
  for (size_t i = 0; i < input->pending.len; i++) {
    if (!ms_span_equal(ms_string_span(&input->pending.ptr[i].key), ms_string_span(&key))) continue;
    ms_string_release(&input->pending.ptr[i].key);
    input->pending.ptr[i] = input->pending.ptr[--input->pending.len];
    break;
  }
  uv_mutex_unlock(&input->lock);
  ms_string_release(&key);
}

_Noreturn void lsp_input_exit(int status) {
  (void)fflush(stdout);
  (void)fflush(stderr);
  _Exit(status);
}
