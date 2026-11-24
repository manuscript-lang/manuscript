/* runtime/std/http_serve_exchange.c: one server exchange over HTTP/1: reading the request body, writing the
 * response and completing the request after the handler (http_serve_internal.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <stdlib.h>

#include "base/alloc.h"
#include "base/chars.h"
#include "runtime/core/unwind.h"
#include "runtime/std/http_serve_internal.h"
#include "runtime/std/time_internal.h"

enum { CHUNK = 65536, DRAIN_LIMIT = 256 * 1024 };

static void set_text(MsString *err, const char *text) {
  ms_string_release(err);
  *err = ms_string_from_span(ms_span_of_text(text));
}

/* ---- lifetime ---- */

static void exchange_drop(MsObj *object) {
  ms_exchange_release((MsExchange *)(void *)object);
}

void ms_exchange_retain(MsExchange *exchange) {
  exchange->refs++;
}

void ms_exchange_release(MsExchange *exchange) {
  if (--exchange->refs > 0) {
    return;
  }
  ms_string_release(&exchange->method);
  ms_string_release(&exchange->path);
  ms_string_release(&exchange->query);
  ms_headers_free(exchange->headers);
  ms_headers_free(exchange->staged);
  if (exchange->websocket != NULL) {
    ms_ws_session_release(exchange->websocket);
  }
  ms_h1_body_free(&exchange->body);
  ms_bytes_free(&exchange->decoded);
  ms_free(exchange);
}

MsObj *ms_exchange_handle(MsExchange *exchange) {
  ms_exchange_retain(exchange);
  return &exchange->header;
}

MsExchange *ms_exchange_alloc(MsServeConn *conn, int64_t deadline) {
  MsExchange *exchange = ms_alloc_zeroed(sizeof *exchange);
  const MsServeLimits *limits = &conn->worker->shared->limits;
  exchange->header.drop = exchange_drop;
  exchange->refs = 1;
  exchange->conn = conn;
  exchange->limits = limits;
  exchange->remaining_read = limits->body;
  exchange->remaining_write = limits->response;
  exchange->staged = ms_headers_new();
  exchange->tls = conn->worker->shared->secure != NULL;
  exchange->deadline = deadline;
  return exchange;
}

MsExchange *ms_exchange_new(MsServeConn *conn, MsH1Request *head, MsHttpTarget *target, MsH1Framing framing,
                            bool keep_alive, bool expect_continue, int64_t deadline) {
  MsExchange *exchange = ms_exchange_alloc(conn, deadline);
  exchange->method = head->method;
  exchange->path = target->path;
  exchange->query = target->query;
  exchange->protocol = head->minor == 1 ? "HTTP/1.1" : "HTTP/1.0";
  exchange->headers = head->fields;
  ms_headers_remove(exchange->headers, ms_span_of_text("Transfer-Encoding"));
  if (target->has_host) {
    ms_headers_set(exchange->headers, ms_span_of_text("Host"), ms_string_span(&target->host));
  }
  ms_string_release(&target->host);
  ms_string_release(&head->target);
  exchange->body = ms_h1_body_new(framing);
  exchange->minor = head->minor;
  exchange->expect_continue = expect_continue;
  exchange->is_head = ms_span_is_text(ms_string_span(&exchange->method), "HEAD");
  exchange->close_conn = !keep_alive || head->minor == 0;
  return exchange;
}

/* ---- the stream ---- */

static bool is_closed(const MsExchange *exchange) {
  return exchange->closed || exchange->upgraded || exchange->rejected || exchange->conn == NULL;
}

static uint8_t send_bytes(MsExchange *exchange, MsSpan data, MsString *err) {
  const uint8_t status = ms_serve_send(exchange->conn, data, exchange->deadline, err);
  if (status != MS_STATUS_OK) {
    exchange->close_conn = true;
  }
  return status;
}

void ms_exchange_close(MsExchange *exchange) {
  exchange->closed = true;
  if (exchange->websocket != NULL) {
    ms_ws_session_close(exchange->websocket);
  }
}

/* ---- the request body ---- */

