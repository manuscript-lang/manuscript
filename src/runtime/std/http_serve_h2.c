/* runtime/std/http_serve_h2.c: an HTTP/2 server connection. The connection's task is the pump: it reads,
 * feeds the sans-io session and acts on its events. A writer task is the only one that writes to the stream;
 * each request stream runs its handler in a task of its own. They wake each other through tokens
 * (http_serve_internal.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "base/alloc.h"
#include "runtime/core/unwind.h"
#include "runtime/std/http_serve_internal.h"

enum {
  SETTLE_NS = 1000000,
  WRITER_GRACE_NS = 1000000000,
  CONNECTION_WINDOW = 1 << 20,
  STREAM_WINDOW = 1 << 18
};

void ms_h2_wake(uint64_t token) {
  ms_token_post(token, 1);
}

void ms_h2_flush(MsH2Conn *owner) {
  ms_h2_wake(owner->out_token);
}

/* ---- the streams of a connection ---- */

static MsH2Stream *find_stream(const MsH2Conn *owner, uint32_t id) {
  for (size_t i = 0; i < owner->count; i++) {
    if (owner->streams[i]->id == id) {
      return owner->streams[i];
    }
  }
  return NULL;
}

static void add_stream(MsH2Conn *owner, MsH2Stream *stream) {
  if (owner->count == owner->capacity) {
    owner->capacity = owner->capacity == 0 ? 8 : owner->capacity * 2;
    MsH2Stream **grown = ms_alloc_zeroed(owner->capacity * sizeof *grown);
    if (owner->count > 0) {
      __builtin_memcpy(grown, owner->streams, owner->count * sizeof *grown);
    }
    ms_free(owner->streams);
    owner->streams = grown;
  }
  owner->streams[owner->count++] = stream;
  owner->conn->idle = false;
}

static void remove_stream(MsH2Conn *owner, const MsH2Stream *stream) {
  for (size_t i = 0; i < owner->count; i++) {
    if (owner->streams[i] == stream) {
      owner->streams[i] = owner->streams[--owner->count];
      break;
    }
  }
  owner->conn->idle = owner->count == 0;
  if (owner->count == 0 && owner->conn->worker->closing) {
    ms_serve_conn_close(owner->conn);
  }
}

static void mark_dead(MsH2Conn *owner) {
  owner->dead = true;
  ms_h2_wake(owner->out_token);
  for (size_t i = 0; i < owner->count; i++) {
    ms_h2_wake(owner->streams[i]->token);
  }
}

/* ---- the writer ---- */

static void writer_body(void *arg) {
  MsH2Conn *owner = arg;
  for (;;) {
    MsBytes out = {0};
    ms_h2_take_output(owner->h2, &out);
    if (out.len > 0) {
      MsString err = ms_string_empty();
      MsServeConn *conn = owner->conn;
      const uint8_t status = conn->io.write(conn->io.context, ms_bytes_span(&out), -1, &err);
      ms_string_release(&err);
      ms_bytes_free(&out);
      if (status != MS_STATUS_OK) {
        mark_dead(owner);
        ms_serve_conn_close(conn);
        return;
      }
      continue;
    }
    ms_bytes_free(&out);
    if (owner->dead) {
      return;
    }
    uint64_t value = 0;
    uint32_t result = 0;
    (void)ms_token_park(owner->out_token, -1, &value, &result);
    if ((result & MS_WAIT_CANCELLED) != 0) {
      return;
    }
  }
}

static void writer_task(void *arg) {
  MsH2Conn *owner = arg;
  MsFaultText message = {0};
  (void)ms_guard_call(writer_body, owner, &message);
  ms_fault_text_free(&message);
  owner->writer_done = true;
}

/* ---- a request stream ---- */

