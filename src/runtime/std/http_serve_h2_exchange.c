/* runtime/std/http_serve_h2_exchange.c: an exchange over an HTTP/2 stream: building it from a request head,
 * the body reads, the response writes and the end of the stream (http_serve_internal.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "base/alloc.h"
#include "base/chars.h"
#include "runtime/std/http_serve_internal.h"

/* ---- the request head ---- */

typedef struct Pseudo {
  MsSpan method;
  MsSpan scheme;
  MsSpan authority;
  MsSpan path;
} Pseudo;

static bool is_pseudo(MsSpan name, const char *text, MsSpan value, MsSpan *slot) {
  if (!ms_span_is_text(name, text)) {
    return false;
  }
  *slot = value;
  return true;
}

/* Splits the pseudo-fields from the rest; the rest become received fields with canonical names (owned in
 * `names`). */
static bool split_fields(const MsList *fields, Pseudo *pseudo, MsHeaderField **rest, MsString **names,
                         size_t *count) {
  const MsH2Field *items = (const MsH2Field *)(const void *)fields->ptr;
  *rest = ms_alloc_zeroed((fields->len + 1) * sizeof **rest);
  *names = ms_alloc_zeroed((fields->len + 1) * sizeof **names);
  *count = 0;
  for (size_t i = 0; i < fields->len; i++) {
    const MsSpan name = ms_bytes_span(&items[i].name);
    const MsSpan value = ms_bytes_span(&items[i].value);
    if (name.len > 0 && name.ptr[0] == ':') {
      if (!(is_pseudo(name, ":method", value, &pseudo->method) ||
            is_pseudo(name, ":scheme", value, &pseudo->scheme) ||
            is_pseudo(name, ":authority", value, &pseudo->authority) ||
            is_pseudo(name, ":path", value, &pseudo->path))) {
        return false;
      }
      continue;
    }
    MsStrBuild canonical = ms_strbuild_new();
    ms_header_canonical(name, &canonical);
    (*names)[*count] = ms_strbuild_finish(&canonical);
    ms_strbuild_free(&canonical);
    (*rest)[*count] = (MsHeaderField){.name = ms_string_span(&(*names)[*count]), .value = value};
    (*count)++;
  }
  return true;
}

static void release_names(MsString *names, MsHeaderField *rest, size_t count) {
  for (size_t i = 0; i < count; i++) {
    ms_string_release(&names[i]);
  }
  ms_free(names);
  ms_free(rest);
}

/* Why the head is refused, or NULL; `target` is filled for a head that passes. */
static const char *check_h2_head(const Pseudo *pseudo, const MsHeaders *headers, const MsServeLimits *limits,
                                 MsHttpTarget *target, uint16_t *status) {
  *status = 400;
  if (pseudo->method.len == 0 || pseudo->path.len == 0 || pseudo->scheme.len == 0) {
    return "missing pseudo-header";
  }
  if (pseudo->authority.len > 0 && !ms_http_valid_authority(pseudo->authority)) {
    return "invalid Host header";
  }
  const MsH1Scan scan = ms_h1_scan(headers);
  MsH1Framing framing = {0};
  MsH1Bad bad = {0};
  if (!ms_h1_request_framing(1, headers, &scan, &framing, &bad)) {
    *status = bad.status;
    return bad.reason;
  }
  const char *reason = NULL;
  if (!ms_http_target_parse(pseudo->path, target, &reason)) {
    return reason;
  }
  if (!scan.text) {
    ms_http_target_release(target);
    return "invalid UTF-8 request";
  }
  if (framing.kind == MS_H1_LENGTH && framing.length > limits->body) {
    ms_http_target_release(target);
    *status = 413;
    return "invalid or oversized request body";
  }
  return NULL;
}