/* Hands out up to `want` decoded bytes; false when none are buffered. */
static bool take_decoded(MsExchange *exchange, size_t max, MsBytes *out, uint8_t *status) {
  const size_t avail = exchange->decoded.len - exchange->decoded_pos;
  if (avail == 0) {
    return false;
  }
  const size_t room = exchange->remaining_read == SIZE_MAX ? SIZE_MAX : exchange->remaining_read + 1;
  const size_t n = avail < max ? (avail < room ? avail : room) : (max < room ? max : room);
  if (n > exchange->remaining_read) {
    exchange->body_over_limit = true;
    *status = MS_STATUS_LIMIT_EXCEEDED;
    return true;
  }
  *out = ms_bytes_from_span(ms_span_of(exchange->decoded.ptr + exchange->decoded_pos, n));
  exchange->decoded_pos += n;
  if (exchange->decoded_pos == exchange->decoded.len) {
    exchange->decoded.len = 0;
    exchange->decoded_pos = 0;
  }
  if (exchange->remaining_read != SIZE_MAX) {
    exchange->remaining_read -= n;
  }
  *status = MS_STATUS_OK;
  return true;
}

/* Decodes what the connection already holds; false when it made no progress. */
static bool decode_buffered(MsExchange *exchange, uint8_t *status, MsString *err) {
  MsServeConn *conn = exchange->conn;
  const MsSpan input = ms_serve_unread(conn);
  if (input.len == 0) {
    return false;
  }
  size_t used = 0;
  MsH1Progress progress;
  const char *error = NULL;
  if (!ms_h1_body_feed(&exchange->body, input, &exchange->decoded, &used, &progress, &error)) {
    exchange->body_malformed = true;
    set_text(err, error);
    *status = MS_STATUS_FAILED;
    return true;
  }
  ms_serve_consume(conn, used);
  return exchange->decoded.len > exchange->decoded_pos || ms_h1_body_is_done(&exchange->body);
}

