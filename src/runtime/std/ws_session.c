/* runtime/std/ws_session.c: a WebSocket session: its record, sending, pinging and closing. */
#include "base/alloc.h"
#include "base/chars.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/std/ws_session_internal.h"

const char ms_ws_truncated_text[] = "connection closed before the exchange completed";

MsWsFault ms_ws_fault(uint8_t status) {
  return (MsWsFault){.status = status, .text = ms_string_empty()};
}

MsWsFault ms_ws_fault_text(const char *text) {
  return (MsWsFault){.status = MS_STATUS_FAILED, .text = ms_string_from_span(ms_span_of_text(text))};
}

MsWsFault ms_ws_fault_string(MsStrBuild *text) {
  return (MsWsFault){.status = MS_STATUS_FAILED, .text = ms_strbuild_finish(text)};
}

void ms_ws_fault_release(MsWsFault *fault) {
  ms_string_release(&fault->text);
  *fault = ms_ws_fault(MS_STATUS_OK);
}

uint8_t ms_ws_fault_take(MsWsFault *fault, MsString *err) {
  const uint8_t status = fault->status;
  *err = fault->text;
  *fault = ms_ws_fault(MS_STATUS_OK);
  return status;
}

MsWsSession *ms_ws_session_new(const MsWsTransport *transport, MsWsConfig *config, MsSpan leftover) {
  MsWsSession *session = ms_alloc_zeroed(sizeof *session);
  atomic_init(&session->handles, 1);
  session->io = *transport;
  session->config = *config;
  config->subprotocol = ms_string_empty();
  session->lock = ms_http_mutex_new();
  session->write_fault = ms_ws_fault(MS_STATUS_OK);
  session->decoder = ms_ws_decoder_new(!config->client, config->compress,
                                       config->has_limit ? config->max_message_bytes : UINT64_MAX);
  ms_ws_decoder_push(&session->decoder, leftover);
  atomic_init(&session->reading, false);
  atomic_init(&session->closed, false);
  atomic_init(&session->failed, false);
  return session;
}

MsWsSession *ms_ws_session_retain(MsWsSession *session) {
  atomic_fetch_add(&session->handles, 1);
  return session;
}

void ms_ws_session_release(MsWsSession *session) {
  if (atomic_fetch_sub(&session->handles, 1) != 1) {
    return;
  }
  if (session->io.release != NULL) {
    session->io.release(session->io.context);
  }
  ms_ws_decoder_free(&session->decoder);
  ms_bytes_list_free(&session->queue);
  ms_ws_fault_release(&session->write_fault);
  ms_string_release(&session->config.subprotocol);
  ms_http_mutex_free(session->lock);
  ms_free(session);
}

bool ms_ws_session_is_last(const MsWsSession *session) {
  return atomic_load(&((MsWsSession *)(uintptr_t)session)->handles) == 1;
}

const MsString *ms_ws_session_subprotocol(const MsWsSession *session) {
  return &session->config.subprotocol;
}

bool ms_ws_session_ended(MsWsSession *session) {
  return atomic_load(&session->closed) || atomic_load(&session->failed) ||
         session->io.is_closed(session->io.context);
}

void ms_ws_session_fail(MsWsSession *session) {
  atomic_store(&session->failed, true);
  session->io.close(session->io.context);
}

/* ---- writing ---- */

/* A transport failure as a session failure; a local timeout is `on_timeout` (NULL: TIMED_OUT). */
static MsWsFault map_write(uint8_t status, MsString *text, const char *on_timeout) {
  switch (status) {
  case MS_STATUS_CLOSED:
  case MS_STATUS_INVALID_INPUT:
    return ms_ws_fault(status);
  case MS_STATUS_TIMED_OUT:
    return on_timeout != NULL ? ms_ws_fault_text(on_timeout) : ms_ws_fault(MS_STATUS_TIMED_OUT);
  case MS_STATUS_FAILED: {
    MsWsFault fault = {.status = MS_STATUS_FAILED, .text = *text};
    *text = ms_string_empty();
    return fault;
  }
  case MS_STATUS_UNAVAILABLE:
    return ms_ws_fault_text("operation unavailable");
  case MS_STATUS_INVALID_DATA:
    return ms_ws_fault_text("invalid data");
  default:
    return ms_ws_fault_text("limit exceeded");
  }
}

static void remember(MsWsSession *session, const MsWsFault *fault) {
  ms_http_mutex_lock(session->lock);
  ms_ws_fault_release(&session->write_fault);
  session->write_fault =
      (MsWsFault){.status = fault->status, .text = ms_string_from_span(ms_string_span(&fault->text))};
  const MsBytes *queued = (const MsBytes *)(const void *)session->queue.ptr;
  for (size_t i = 0; i < session->queue.len; i++) {
    MsBytes drop = queued[i];
    ms_bytes_free(&drop);
  }
  session->queue.len = 0;
  session->flushing = false;
  ms_http_mutex_unlock(session->lock);
}

/* The next queued frame, or false (ending the flush) when none is left. */
static bool next_queued(MsWsSession *session, MsBytes *bytes) {
  ms_http_mutex_lock(session->lock);
  const bool any = session->queue.len > 0;
  if (any) {
    *bytes = ((MsBytes *)(void *)session->queue.ptr)[0];
    __builtin_memmove(session->queue.ptr, session->queue.ptr + sizeof *bytes,
                      (session->queue.len - 1) * sizeof *bytes);
    session->queue.len--;
  } else {
    session->flushing = false;
  }
  ms_http_mutex_unlock(session->lock);
  return any;
}

