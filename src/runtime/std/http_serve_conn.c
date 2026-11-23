/* runtime/std/http_serve_conn.c: a server connection: its input buffer, the request loop of HTTP/1 and the
 * worker that owns the connections (http_serve.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <stdio.h>

#include "base/alloc.h"
#include "runtime/core/unwind.h"
#include "runtime/std/http_serve_internal.h"
#include "runtime/std/time_internal.h"

enum { HEAD_CAP = 1 << 30, DRAIN_WINDOW_NS = 500000000, DRAIN_BYTES = 1 << 20, GRACE_POLL_NS = 5000000 };
#define HANDSHAKE_NS ((int64_t)10000000000)

/* ---- shared state ---- */

MsServeShared *ms_serve_shared_new(const MsServeLimits *limits, MsServeHandler handler, void *context,
                                   void (*release)(void *)) {
  MsServeShared *shared = ms_alloc_zeroed(sizeof *shared);
  atomic_init(&shared->refs, 1);
  atomic_init(&shared->admitted, 0);
  shared->limits = *limits;
  shared->handler = handler;
  shared->handler_context = context;
  shared->handler_release = release;
  return shared;
}

MsServeShared *ms_serve_shared_retain(MsServeShared *shared) {
  atomic_fetch_add(&shared->refs, 1);
  return shared;
}

void ms_serve_shared_release(MsServeShared *shared) {
  if (atomic_fetch_sub(&shared->refs, 1) != 1) {
    return;
  }
  if (shared->handler_release != NULL) {
    shared->handler_release(shared->handler_context);
  }
  if (shared->secure_release != NULL) {
    shared->secure_release(shared->secure_context);
  }
  ms_free(shared);
}

/* ---- the connection's stream ---- */

MsSpan ms_serve_unread(const MsServeConn *conn) {
  return ms_span_of(conn->in.ptr + conn->pos, conn->in.len - conn->pos);
}

void ms_serve_consume(MsServeConn *conn, size_t n) {
  conn->pos += n;
  if (conn->pos == conn->in.len) {
    conn->in.len = 0;
    conn->pos = 0;
  }
}

uint8_t ms_serve_fill(MsServeConn *conn, int64_t deadline, MsString *err) {
  if (conn->eof) {
    return MS_STATUS_NONE;
  }
  MsBytes chunk = {0};
  const uint8_t status = conn->io.read(conn->io.context, ms_serve_left(deadline), &chunk, err);
  if (status == MS_STATUS_OK) {
    __builtin_memcpy(ms_list_extend(&conn->in, 1, chunk.len), chunk.ptr, chunk.len);
  } else if (status == MS_STATUS_NONE) {
    conn->eof = true;
  }
  ms_bytes_free(&chunk);
  return status;
}

uint8_t ms_serve_send(MsServeConn *conn, MsSpan data, int64_t deadline, MsString *err) {
  if (data.len == 0) {
    return MS_STATUS_OK;
  }
  return conn->io.write(conn->io.context, data, ms_serve_left(deadline), err);
}

bool ms_serve_body_allowed(int64_t status) {
  return !(status >= 100 && status < 200) && status != 204 && status != 304;
}

static void date_line(MsStrBuild *out) {
  MsStrBuild value = ms_strbuild_new();
  ms_h1_http_date(&value, ms_clock_realtime().seconds);
  ms_h1_header_line(out, ms_span_of_text("Date"), ms_strbuild_span(&value));
  ms_strbuild_free(&value);
}

void ms_serve_date_line(MsStrBuild *out) {
  date_line(out);
}

void ms_serve_error_bytes(MsStrBuild *out, uint16_t status, const char *message, bool close) {
  MsStrBuild body = ms_strbuild_new();
  ms_strbuild_append_text(&body, message);
  ms_strbuild_append_byte(&body, '\n');
  ms_h1_status_line(out, status);
  ms_h1_header_line(out, ms_span_of_text("Content-Type"), ms_span_of_text("text/plain; charset=utf-8"));
  ms_h1_header_line(out, ms_span_of_text("X-Content-Type-Options"), ms_span_of_text("nosniff"));
  date_line(out);
  ms_h1_header_number(out, ms_span_of_text("Content-Length"), ms_strbuild_span(&body).len);
  if (close) {
    ms_h1_header_line(out, ms_span_of_text("Connection"), ms_span_of_text("close"));
  }
  ms_strbuild_append_text(out, "\r\n");
  ms_strbuild_append(out, ms_strbuild_span(&body));
  ms_strbuild_free(&body);
}