static void stream_task(void *arg) {
  MsH2Stream *stream = arg;
  MsH2Conn *owner = stream->owner;
  MsServeShared *shared = owner->conn->worker->shared;
  MsExchange *exchange = stream->exchange;
  const int failure = ms_serve_call_handler(shared, exchange);
  ms_task_limit_current_at(MS_NO_DEADLINE);
  (void)ms_exchange_finish(exchange, failure);
  atomic_fetch_sub(&shared->admitted, 1);
  remove_stream(owner, stream);
  ms_exchange_release(exchange);
  ms_bytes_free(&stream->inbox);
  (void)ms_token_free(stream->token);
  ms_free(stream);
}

/* Answers a request that never reaches a handler. */
static void reject_stream(MsH2Conn *owner, uint32_t id, uint16_t status, const char *text) {
  MsH2Field fields[2];
  MsStrBuild code = ms_strbuild_new();
  ms_strbuild_append_u64(&code, status);
  fields[0] = (MsH2Field){.name = ms_bytes_view(ms_span_of_text(":status")),
                          .value = ms_bytes_view(ms_strbuild_span(&code))};
  fields[1] = (MsH2Field){.name = ms_bytes_view(ms_span_of_text("content-type")),
                          .value = ms_bytes_view(ms_span_of_text("text/plain; charset=utf-8"))};
  if (ms_h2_send_response_headers(owner->h2, id, fields, 2, false)) {
    MsStrBuild body = ms_strbuild_new();
    ms_strbuild_append_text(&body, text);
    ms_strbuild_append_byte(&body, '\n');
    (void)ms_h2_send_data(owner->h2, id, ms_strbuild_span(&body), true);
    ms_strbuild_free(&body);
  }
  ms_strbuild_free(&code);
  ms_h2_flush(owner);
}

static void start_stream(MsH2Conn *owner, const MsH2Event *event) {
  MsServeConn *conn = owner->conn;
  MsServeShared *shared = conn->worker->shared;
  uint16_t status = 400;
  const char *reason = NULL;
  MsH2Stream *stream = ms_alloc_zeroed(sizeof *stream);
  stream->id = event->id;
  stream->owner = owner;
  stream->token = ms_token_new(0);
  const int64_t deadline = ms_sched_deadline_after(shared->limits.timeout_ns);
  stream->exchange =
      ms_exchange_new_h2(conn, stream, &event->fields, event->end_stream, deadline, &status, &reason);
  const bool admitted = stream->exchange != NULL && !conn->worker->closing && ms_serve_admit(shared);
  MsTaskStatus spawned = MS_TASK_OK;
  if (admitted) {
    add_stream(owner, stream);
    stream->task = ms_task_spawn(stream_task, stream, MS_SPAWN_DETACHED, 0, &spawned);
  }
  if (admitted && stream->task != 0) {
    return;
  }
  if (admitted) {
    remove_stream(owner, stream);
    atomic_fetch_sub(&shared->admitted, 1);
    status = 503;
    reason = "server busy";
  } else if (stream->exchange != NULL) {
    status = 503;
    reason = conn->worker->closing ? "server closed" : "server busy";
  }
  reject_stream(owner, event->id, status, reason);
  if (stream->exchange != NULL) {
    ms_exchange_release(stream->exchange);
  }
  (void)ms_token_free(stream->token);
  ms_free(stream);
}

/* ---- the pump ---- */

static void on_data(MsH2Conn *owner, const MsH2Event *event) {
  MsH2Stream *stream = find_stream(owner, event->id);
  if (stream == NULL || stream->reset) {
    ms_h2_release(owner->h2, event->id, event->data.len);
    return;
  }
  if (event->data.len > 0) {
    __builtin_memcpy(ms_list_extend(&stream->inbox, 1, event->data.len), event->data.ptr, event->data.len);
  }
  stream->end_in = stream->end_in || event->end_stream;
  ms_h2_wake(stream->token);
}

static void on_reset(MsH2Conn *owner, const MsH2Event *event) {
  MsH2Stream *stream = find_stream(owner, event->id);
  if (stream == NULL) {
    return;
  }
  stream->reset = true;
  ms_task_cancel(stream->task);
  ms_h2_wake(stream->token);
}