uint8_t ms_exchange_read(MsExchange *exchange, bool has_max, int64_t max, MsBytes *out, MsString *err) {
  if (has_max && max <= 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (is_closed(exchange)) {
    return MS_STATUS_CLOSED;
  }
  const size_t want = !has_max || max > CHUNK ? CHUNK : (size_t)max;
  if (exchange->h2 != NULL) {
    return ms_h2x_read(exchange, want, out, err);
  }
  if (exchange->expect_continue) {
    exchange->expect_continue = false;
    if (!ms_h1_body_is_done(&exchange->body)) {
      const uint8_t sent = send_bytes(exchange, ms_span_of_text("HTTP/1.1 100 Continue\r\n\r\n"), err);
      if (sent != MS_STATUS_OK) {
        return sent;
      }
    }
  }
  for (;;) {
    uint8_t status = MS_STATUS_OK;
    if (take_decoded(exchange, want, out, &status)) {
      return status;
    }
    if (ms_h1_body_is_done(&exchange->body)) {
      return MS_STATUS_NONE;
    }
    if (decode_buffered(exchange, &status, err)) {
      if (status != MS_STATUS_OK) {
        return status;
      }
      continue;
    }
    status = ms_serve_fill(exchange->conn, exchange->deadline, err);
    if (status == MS_STATUS_NONE) {
      if (ms_h1_body_finish_on_eof(&exchange->body)) {
        return MS_STATUS_NONE;
      }
      exchange->body_malformed = true;
      set_text(err, "unexpected EOF");
      return MS_STATUS_FAILED;
    }
    if (status != MS_STATUS_OK) {
      return status;
    }
  }
}

/* ---- the response ---- */

static bool reserved_name(MsSpan name) {
  return ms_ascii_equal_fold(name, ms_span_of_text("Content-Length")) ||
         ms_ascii_equal_fold(name, ms_span_of_text("Transfer-Encoding")) ||
         ms_ascii_equal_fold(name, ms_span_of_text("Connection"));
}

/* Checks handler headers against the rules of send_headers. */
static uint8_t check_headers(const MsHeaders *headers, size_t limit) {
  size_t bytes = 0;
  for (size_t g = 0; g < ms_headers_group_count(headers); g++) {
    const MsSpan name = ms_headers_group_name(headers, g);
    if (!ms_header_valid_name(name) || reserved_name(name)) {
      return MS_STATUS_INVALID_INPUT;
    }
    for (size_t i = 0; i < ms_headers_group_size(headers, g); i++) {
      const MsSpan value = ms_headers_group_value(headers, g, i);
      bytes += name.len + value.len + 4;
      if (bytes > limit) {
        return MS_STATUS_LIMIT_EXCEEDED;
      }
      if (!ms_header_valid_value(value)) {
        return MS_STATUS_INVALID_INPUT;
      }
    }
  }
  return MS_STATUS_OK;
}

uint8_t ms_exchange_send_headers(MsExchange *exchange, int64_t status, const MsHeaders *headers) {
  if (is_closed(exchange)) {
    return MS_STATUS_CLOSED;
  }
  if (exchange->sent || status < 200 || status > 599) {
    return MS_STATUS_INVALID_INPUT;
  }
  const uint8_t checked = check_headers(headers, exchange->limits->header);
  if (checked != MS_STATUS_OK) {
    return checked;
  }
  exchange->sent = true;
  exchange->status = (uint16_t)status;
  ms_headers_free(exchange->staged);
  exchange->staged = ms_headers_copy(headers);
  return MS_STATUS_OK;
}

enum { STAGED_INLINE = 16 }; /* handler headers sorted without an allocation up to this many names */

typedef struct Named {
  MsString name;
  size_t group;
} Named;

static int by_name(const void *a, const void *b) {
  const MsSpan x = ms_string_span(&((const Named *)a)->name);
  const MsSpan y = ms_string_span(&((const Named *)b)->name);
  const size_t n = x.len < y.len ? x.len : y.len;
  const int c = n == 0 ? 0 : __builtin_memcmp(x.ptr, y.ptr, n);
  return c != 0 ? c : (x.len > y.len) - (x.len < y.len);
}

/* The handler's fields with canonical names in sorted order; reports whether a Content-Type and a Date came.
 */
static void append_staged(MsStrBuild *out, const MsHeaders *headers, bool *has_type, bool *has_date) {
  const size_t count = ms_headers_group_count(headers);
  if (count == 0) {
    return;
  }
  Named names_inline[STAGED_INLINE] = {0};
  Named *names = count <= STAGED_INLINE ? names_inline : ms_alloc_zeroed(count * sizeof *names);
  for (size_t g = 0; g < count; g++) {
    MsStrBuild canonical = ms_strbuild_new();
    ms_header_canonical(ms_headers_group_name(headers, g), &canonical);
    names[g].name = ms_strbuild_finish(&canonical);
    names[g].group = g;
  }
  qsort(names, count, sizeof *names, by_name);
  for (size_t k = 0; k < count; k++) {
    const MsSpan name = ms_string_span(&names[k].name);
    *has_type = *has_type || ms_span_is_text(name, "Content-Type");
    *has_date = *has_date || ms_span_is_text(name, "Date");
    for (size_t i = 0; i < ms_headers_group_size(headers, names[k].group); i++) {
      ms_h1_header_line(out, name, ms_headers_group_value(headers, names[k].group, i));
    }
    ms_string_release(&names[k].name);
  }
  if (names != names_inline) {
    ms_free(names);
  }
}

/* Builds the head with the first body bytes; `length` is the whole body's size, or -1 to stream it chunked.
 */
static uint8_t write_head(MsExchange *exchange, MsSpan first, int64_t length, MsString *err) {
  MsStrBuild *const head = &exchange->conn->head;
  ms_strbuild_clear(head);
  MsStrBuild out = *head;
  bool has_type = false;
  bool has_date = false;
  ms_h1_status_line(&out, exchange->status);
  append_staged(&out, exchange->staged, &has_type, &has_date);
  if (!has_date) {
    ms_serve_date_line(&out);
  }
  const bool allowed = ms_serve_body_allowed(exchange->status);
  if (length >= 0 && allowed && !exchange->is_head) {
    ms_h1_header_number(&out, ms_span_of_text("Content-Length"), (uint64_t)length);
  }
  if (allowed && !has_type && first.len > 0) {
    ms_h1_header_line(&out, ms_span_of_text("Content-Type"),
                      ms_span_of_text(ms_http_detect_content_type(first)));
  }
  if (exchange->close_conn) {
    ms_h1_header_line(&out, ms_span_of_text("Connection"), ms_span_of_text("close"));
  }
  exchange->chunked = length < 0 && allowed && !exchange->is_head && exchange->minor == 1;
  if (exchange->chunked) {
    ms_h1_header_line(&out, ms_span_of_text("Transfer-Encoding"), ms_span_of_text("chunked"));
  }
  ms_strbuild_append_text(&out, "\r\n");
  exchange->head_written = true;
  if (exchange->chunked) {
    ms_h1_chunk(&out, first);
  } else {
    ms_strbuild_append(&out, first);
  }
  const uint8_t status = send_bytes(exchange, ms_strbuild_span(&out), err);
  *head = out; /* the buffer may have grown: the connection keeps it for the next response */
  return status;
}

uint8_t ms_exchange_write(MsExchange *exchange, MsSpan data, MsString *err) {
  if (is_closed(exchange)) {
    return MS_STATUS_CLOSED;
  }
  if (!exchange->sent || exchange->response_complete) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (data.len > exchange->remaining_write) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  if (!ms_serve_body_allowed(exchange->status)) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (exchange->is_head) {
    return MS_STATUS_OK; /* a HEAD answer has no body: the bytes are dropped */
  }
  uint8_t status = MS_STATUS_OK;
  if (exchange->h2 != NULL) {
    status = ms_h2x_write(exchange, data, -1, err);
  } else if (!exchange->head_written) {
    status = write_head(exchange, data, -1, err);
  } else if (exchange->chunked) {
    MsStrBuild out = ms_strbuild_new();
    ms_h1_chunk(&out, data);
    status = send_bytes(exchange, ms_strbuild_span(&out), err);
    ms_strbuild_free(&out);
  } else {
    status = send_bytes(exchange, data, err);
  }
  if (status == MS_STATUS_OK && exchange->remaining_write != SIZE_MAX) {
    exchange->remaining_write -= data.len;
  }
  return status;
}

/* A head-only answer (HEAD, or a status without a body) still names the length and type the body would have.
 */
static void stage_head_only(MsExchange *exchange, MsSpan body) {
  exchange->response_complete = true;
  if (!exchange->is_head || !ms_serve_body_allowed(exchange->status) || body.len == 0) {
    return;
  }
  MsStrBuild length = ms_strbuild_new();
  ms_strbuild_append_u64(&length, body.len);
  ms_headers_set(exchange->staged, ms_span_of_text("Content-Length"), ms_strbuild_span(&length));
  ms_strbuild_free(&length);
  MsSpan type;
  if (!ms_headers_first(exchange->staged, ms_span_of_text("Content-Type"), &type)) {
    ms_headers_set(exchange->staged, ms_span_of_text("Content-Type"),
                   ms_span_of_text(ms_http_detect_content_type(body)));
  }
}

uint8_t ms_exchange_send(MsExchange *exchange, int64_t status, const MsHeaders *headers, MsSpan body,
                         MsString *err) {
  const uint8_t checked = ms_exchange_send_headers(exchange, status, headers);
  if (checked != MS_STATUS_OK) {
    return checked;
  }
  if (body.len > exchange->remaining_write) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  if (body.len == 0 || exchange->is_head || !ms_serve_body_allowed(exchange->status)) {
    stage_head_only(exchange, body);
    return MS_STATUS_OK;
  }
  const uint8_t sent = exchange->h2 != NULL ? ms_h2x_write(exchange, body, (int64_t)body.len, err)
                                            : write_head(exchange, body, (int64_t)body.len, err);
  if (sent != MS_STATUS_OK) {
    return sent;
  }
  if (exchange->remaining_write != SIZE_MAX) {
    exchange->remaining_write -= body.len;
  }
  exchange->response_complete = true;
  return MS_STATUS_OK;
}

/* ---- the WebSocket upgrade ---- */

/* Answers a refused upgrade and marks the exchange. */
static void reject_upgrade(MsExchange *exchange, const MsWsRejected *rejected) {
  MsBytes response = {0};
  ms_ws_rejected_response(rejected, ms_clock_realtime().seconds, false, &response);
  MsString ignored = ms_string_empty();
  (void)send_bytes(exchange, ms_bytes_span(&response), &ignored);
  ms_string_release(&ignored);
  ms_bytes_free(&response);
  exchange->rejected = true;
  exchange->close_conn = true;
}

uint8_t ms_exchange_upgrade(MsExchange *exchange, const MsSpan *origins, size_t origin_count,
                            const MsSpan *subprotocols, size_t subprotocol_count, bool has_max, int64_t max,
                            MsWsSession **out, MsString *err) {
  if ((has_max && max <= 0) || exchange->closed || exchange->sent || exchange->upgraded ||
      exchange->rejected || exchange->conn == NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  for (size_t i = 0; i < subprotocol_count; i++) {
    if (!ms_header_valid_name(subprotocols[i])) {
      return MS_STATUS_INVALID_INPUT;
    }
  }
  MsSpan host = ms_span_of(NULL, 0);
  (void)ms_headers_first(exchange->headers, ms_span_of_text("Host"), &host);
  const MsWsRequest request = {.method = ms_string_span(&exchange->method),
                               .host = host,
                               .tls = exchange->tls,
                               .fields = exchange->headers};
  const MsWsServerOptions options = {.allowed_origins = origins,
                                     .allowed_origin_count = origin_count,
                                     .subprotocols = subprotocols,
                                     .subprotocol_count = subprotocol_count,
                                     .compression = false};
  MsWsAccepted accepted;
  MsWsRejected rejected;
  const bool http11 = exchange->minor == 1;
  if (!http11) {
    rejected = (MsWsRejected){400, "websocket: upgrade needs HTTP/1.1"};
  }
  if (!http11 || !ms_ws_accept(&request, &options, &accepted, &rejected)) {
    reject_upgrade(exchange, &rejected);
    set_text(err, rejected.message);
    return MS_STATUS_FAILED;
  }
  const uint8_t sent = send_bytes(exchange, ms_bytes_span(&accepted.response), err);
  if (sent != MS_STATUS_OK) {
    ms_ws_accepted_release(&accepted);
    return sent;
  }
  MsWsConfig config = {.client = false,
                       .compress = accepted.compress,
                       .has_limit = has_max,
                       .max_message_bytes = (uint64_t)max,
                       .subprotocol = accepted.subprotocol};
  accepted.subprotocol = ms_string_empty();
  MsServeConn *conn = exchange->conn;
  *out = ms_ws_session_new(&conn->io, &config, ms_serve_unread(conn));
  ms_serve_consume(conn, ms_serve_unread(conn).len);
  conn->io = (MsWsTransport){0}; /* the session owns the stream now */
  ms_ws_accepted_release(&accepted);
  exchange->deadline = MS_NO_DEADLINE; /* a WebSocket outlives the request timeout */
  ms_task_limit_current_at(MS_NO_DEADLINE);
  exchange->upgraded = true;
  exchange->websocket = ms_ws_session_retain(*out);
  return MS_STATUS_OK;
}

/* ---- completing the request ---- */

/* Skips what is left of the request body that is already buffered; false when more would have to be read. */
static bool drain_request_body(MsExchange *exchange) {
  MsBytes sink = {0};
  size_t total = 0;
  while (!ms_h1_body_is_done(&exchange->body) && total < DRAIN_LIMIT) {
    const MsSpan input = ms_serve_unread(exchange->conn);
    if (input.len == 0) {
      break;
    }
    size_t used = 0;
    MsH1Progress progress;
    const char *error = NULL;
    sink.len = 0;
    if (!ms_h1_body_feed(&exchange->body, input, &sink, &used, &progress, &error)) {
      break;
    }
    ms_serve_consume(exchange->conn, used);
    total += used;
  }
  ms_bytes_free(&sink);
  return ms_h1_body_is_done(&exchange->body);
}

/* The answer a failed handler leaves behind when no head went out; false when the connection must close. */
static bool failure_answer(MsExchange *exchange, int failure, bool late, MsStrBuild *out) {
  const bool timed = late || failure == 3;
  if (exchange->body_malformed && !timed) {
    ms_serve_error_bytes(out, 400, "malformed request body", true);
    return false;
  }
  if (exchange->body_over_limit && !timed) {
    ms_serve_error_bytes(out, 413, "invalid or oversized request body", false);
    return true;
  }
  ms_serve_error_bytes(out, timed ? 504 : 500, "request failed", false);
  return true;
}

bool ms_exchange_finish(MsExchange *exchange, int failure) {
  MsServeConn *conn = exchange->conn;
  const bool late = exchange->deadline != MS_NO_DEADLINE && ms_sched_now() > exchange->deadline;
  const bool failed = failure != 0 || late;
  if (exchange->h2 != NULL) {
    exchange->closed = true;
    ms_h2x_finish(exchange, failure, late);
    return true;
  }
  exchange->closed = true;
  if (exchange->upgraded) {
    ms_ws_session_close(exchange->websocket); /* the WebSocket lives as long as the handler */
    exchange->conn = NULL;
    return false;
  }
  MsStrBuild out = ms_strbuild_new();
  bool close = exchange->close_conn || conn->worker->closing;
  if (exchange->rejected) {
    close = true;
  } else if (failed && exchange->head_written) {
    close = true; /* part of the response is out: abort the connection */
    ms_strbuild_free(&out);
    exchange->conn = NULL;
    return false;
  } else if (failed) {
    close = !failure_answer(exchange, failure, late, &out) || close;
  } else if (!exchange->sent) {
    ms_h1_status_line(&out, 204);
    ms_serve_date_line(&out);
    if (close) {
      ms_h1_header_line(&out, ms_span_of_text("Connection"), ms_span_of_text("close"));
    }
    ms_strbuild_append_text(&out, "\r\n");
  }
  MsString err = ms_string_empty();
  if (!failed && exchange->sent && !exchange->head_written && !exchange->rejected) {
    close = write_head(exchange, ms_span_of(NULL, 0), 0, &err) != MS_STATUS_OK || close;
  } else if (!failed && exchange->chunked) {
    ms_strbuild_append_text(&out, MS_H1_LAST_CHUNK);
  }
  close = close || !drain_request_body(exchange);
  const bool written = ms_serve_send(conn, ms_strbuild_span(&out), MS_NO_DEADLINE, &err) == MS_STATUS_OK;
  ms_string_release(&err);
  ms_strbuild_free(&out);
  exchange->conn = NULL;
  return written && !close;
}

/* ---- HTTP/2 response heads ---- */

static void add_field(MsList *list, MsSpan name, MsSpan value) {
  const MsH2Field field = {.name = ms_bytes_from_span(name), .value = ms_bytes_from_span(value)};
  ms_list_push(list, sizeof field, &field);
}

static void add_lowered(MsList *list, MsSpan name, MsSpan value) {
  MsStrBuild lower = ms_strbuild_new();
  for (size_t i = 0; i < name.len; i++) {
    ms_strbuild_append_byte(&lower, ms_ascii_to_lower(name.ptr[i]));
  }
  add_field(list, ms_strbuild_span(&lower), value);
  ms_strbuild_free(&lower);
}

/* Appends the handler's fields, names lower-cased and sorted; reports whether a type and a date came. */
static void staged_fields(MsList *list, const MsHeaders *headers, bool *has_type, bool *has_date) {
  const size_t count = ms_headers_group_count(headers);
  Named *names = ms_alloc_zeroed((count + 1) * sizeof *names);
  for (size_t g = 0; g < count; g++) {
    MsStrBuild canonical = ms_strbuild_new();
    ms_header_canonical(ms_headers_group_name(headers, g), &canonical);
    names[g].name = ms_strbuild_finish(&canonical);
    names[g].group = g;
  }
  qsort(names, count, sizeof *names, by_name);
  for (size_t k = 0; k < count; k++) {
    const MsSpan name = ms_string_span(&names[k].name);
    *has_type = *has_type || ms_span_is_text(name, "Content-Type");
    *has_date = *has_date || ms_span_is_text(name, "Date");
    for (size_t i = 0; i < ms_headers_group_size(headers, names[k].group); i++) {
      add_lowered(list, name, ms_headers_group_value(headers, names[k].group, i));
    }
    ms_string_release(&names[k].name);
  }
  ms_free(names);
}

size_t ms_exchange_h2_fields(MsExchange *exchange, MsSpan first, int64_t length, MsH2Field **out) {
  MsList list = {0};
  MsStrBuild code = ms_strbuild_new();
  ms_strbuild_append_u64(&code, exchange->status);
  add_field(&list, ms_span_of_text(":status"), ms_strbuild_span(&code));
  ms_strbuild_free(&code);
  bool has_type = false;
  bool has_date = false;
  staged_fields(&list, exchange->staged, &has_type, &has_date);
  if (!has_date) {
    MsStrBuild date = ms_strbuild_new();
    ms_h1_http_date(&date, ms_clock_realtime().seconds);
    add_field(&list, ms_span_of_text("date"), ms_strbuild_span(&date));
    ms_strbuild_free(&date);
  }
  const bool allowed = ms_serve_body_allowed(exchange->status);
  if (length >= 0 && allowed && !exchange->is_head) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_u64(&text, (uint64_t)length);
    add_field(&list, ms_span_of_text("content-length"), ms_strbuild_span(&text));
    ms_strbuild_free(&text);
  }
  if (allowed && !has_type && first.len > 0) {
    add_field(&list, ms_span_of_text("content-type"), ms_span_of_text(ms_http_detect_content_type(first)));
  }
  *out = (MsH2Field *)(void *)list.ptr;
  return list.len;
}

void ms_h2_fields_release(MsH2Field *fields, size_t count) {
  for (size_t i = 0; i < count; i++) {
    ms_bytes_free(&fields[i].name);
    ms_bytes_free(&fields[i].value);
  }
  ms_free(fields);
}