/* ---- answering and closing ---- */

void ms_serve_conn_close(MsServeConn *conn) {
  if (conn->io.close != NULL) {
    conn->io.close(conn->io.context);
  }
}

/* Reads and drops what the peer is still sending, for at most a short while, so closing does not reset a
 * connection whose answer is in flight. */
static void drain_peer(MsServeConn *conn) {
  if (conn->io.shutdown_write == NULL || conn->eof) {
    return;
  }
  conn->io.shutdown_write(conn->io.context);
  const int64_t deadline = ms_sched_deadline_after(DRAIN_WINDOW_NS);
  size_t total = 0;
  while (total < DRAIN_BYTES) {
    MsString err = ms_string_empty();
    const size_t before = conn->in.len;
    const uint8_t status = ms_serve_fill(conn, deadline, &err);
    ms_string_release(&err);
    total += conn->in.len - before;
    conn->in.len = 0;
    conn->pos = 0;
    if (status != MS_STATUS_OK) {
      return;
    }
  }
}

/* Writes a refusal and closes; `drain` waits for the peer's end of a request it was still sending. */
static void refuse(MsServeConn *conn, uint16_t status, const char *message, bool drain) {
  MsStrBuild out = ms_strbuild_new();
  ms_serve_error_bytes(&out, status, message, true);
  MsString err = ms_string_empty();
  const uint8_t sent = ms_serve_send(conn, ms_strbuild_span(&out), MS_NO_DEADLINE, &err);
  ms_string_release(&err);
  ms_strbuild_free(&out);
  if (sent == MS_STATUS_OK && drain) {
    drain_peer(conn);
  }
}

/* ---- one request ---- */

typedef enum Next { NEXT_CLOSE, NEXT_AGAIN, NEXT_MOVED } Next;

/* The request head at the front of the input: reads until it is complete or refused. */
static Next read_head(MsServeConn *conn, const MsServeLimits *limits, MsH1Request *head, int64_t *started) {
  const size_t limit = limits->header > HEAD_CAP ? HEAD_CAP : limits->header;
  conn->idle = true;
  for (;;) {
    MsH1Bad bad = {0};
    const MsSpan input = ms_serve_unread(conn);
    const MsH1Parse parsed = input.len == 0 ? MS_H1_PARTIAL : ms_h1_parse_request(input, limit, head, &bad);
    if (parsed == MS_H1_COMPLETE) {
      conn->idle = false;
      ms_serve_consume(conn, head->length);
      *started = ms_sched_deadline_after(limits->timeout_ns); /* the request's own budget starts here */
      return NEXT_AGAIN;
    }
    if (parsed == MS_H1_BAD) {
      conn->idle = false;
      refuse(conn, bad.status, bad.reason, true);
      return NEXT_CLOSE;
    }
    if (input.len > 0) {
      conn->idle = false; /* a head has begun: closing would lose it */
    }
    if (*started == MS_NO_DEADLINE || input.len == 0) {
      *started = ms_sched_deadline_after(limits->timeout_ns);
    }
    MsString err = ms_string_empty();
    const bool waiting = input.len == 0;
    if (waiting) {
      ms_serve_idle_list(conn); /* another thread may take the connection while this one is held up */
    }
    const uint8_t status = ms_serve_fill(conn, *started, &err);
    ms_string_release(&err);
    if (waiting && ms_serve_idle_unlist(conn)) {
      return NEXT_MOVED;
    }
    if (status != MS_STATUS_OK) {
      if (status == MS_STATUS_TIMED_OUT && input.len > 0) {
        refuse(conn, 408, "request timeout", false);
      }
      return NEXT_CLOSE;
    }
  }
}

