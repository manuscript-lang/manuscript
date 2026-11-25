/* runtime/std/ws_receive.c: reading messages of a WebSocket session, and the close handshake. */
#include "base/strbuild.h"
#include "base/chars.h"
#include "base/utf8.h"
#include "runtime/sys/sys.h"
#include "runtime/std/ws_session_internal.h"

/* The time left of `timeout_ns` (negative: none) since `start`. */
static int64_t time_left(int64_t timeout_ns, int64_t start) {
  if (timeout_ns < 0) {
    return -1;
  }
  const int64_t left = timeout_ns - (ms_sys_monotonic_ns() - start);
  return left > 0 ? left : 0;
}

/* The session ends with `fault`, unless it was closed locally meanwhile. */
static MsWsFault finish(MsWsSession *session, MsWsFault fault) {
  const bool local = atomic_load(&session->closed) || session->io.is_closed(session->io.context);
  ms_ws_session_fail(session);
  if (local) {
    ms_ws_fault_release(&fault);
    return ms_ws_fault(MS_STATUS_CLOSED);
  }
  return fault;
}

/* A failure of `text`, or of the message body when one was begun. */
static MsWsFault failed_text(MsStrBuild *text, bool body) {
  if (body) {
    ms_strbuild_free(text);
    return ms_ws_fault_text(ms_ws_truncated_text);
  }
  return ms_ws_fault_string(text);
}

static MsWsFault failed_string(MsString *text, bool body) {
  MsStrBuild build = ms_strbuild_new();
  ms_strbuild_append_string(&build, text);
  return failed_text(&build, body);
}

/* Reads more bytes into the decoder; TIMED_OUT leaves the session intact. */
static MsWsFault fill(MsWsSession *session, int64_t timeout_ns, int64_t start) {
  MsBytes bytes = {0};
  MsString text = ms_string_empty();
  const bool body = ms_ws_decoder_in_message(&session->decoder);
  const uint8_t status = session->io.read(session->io.context, time_left(timeout_ns, start), &bytes, &text);
  MsWsFault fault;
  if (status == MS_STATUS_OK) {
    ms_ws_decoder_push(&session->decoder, ms_bytes_span(&bytes));
    fault = ms_ws_fault(MS_STATUS_OK);
  } else if (status == MS_STATUS_TIMED_OUT && timeout_ns >= 0) {
    fault = ms_ws_fault(MS_STATUS_TIMED_OUT);
  } else if (status == MS_STATUS_NONE) {
    MsStrBuild eof = ms_strbuild_new();
    ms_ws_close_error_text(MS_WS_CLOSE_ABNORMAL, ms_span_of_text("unexpected EOF"), &eof);
    fault = finish(session, failed_text(&eof, body));
  } else if (status == MS_STATUS_CLOSED) {
    fault = finish(session, ms_ws_fault(MS_STATUS_CLOSED));
  } else if (status == MS_STATUS_FAILED) {
    fault = finish(session, failed_string(&text, body));
  } else {
    fault = finish(session, ms_ws_fault_text(ms_ws_truncated_text));
  }
  ms_bytes_free(&bytes);
  ms_string_release(&text);
  return fault;
}

/* ---- events ---- */

static MsWsFault deliver(MsWsSession *session, MsWsEvent *event, MsWsMessage *out) {
  if (event->text && !ms_utf8_is_valid(event->data.ptr, event->data.len)) {
    atomic_store(&session->failed, true); /* RFC 6455 section 8.1: fail the connection with 1007 */
    ms_ws_session_send_close(session, MS_WS_CLOSE_INVALID_PAYLOAD, ms_span_of(NULL, 0), MS_WS_CLOSE_WRITE_NS);
    session->io.close(session->io.context);
    ms_bytes_free(&event->data);
    return ms_ws_fault(MS_STATUS_INVALID_DATA);
  }
  out->data = event->data;
  out->text = event->text;
  return ms_ws_fault(MS_STATUS_OK);
}

/* The default ping handler: a pong with the same payload. A sent close frame and a timeout are ignored; any
 * other write failure ends the session. */
static MsWsFault answer_ping(MsWsSession *session, MsSpan payload) {
  MsWsFault fault = ms_ws_session_control(session, MS_WS_OP_PONG, payload, MS_WS_CONTROL_WRITE_NS, NULL);
  const bool sent = fault.status == MS_STATUS_FAILED &&
                    ms_span_is_text(ms_string_span(&fault.text), "websocket: close sent");
  if (fault.status == MS_STATUS_OK || fault.status == MS_STATUS_TIMED_OUT || sent) {
    ms_ws_fault_release(&fault);
    return ms_ws_fault(MS_STATUS_OK);
  }
  const bool body = ms_ws_decoder_in_message(&session->decoder);
  if (fault.status == MS_STATUS_FAILED) {
    MsWsFault ended = finish(session, failed_string(&fault.text, body));
    ms_ws_fault_release(&fault);
    return ended;
  }
  ms_ws_fault_release(&fault);
  return finish(session, ms_ws_fault_text(ms_ws_truncated_text));
}