/* Writes one frame or message: a failure is sticky; a call during a write only queues behind it. */
static MsWsFault ms_ws_session_write(MsWsSession *session, MsBytes bytes, int64_t timeout_ns,
                              const char *on_timeout) {
  ms_http_mutex_lock(session->lock);
  if (session->write_fault.status != MS_STATUS_OK) {
    MsWsFault copy = {.status = session->write_fault.status,
                      .text = ms_string_from_span(ms_string_span(&session->write_fault.text))};
    ms_http_mutex_unlock(session->lock);
    ms_bytes_free(&bytes);
    return copy;
  }
  ms_list_push(&session->queue, sizeof bytes, &bytes);
  const bool busy = session->flushing;
  session->flushing = true;
  ms_http_mutex_unlock(session->lock);
  if (busy) {
    return ms_ws_fault(MS_STATUS_OK);
  }
  MsBytes frame;
  while (next_queued(session, &frame)) {
    MsString text = ms_string_empty();
    const uint8_t status = session->io.write(session->io.context, ms_bytes_span(&frame), timeout_ns, &text);
    ms_bytes_free(&frame);
    if (status != MS_STATUS_OK) {
      MsWsFault fault = map_write(status, &text, on_timeout);
      ms_string_release(&text);
      remember(session, &fault);
      return fault;
    }
    ms_string_release(&text);
  }
  return ms_ws_fault(MS_STATUS_OK);
}

MsWsFault ms_ws_session_control(MsWsSession *session, uint8_t opcode, MsSpan payload, int64_t timeout_ns,
                                const char *on_timeout) {
  MsBytes frame = {0};
  if (!ms_ws_encode_control(&frame, opcode, payload, session->config.client)) {
    ms_bytes_free(&frame);
    return ms_ws_fault(MS_STATUS_INVALID_INPUT);
  }
  MsWsFault fault = ms_ws_session_write(session, frame, timeout_ns, on_timeout);
  if (fault.status == MS_STATUS_OK && opcode == MS_WS_OP_CLOSE) {
    MsWsFault sent = ms_ws_fault_text("websocket: close sent");
    ms_http_mutex_lock(session->lock);
    ms_ws_fault_release(&session->write_fault);
    session->write_fault = sent;
    ms_http_mutex_unlock(session->lock);
  }
  return fault;
}

void ms_ws_session_send_close(MsWsSession *session, uint16_t code, MsSpan reason, int64_t timeout_ns) {
  MsBytes payload = {0};
  ms_ws_format_close(code, reason, &payload);
  MsWsFault fault = ms_ws_session_control(session, MS_WS_OP_CLOSE, ms_bytes_span(&payload), timeout_ns, NULL);
  ms_bytes_free(&payload);
  ms_ws_fault_release(&fault);
}

/* ---- the calls ---- */

uint8_t ms_ws_session_send(MsWsSession *session, MsSpan data, bool text, int64_t timeout_ns, MsString *err) {
  *err = ms_string_empty();
  if (ms_ws_session_ended(session)) {
    return MS_STATUS_CLOSED;
  }
  if (session->config.has_limit && data.len > session->config.max_message_bytes) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  if (text && !ms_utf8_is_valid(data.ptr, data.len)) {
    return MS_STATUS_INVALID_DATA;
  }
  MsBytes wire = {0};
  if (!ms_ws_encode_message(&wire, text ? MS_WS_OP_TEXT : MS_WS_OP_BINARY, data, session->config.client,
                            session->config.compress, 0)) {
    ms_bytes_free(&wire);
    *err = ms_string_from_span(ms_span_of_text("no random bytes for the masking key"));
    return MS_STATUS_FAILED;
  }
  MsWsFault fault = ms_ws_session_write(session, wire, timeout_ns, NULL);
  return ms_ws_fault_take(&fault, err);
}

uint8_t ms_ws_session_ping(MsWsSession *session, MsSpan data, MsString *err) {
  *err = ms_string_empty();
  if (ms_ws_session_ended(session)) {
    return MS_STATUS_CLOSED;
  }
  MsWsFault fault =
      ms_ws_session_control(session, MS_WS_OP_PING, data, MS_WS_CONTROL_WRITE_NS, "i/o timeout");
  return ms_ws_fault_take(&fault, err);
}

/* Like close with a status code and a reason (cut to 123 bytes). */
static void ms_ws_session_close_with(MsWsSession *session, uint16_t code, MsSpan reason) {
  if (atomic_exchange(&session->closed, true)) {
    return;
  }
  if (!session->io.is_closed(session->io.context)) {
    size_t end = reason.len < MS_WS_MAX_CLOSE_REASON ? reason.len : MS_WS_MAX_CLOSE_REASON;
    while (end > 0 && end < reason.len && ms_utf8_is_continuation(reason.ptr[end])) {
      end--;
    }
    ms_ws_session_send_close(session, code, ms_span_of(reason.ptr, end), MS_WS_CLOSE_WRITE_NS);
  }
  session->io.close(session->io.context);
}

void ms_ws_session_close(MsWsSession *session) {
  ms_ws_session_close_with(session, MS_WS_CLOSE_NORMAL, ms_span_of(NULL, 0));
}