/* Why a parsed head is refused, or NULL. `target` is filled for a request that passes. */
static const char *check_head(const MsH1Request *head, const MsServeLimits *limits, MsH1Scan *scan,
                              MsHttpTarget *target, MsH1Framing *framing, uint16_t *status) {
  *status = 400;
  *scan = ms_h1_scan(head->fields);
  if (head->minor == 1 && scan->hosts == 0) {
    return "missing required Host header";
  }
  if (scan->hosts > 1) {
    return "too many Host headers";
  }
  if (scan->hosts == 1 && !ms_http_valid_authority(scan->host)) {
    return "invalid Host header";
  }
  MsH1Bad bad = {0};
  if (!ms_h1_request_framing(head->minor, head->fields, scan, framing, &bad)) {
    *status = bad.status;
    return bad.reason;
  }
  const char *reason = NULL;
  if (!ms_http_target_parse(ms_string_span(&head->target), target, &reason)) {
    return reason;
  }
  if (ms_span_is_text(ms_string_span(&target->path), "*") &&
      !ms_span_is_text(ms_string_span(&head->method), "OPTIONS")) {
    ms_http_target_release(target);
    return "asterisk-form target needs OPTIONS";
  }
  if (!scan->text) {
    ms_http_target_release(target);
    return "invalid UTF-8 request";
  }
  if (framing->kind == MS_H1_LENGTH && framing->length > limits->body) {
    ms_http_target_release(target);
    *status = 413;
    return "invalid or oversized request body";
  }
  return NULL;
}

bool ms_serve_admit(MsServeShared *shared) {
  const size_t before = atomic_fetch_add(&shared->admitted, 1);
  if (before < shared->limits.admission) {
    return true;
  }
  atomic_fetch_sub(&shared->admitted, 1);
  return false;
}

/* The request task: the handler runs under the request's time limit, in a guard so a fault or a stop ends
 * only this request and the task always reports how it ended. */
typedef struct Request {
  MsServeShared *shared;
  MsExchange *exchange;
  MsHandlerEnd end;
} Request;

static void request_body(void *arg) {
  Request *request = arg;
  ms_task_limit_current_at(request->exchange->deadline);
  request->end = request->shared->handler(request->shared->handler_context, request->exchange);
}

int ms_serve_call_handler(MsServeShared *shared, MsExchange *exchange) {
  Request request = {.shared = shared, .exchange = exchange, .end = MS_HANDLER_OK};
  MsFaultText message = {0};
  const MsGuardStatus guard = ms_guard_call(request_body, &request, &message);
  int failure = 3;
  if (guard == MS_GUARD_OK) {
    failure = request.end == MS_HANDLER_OK ? 0 : 1;
  } else if (guard == MS_GUARD_FAULT) {
    failure = 2;
    (void)fwrite("HTTP stream handler fault: ", 1, 27, stderr);
    (void)fwrite(message.bytes, 1, message.length, stderr);
    (void)fputc('\n', stderr);
  }
  ms_fault_text_free(&message);
  return failure;
}

static void request_task(void *arg) {
  Request *request = arg;
  MsExchange *exchange = request->exchange;
  exchange->failure = ms_serve_call_handler(request->shared, exchange);
  ms_exchange_release(exchange);
  ms_free(request);
}

typedef struct Watch {
  MsServeConn *conn;
  MsTaskHandle handler;
} Watch;

/* Waits for the peer to leave while the handler runs and cancels the handler when it does. A request with no
 * body leaves the stream unread, so this is the only reader. Bytes that arrive instead (a pipelined request) end
 * the watch and wait in the buffer for the next turn. */
static void watch_peer(void *arg) {
  Watch *watch = arg;
  MsString err = ms_string_empty();
  const uint8_t status = ms_serve_fill(watch->conn, MS_NO_DEADLINE, &err);
  ms_string_release(&err);
  if (status == MS_STATUS_NONE) {
    ms_task_cancel(watch->handler);
  }
}