static void dispatch(MsH2Conn *owner, const MsH2Event *event) {
  MsH2Stream *known = find_stream(owner, event->id);
  switch (event->kind) {
  case MS_H2_HEADERS:
    if (known == NULL) {
      start_stream(owner, event);
    } else if (event->end_stream) {
      known->end_in = true; /* trailers */
      ms_h2_wake(known->token);
    }
    break;
  case MS_H2_DATA:
    on_data(owner, event);
    break;
  case MS_H2_RESET:
    on_reset(owner, event);
    break;
  case MS_H2_WINDOW_OPENED:
    for (size_t i = 0; i < owner->count; i++) {
      if (event->id == 0 || owner->streams[i]->id == event->id) {
        ms_h2_wake(owner->streams[i]->token);
      }
    }
    break;
  default:
    break;
  }
}

static void drain_events(MsH2Conn *owner) {
  MsH2Event event;
  while (ms_h2_poll(owner->h2, &event)) {
    dispatch(owner, &event);
    ms_h2_event_release(&event);
  }
}

static uint32_t clamp32(size_t value) {
  return value > UINT32_MAX ? 0 : (uint32_t)value; /* 0: the protocol default or unlimited */
}

static void pump(MsH2Conn *owner) {
  MsServeConn *conn = owner->conn;
  const MsServeLimits *limits = &conn->worker->shared->limits;
  conn->idle = true;
  for (;;) {
    if (owner->dead || (conn->worker->closing && owner->count == 0)) {
      return;
    }
    const int64_t deadline = owner->count == 0 ? ms_sched_deadline_after(limits->timeout_ns) : MS_NO_DEADLINE;
    MsString err = ms_string_empty();
    const uint8_t status = ms_serve_fill(conn, deadline, &err);
    ms_string_release(&err);
    if (status != MS_STATUS_OK) {
      return;
    }
    const MsSpan input = ms_serve_unread(conn);
    const bool fed = ms_h2_feed(owner->h2, input);
    ms_serve_consume(conn, input.len);
    drain_events(owner);
    ms_h2_flush(owner);
    if (!fed) {
      return;
    }
  }
}

static void pump_body(void *arg) {
  pump(arg);
}

/* Ends the connection: queue GOAWAY, stop every stream, wait for the tasks, let the writer flush. */
static void wind_down(MsH2Conn *owner) {
  ms_h2_shutdown(owner->h2, MS_H2_NO_ERROR);
  mark_dead(owner);
  for (size_t i = 0; i < owner->count; i++) {
    owner->streams[i]->reset = true;
    ms_task_cancel(owner->streams[i]->task);
  }
  int64_t patience = ms_sched_deadline_after(WRITER_GRACE_NS);
  while (owner->count > 0 || !owner->writer_done) {
    if (owner->count == 0 && ms_sched_now() > patience) {
      ms_serve_conn_close(owner->conn); /* a writer stuck on a stalled peer fails */
      patience = MS_NO_DEADLINE;
    }
    ms_task_sleep(SETTLE_NS);
  }
}

void ms_serve_h2(MsServeConn *conn) {
  const MsServeLimits *limits = &conn->worker->shared->limits;
  const MsH2Settings settings = {.max_concurrent = clamp32(limits->admission),
                                 .initial_window = STREAM_WINDOW,
                                 .max_header_list = clamp32(limits->header),
                                 .connection_window = CONNECTION_WINDOW};
  MsH2Conn *owner = ms_alloc_zeroed(sizeof *owner);
  owner->conn = conn;
  owner->h2 = ms_h2_new(true, &settings);
  owner->out_token = ms_token_new(0);
  MsTaskStatus spawned = MS_TASK_OK;
  if (ms_task_spawn(writer_task, owner, MS_SPAWN_DETACHED, 0, &spawned) != 0) {
    MsFaultText message = {0};
    ms_h2_flush(owner);
    (void)ms_guard_call(pump_body, owner, &message);
    ms_fault_text_free(&message);
    wind_down(owner);
  }
  (void)ms_token_free(owner->out_token);
  ms_h2_free(owner->h2);
  ms_free(owner->streams);
  ms_free(owner);
}