MsExchange *ms_exchange_new_h2(MsServeConn *conn, MsH2Stream *stream, const MsList *fields, bool end_stream,
                               int64_t deadline, uint16_t *status, const char **reason) {
  Pseudo pseudo = {0};
  MsHeaderField *rest = NULL;
  MsString *names = NULL;
  size_t count = 0;
  if (!split_fields(fields, &pseudo, &rest, &names, &count)) {
    release_names(names, rest, count);
    *status = 400;
    *reason = "invalid pseudo-header";
    return NULL;
  }
  MsHeaders *headers = ms_headers_from_received(rest, count);
  release_names(names, rest, count);
  if (pseudo.authority.len > 0) {
    ms_headers_set(headers, ms_span_of_text("Host"), pseudo.authority);
  }
  MsHttpTarget target = {0};
  *reason = check_h2_head(&pseudo, headers, &conn->worker->shared->limits, &target, status);
  if (*reason != NULL) {
    ms_headers_free(headers);
    return NULL;
  }
  MsExchange *exchange = ms_exchange_alloc(conn, deadline);
  exchange->method = ms_string_from_span(pseudo.method);
  exchange->path = target.path;
  exchange->query = target.query;
  ms_string_release(&target.host);
  exchange->protocol = "HTTP/2.0";
  exchange->headers = headers;
  exchange->body = ms_h1_body_new((MsH1Framing){.kind = MS_H1_NO_BODY});
  exchange->minor = 1;
  exchange->is_head = ms_span_is_text(ms_string_span(&exchange->method), "HEAD");
  exchange->h2 = stream;
  stream->end_in = end_stream;
  return exchange;
}

/* ---- waiting on the stream ---- */

/* 0 woken, 1 timed out, 2 cancelled. */
static int wait_stream(MsH2Stream *stream, int64_t deadline) {
  uint64_t value = 0;
  uint32_t result = 0;
  (void)ms_token_park(stream->token, ms_serve_left(deadline), &value, &result);
  if ((result & MS_WAIT_CANCELLED) != 0) {
    return 2;
  }
  return (result & MS_WAIT_TIMEOUT) != 0 ? 1 : 0;
}

static bool stream_gone(const MsH2Stream *stream) {
  return stream->reset || stream->owner->dead;
}

/* ---- reading the body ---- */

uint8_t ms_h2x_read(MsExchange *exchange, size_t want, MsBytes *out, MsString *err) {
  (void)err;
  MsH2Stream *stream = exchange->h2;
  for (;;) {
    const size_t avail = stream->inbox.len - stream->pos;
    if (avail > 0) {
      const size_t room = exchange->remaining_read == SIZE_MAX ? SIZE_MAX : exchange->remaining_read + 1;
      size_t n = avail < want ? avail : want;
      n = n < room ? n : room;
      if (n > exchange->remaining_read) {
        exchange->body_over_limit = true;
        return MS_STATUS_LIMIT_EXCEEDED;
      }
      *out = ms_bytes_from_span(ms_span_of(stream->inbox.ptr + stream->pos, n));
      stream->pos += n;
      if (stream->pos == stream->inbox.len) {
        stream->inbox.len = 0;
        stream->pos = 0;
      }
      if (exchange->remaining_read != SIZE_MAX) {
        exchange->remaining_read -= n;
      }
      ms_h2_release(stream->owner->h2, stream->id, n);
      ms_h2_flush(stream->owner);
      return MS_STATUS_OK;
    }
    if (stream->end_in) {
      return MS_STATUS_NONE;
    }
    if (stream_gone(stream)) {
      return MS_STATUS_CLOSED;
    }
    const int woke = wait_stream(stream, exchange->deadline);
    if (woke != 0) {
      return woke == 1 ? MS_STATUS_TIMED_OUT : MS_STATUS_CLOSED;
    }
  }
}

/* ---- writing the response ---- */