/* The default close handler: echoes the code; a close 1000 or 1001 is the normal end of the session. */
static MsWsFault peer_closed(MsWsSession *session, const MsWsEvent *event) {
  ms_ws_session_send_close(session, event->code, ms_span_of(NULL, 0), MS_WS_CONTROL_WRITE_NS);
  const bool body = ms_ws_decoder_in_message(&session->decoder);
  if (!body && (event->code == MS_WS_CLOSE_NORMAL || event->code == MS_WS_CLOSE_GOING_AWAY)) {
    ms_ws_session_fail(session);
    return ms_ws_fault(MS_STATUS_NONE);
  }
  MsStrBuild text = ms_strbuild_new();
  ms_ws_close_error_text(event->code, ms_bytes_span(&event->data), &text);
  return finish(session, failed_text(&text, body));
}

static MsWsFault decode_failure(MsWsSession *session, MsWsError *error) {
  MsWsFault fault;
  switch (error->kind) {
  case MS_WS_ERR_PROTOCOL: {
    MsBytes payload = {0};
    ms_ws_protocol_error_payload(ms_string_span(&error->text), &payload);
    MsWsFault sent =
        ms_ws_session_control(session, MS_WS_OP_CLOSE, ms_bytes_span(&payload), MS_WS_CONTROL_WRITE_NS, NULL);
    ms_ws_fault_release(&sent);
    ms_bytes_free(&payload);
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "websocket: ");
    ms_strbuild_append_string(&text, &error->text);
    fault = failed_text(&text, error->body);
    break;
  }
  case MS_WS_ERR_LIMIT:
    if (error->reply_close) {
      ms_ws_session_send_close(session, MS_WS_CLOSE_MESSAGE_TOO_BIG, ms_span_of(NULL, 0),
                               MS_WS_CONTROL_WRITE_NS);
    }
    fault = error->body ? ms_ws_fault_text(ms_ws_truncated_text) : ms_ws_fault(MS_STATUS_LIMIT_EXCEEDED);
    break;
  case MS_WS_ERR_INVALID_PAYLOAD:
    ms_ws_session_send_close(session, MS_WS_CLOSE_INVALID_PAYLOAD, ms_span_of(NULL, 0),
                             MS_WS_CONTROL_WRITE_NS);
    fault = ms_ws_fault(MS_STATUS_INVALID_DATA);
    break;
  case MS_WS_ERR_OVERFLOW:
    fault = ms_ws_fault(MS_STATUS_LIMIT_EXCEEDED);
    break;
  default:
    fault = ms_ws_fault_text(ms_ws_truncated_text);
    break;
  }
  ms_ws_error_release(error);
  return finish(session, fault);
}

/* Handles one event; false when the receive goes on. */
static bool on_event(MsWsSession *session, MsWsEvent *event, MsWsMessage *out, MsWsFault *result) {
  *result = ms_ws_fault(MS_STATUS_OK);
  switch (event->kind) {
  case MS_WS_MESSAGE:
    *result = deliver(session, event, out);
    return true;
  case MS_WS_PING:
    *result = answer_ping(session, ms_bytes_span(&event->data));
    ms_bytes_free(&event->data);
    return result->status != MS_STATUS_OK;
  case MS_WS_PONG:
    ms_bytes_free(&event->data);
    return false;
  default:
    *result = peer_closed(session, event);
    ms_bytes_free(&event->data);
    return true;
  }
}

static MsWsFault receive_loop(MsWsSession *session, int64_t timeout_ns, MsWsMessage *out) {
  const int64_t start = ms_sys_monotonic_ns();
  for (;;) {
    MsWsEvent event;
    MsWsError error;
    const MsWsPoll poll = ms_ws_decoder_poll(&session->decoder, &event, &error);
    if (poll == MS_WS_NEED_MORE) {
      MsWsFault fault = fill(session, timeout_ns, start);
      if (fault.status != MS_STATUS_OK) {
        return fault;
      }
      continue;
    }
    if (poll == MS_WS_GOT_ERROR) {
      return decode_failure(session, &error);
    }
    MsWsFault result;
    if (on_event(session, &event, out, &result)) {
      return result;
    }
  }
}

uint8_t ms_ws_session_receive(MsWsSession *session, int64_t timeout_ns, MsWsMessage *out, MsString *err) {
  *err = ms_string_empty();
  *out = (MsWsMessage){0};
  if (ms_ws_session_ended(session)) {
    return MS_STATUS_CLOSED;
  }
  if (atomic_exchange(&session->reading, true)) {
    *err = ms_string_from_span(ms_span_of_text("websocket: concurrent receive"));
    return MS_STATUS_FAILED;
  }
  MsWsFault fault = receive_loop(session, timeout_ns, out);
  atomic_store(&session->reading, false);
  return ms_ws_fault_take(&fault, err);
}

/* ---- the close handshake ---- */