/* 0: the handler returned; 1: it returned an error; 2: it faulted; 3: it ran out of time or was stopped. */
static int run_handler(MsServeShared *shared, MsExchange *exchange, bool watching) {
  Request *request = ms_alloc_zeroed(sizeof *request);
  request->shared = shared;
  request->exchange = exchange;
  ms_exchange_retain(exchange);
  MsTaskStatus spawned = MS_TASK_OK;
  /* First in line: the request runs before the other ready connections are read, so a handler that computes
   * leaves them unread, where another thread can take them. */
  const MsTaskHandle task = ms_task_spawn(request_task, request, MS_SPAWN_FRONT, 0, &spawned);
  if (task == 0) {
    ms_exchange_release(exchange);
    ms_free(request);
    return 2;
  }
  Watch watch = {exchange->conn, task};
  MsTaskHandle watcher = 0;
  if (watching && !exchange->conn->eof) {
    watcher = ms_task_spawn(watch_peer, &watch, 0, 0, &spawned);
  }
  uint8_t outcome = 0;
  MsFaultText message = {0};
  const MsTaskStatus joined = ms_task_join(task, &outcome, &message);
  if (watcher != 0) {
    uint8_t ignored = 0;
    MsFaultText ignored_message = {0};
    ms_task_cancel(watcher);
    (void)ms_task_join(watcher, &ignored, &ignored_message);
    ms_fault_text_free(&ignored_message);
  }
  if (joined != MS_TASK_OK || outcome == 2) {
    ms_task_cancel(task); /* this task was stopped while waiting: the request ends with it */
    return 3;
  }
  ms_fault_text_free(&message);
  return exchange->failure;
}

/* Serves the request whose head was read; reports whether the connection can take another. */
static Next serve_request(MsServeConn *conn, MsServeShared *shared, MsH1Request *head, int64_t started) {
  MsH1Scan scan;
  MsHttpTarget target = {0};
  MsH1Framing framing = {0};
  uint16_t status = 400;
  const char *reason = check_head(head, &shared->limits, &scan, &target, &framing, &status);
  if (reason != NULL) {
    ms_h1_request_release(head);
    refuse(conn, status, reason, true);
    return NEXT_CLOSE;
  }
  const bool keep_alive = ms_h1_scan_keep_alive(&scan, head->minor);
  if (conn->worker->closing || !ms_serve_admit(shared)) {
    ms_h1_request_release(head);
    ms_http_target_release(&target);
    refuse(conn, 503, conn->worker->closing ? "server closed" : "server busy", true);
    return NEXT_CLOSE;
  }
  MsExchange *exchange =
      ms_exchange_new(conn, head, &target, framing, keep_alive, scan.expect_continue, started);
  /* A request that asks to upgrade hands the stream to the handler, which reads it itself. */
  MsSpan upgrade = ms_span_of(NULL, 0);
  const bool upgrading = ms_headers_first(exchange->headers, ms_span_of_text("Upgrade"), &upgrade);
  const int failure = run_handler(shared, exchange, framing.kind == MS_H1_NO_BODY && !upgrading);
  atomic_fetch_sub(&shared->admitted, 1);
  const bool open = ms_exchange_finish(exchange, failure) && !conn->worker->closing;
  ms_exchange_release(exchange);
  return open ? NEXT_AGAIN : NEXT_CLOSE;
}

static void unlink_conn(MsServeConn *conn) {
  MsServeWorker *worker = conn->worker;
  if (conn->prev != NULL) {
    conn->prev->next = conn->next;
  } else {
    worker->conns = conn->next;
  }
  if (conn->next != NULL) {
    conn->next->prev = conn->prev;
  }
  worker->count--;
}

/* The handshake of a secure listener, bounded so a client that never answers does not hold the task. */
static Next handshake(MsServeConn *conn, const MsServeShared *shared) {
  if (shared->secure == NULL) {
    return NEXT_AGAIN;
  }
  const int64_t limit = shared->limits.timeout_ns < 0 ? HANDSHAKE_NS : shared->limits.timeout_ns;
  MsString err = ms_string_empty();
  const uint8_t status = shared->secure(shared->secure_context, &conn->io, limit, &conn->h2, &err);
  ms_string_release(&err);
  return status == MS_STATUS_OK ? NEXT_AGAIN : NEXT_CLOSE;
}

