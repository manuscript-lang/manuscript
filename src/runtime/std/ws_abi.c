/* runtime/std/ws_abi.c: the WebSocket natives (ws_abi.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */
#include "runtime/std/ws_abi.h"

#include "base/alloc.h"
#include "runtime/std/fail.h"
#include "runtime/std/net_conn.h"

typedef struct WsHandle {
  MsObj header;
  MsWsSession *session;
} WsHandle;

static void handle_drop(MsObj *object) {
  WsHandle *handle = (WsHandle *)(void *)object;
  ms_ws_session_release(handle->session);
  ms_free(handle);
}

MsObj *ms_ws_handle_new(MsWsSession *session) {
  WsHandle *handle = ms_alloc_zeroed(sizeof *handle);
  handle->header.drop = handle_drop;
  handle->session = ms_ws_session_retain(session);
  return &handle->header;
}

static MsWsSession *session_of(const MsObj *object) {
  return ((const WsHandle *)(const void *)object)->session;
}

/* ---- the transport: a connection handle of @std/net ---- */

static uint8_t conn_read(void *context, int64_t timeout_ns, MsBytes *out, MsString *err) {
  return msstd_net_connection_read(context, 0, 0, timeout_ns >= 0, timeout_ns, out, err);
}

static uint8_t conn_write(void *context, MsSpan data, int64_t timeout_ns, MsString *err) {
  const MsBytes view = ms_bytes_view(data);
  return msstd_net_connection_write_bytes(context, &view, timeout_ns >= 0, timeout_ns, err);
}

static void conn_close(void *context) {
  msstd_net_connection_close(context);
}

static bool conn_is_closed(void *context) {
  return atomic_load(&ms_net_handle_core(context)->closed);
}

static void conn_shutdown_write(void *context) {
  MsString err = ms_string_empty();
  (void)msstd_net_connection_shutdown_write(context, &err);
  ms_string_release(&err);
}

static bool conn_steal_read(void *context, MsBytes *out) {
  return ms_net_core_steal_read(ms_net_handle_core(context), out);
}

static void conn_release(void *context) {
  MsObj *connection = context;
  connection->drop(connection);
}

MsWsTransport ms_net_connection_transport(MsObj *connection) {
  return (MsWsTransport){.context = connection,
                         .read = conn_read,
                         .write = conn_write,
                         .close = conn_close,
                         .is_closed = conn_is_closed,
                         .release = conn_release,
                         .shutdown_write = conn_shutdown_write,
                         .steal_read = conn_steal_read};
}

MsWsSession *ms_ws_connection_session(MsObj *connection, MsWsConfig *config, MsSpan leftover) {
  const MsWsTransport transport = ms_net_connection_transport(connection);
  return ms_ws_session_new(&transport, config, leftover);
}

/* ---- the natives ---- */

void msstd_websocket_close(const MsObj *s) {
  ms_ws_session_close(session_of(s));
}

MsObj *msstd_websocket_share(const MsObj *s) {
  return ms_ws_handle_new(session_of(s));
}

void msstd_websocket_close_if_last(const MsObj *s) {
  if (ms_ws_session_is_last(session_of(s))) {
    ms_ws_session_close(session_of(s));
  }
}

void msstd_websocket_subprotocol(const MsObj *s, MsString *out) {
  *out = ms_string_from_span(ms_string_span(ms_ws_session_subprotocol(session_of(s))));
}

uint8_t msstd_websocket_ping(const MsObj *s, const MsString *data, MsString *err) {
  MsString text = ms_string_empty();
  const uint8_t status = ms_ws_session_ping(session_of(s), ms_string_span(data), &text);
  return ms_fail_finish_with(status, &text, err);
}

uint8_t msstd_websocket_ping_bytes(const MsObj *s, const MsBytes *data, MsString *err) {
  MsString text = ms_string_empty();
  const uint8_t status = ms_ws_session_ping(session_of(s), ms_bytes_span(data), &text);
  return ms_fail_finish_with(status, &text, err);
}

uint8_t msstd_websocket_send_bytes(const MsObj *s, const MsBytes *data, uint8_t text, MsString *err) {
  MsString failure = ms_string_empty();
  const uint8_t status = ms_ws_session_send(session_of(s), ms_bytes_span(data), text != 0, -1, &failure);
  return ms_fail_finish_with(status, &failure, err);
}

uint8_t msstd_websocket_receive(const MsObj *s, MsWebSocketMessage *out, MsString *err) {
  MsWsMessage message;
  MsString text = ms_string_empty();
  const uint8_t status = ms_ws_session_receive(session_of(s), -1, &message, &text);
  *out = (MsWebSocketMessage){.data = message.data, .text = message.text};
  return ms_fail_finish_with(status, &text, err);
}