/* Gives `data` to the stream, waiting for the peer's window; `end` ends the stream with the last byte. */
static uint8_t send_all(MsExchange *exchange, MsSpan data, bool end) {
  MsH2Stream *stream = exchange->h2;
  for (;;) {
    if (stream_gone(stream)) {
      return MS_STATUS_CLOSED;
    }
    const size_t taken = ms_h2_send_data(stream->owner->h2, stream->id, data, end);
    data = ms_span_of(data.ptr + taken, data.len - taken);
    ms_h2_flush(stream->owner);
    if (data.len == 0) {
      return MS_STATUS_OK;
    }
    const int woke = wait_stream(stream, exchange->deadline);
    if (woke != 0) {
      return woke == 1 ? MS_STATUS_TIMED_OUT : MS_STATUS_CLOSED;
    }
  }
}

static uint8_t send_head(MsExchange *exchange, MsSpan first, int64_t length, bool end) {
  MsH2Field *fields = NULL;
  const size_t count = ms_exchange_h2_fields(exchange, first, length, &fields);
  const bool sent =
      ms_h2_send_response_headers(exchange->h2->owner->h2, exchange->h2->id, fields, count, end);
  ms_h2_fields_release(fields, count);
  exchange->head_written = true;
  ms_h2_flush(exchange->h2->owner);
  return sent ? MS_STATUS_OK : MS_STATUS_FAILED;
}

uint8_t ms_h2x_write(MsExchange *exchange, MsSpan data, int64_t content_length, MsString *err) {
  if (stream_gone(exchange->h2)) {
    return MS_STATUS_CLOSED;
  }
  if (!exchange->head_written && send_head(exchange, data, content_length, false) != MS_STATUS_OK) {
    ms_string_release(err);
    *err = ms_string_from_span(ms_span_of_text("response head refused"));
    return MS_STATUS_FAILED;
  }
  return send_all(exchange, data, false);
}

/* ---- the end of the stream ---- */

/* The text answer of a failed request whose head was not sent. */
static void send_failure(MsExchange *exchange, int failure, bool late) {
  const bool timed = late || failure == 3;
  const char *text = "request failed";
  exchange->status = timed ? 504 : 500;
  if (exchange->body_malformed && !timed) {
    exchange->status = 400;
    text = "malformed request body";
  } else if (exchange->body_over_limit && !timed) {
    exchange->status = 413;
    text = "invalid or oversized request body";
  }
  ms_headers_free(exchange->staged);
  exchange->staged = ms_headers_new();
  ms_headers_set(exchange->staged, ms_span_of_text("Content-Type"),
                 ms_span_of_text("text/plain; charset=utf-8"));
  ms_headers_set(exchange->staged, ms_span_of_text("X-Content-Type-Options"), ms_span_of_text("nosniff"));
  MsStrBuild body = ms_strbuild_new();
  ms_strbuild_append_text(&body, text);
  ms_strbuild_append_byte(&body, '\n');
  const MsSpan span = ms_strbuild_span(&body);
  if (send_head(exchange, span, (int64_t)span.len, false) == MS_STATUS_OK) {
    (void)send_all(exchange, span, true);
  }
  ms_strbuild_free(&body);
}

void ms_h2x_finish(MsExchange *exchange, int failure, bool late) {
  MsH2Stream *stream = exchange->h2;
  const bool failed = failure != 0 || late;
  if (stream_gone(stream)) {
    return;
  }
  if (failed && exchange->head_written) {
    ms_h2_send_rst(stream->owner->h2, stream->id, failure == 2 ? MS_H2_INTERNAL_ERROR : MS_H2_CANCEL);
  } else if (failed) {
    send_failure(exchange, failure, late);
  } else if (!exchange->sent) {
    exchange->status = 204;
    (void)send_head(exchange, ms_span_of(NULL, 0), -1, true);
  } else if (!exchange->head_written) {
    (void)send_head(exchange, ms_span_of(NULL, 0), 0, true);
  } else {
    (void)send_all(exchange, ms_span_of(NULL, 0), true);
  }
  ms_h2_flush(stream->owner);
}