static void connection_loop(void *arg) {
  MsServeConn *conn = arg;
  MsServeShared *shared = conn->worker->shared;
  Next next = handshake(conn, shared);
  if (next == NEXT_AGAIN && conn->h2) {
    ms_serve_h2(conn);
    return;
  }
  while (next == NEXT_AGAIN && !conn->worker->closing) {
    MsH1Request head = {0};
    int64_t started = MS_NO_DEADLINE;
    next = read_head(conn, &shared->limits, &head, &started);
    if (next == NEXT_AGAIN) {
      next = serve_request(conn, shared, &head, started);
    }
  }
}

static void connection_task(void *arg) {
  MsServeConn *conn = arg;
  MsFaultText message = {0};
  (void)ms_guard_call(connection_loop, conn, &message);
  ms_fault_text_free(&message);
  const bool taken = ms_serve_idle_unlist(conn); /* also when the task was cancelled while it waited */
  if (!taken) {
    ms_serve_conn_close(conn);
  }
  unlink_conn(conn);
  if (!taken && conn->io.release != NULL) {
    conn->io.release(conn->io.context);
  }
  ms_bytes_free(&conn->in);
  ms_free(conn);
}

/* ---- the worker ---- */

MsServeWorker *ms_serve_worker_new(MsServeShared *shared) {
  MsServeWorker *worker = ms_alloc_zeroed(sizeof *worker);
  worker->shared = ms_serve_shared_retain(shared);
  worker->idle = ms_serve_idle_open(worker);
  return worker;
}

static void adopt(MsServeWorker *worker, const MsWsTransport *stream, bool h2, MsBytes first) {
  MsServeConn *conn = ms_alloc_zeroed(sizeof *conn);
  conn->worker = worker;
  conn->io = *stream;
  conn->h2 = h2;
  if (first.len > 0) {
    __builtin_memcpy(ms_list_extend(&conn->in, 1, first.len), first.ptr, first.len);
  }
  conn->next = worker->conns;
  if (conn->next != NULL) {
    conn->next->prev = conn;
  }
  worker->conns = conn;
  worker->count++;
  MsTaskStatus status = MS_TASK_OK;
  conn->task = ms_task_spawn(connection_task, conn, MS_SPAWN_DETACHED, 0, &status);
  if (conn->task == 0) {
    ms_serve_conn_close(conn);
    unlink_conn(conn);
    if (conn->io.release != NULL) {
      conn->io.release(conn->io.context);
    }
    ms_bytes_free(&conn->in);
    ms_free(conn);
  }
}

void ms_serve_worker_adopt(MsServeWorker *worker, const MsWsTransport *stream, bool h2) {
  adopt(worker, stream, h2, (MsBytes){0});
}

bool ms_serve_worker_resume(MsServeWorker *worker, const MsWsTransport *stream, MsBytes first) {
  if (worker->closing) {
    return false;
  }
  adopt(worker, stream, false, first);
  ms_bytes_free(&first);
  return true;
}

static void close_idle(MsServeWorker *worker) {
  for (MsServeConn *conn = worker->conns; conn != NULL; conn = conn->next) {
    if (conn->idle && !ms_serve_idle_taken(conn)) {
      ms_serve_conn_close(conn);
    }
  }
}

void ms_serve_worker_close(MsServeWorker *worker) {
  worker->closing = true;
  const int64_t deadline = worker->shared->limits.grace_ns < 0
                               ? MS_NO_DEADLINE
                               : ms_sched_deadline_after(worker->shared->limits.grace_ns);
  while (worker->count > 0 && ms_sched_now() < deadline) {
    close_idle(worker);
    ms_task_sleep(GRACE_POLL_NS);
  }
  for (MsServeConn *conn = worker->conns; conn != NULL; conn = conn->next) {
    ms_task_cancel(conn->task);
    if (!ms_serve_idle_taken(conn)) {
      ms_serve_conn_close(conn);
    }
  }
  while (worker->count > 0) {
    ms_task_sleep(GRACE_POLL_NS);
  }
  if (worker->idle != NULL) {
    ms_serve_idle_close(worker->idle);
  }
  ms_serve_shared_release(worker->shared);
  ms_free(worker);
}
