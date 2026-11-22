/* runtime/std/ws_abi.h: the WebSocket handle natives of @std/net/websocket over ws_session.h. A handle is a
 * reference on a session; the session closes its connection on close() and ends when the last handle drops.
 */
#ifndef MS_RUNTIME_STD_WS_ABI_H
#define MS_RUNTIME_STD_WS_ABI_H

#include "abi/status.h"
#include "runtime/std/ws_session.h"

/* A received message as the program sees it. */
typedef struct MsWebSocketMessage {
  MsBytes data;
  uint8_t text;
} MsWebSocketMessage;

/* A session over `connection` (a connection handle, which the session owns), after the handshake: `leftover`
 * are the bytes read past the handshake head. `config` is consumed. */
/* A connection handle of @std/net as a stream; the transport owns the handle. */
MsWsTransport ms_net_connection_transport(MsObj *connection);
MsWsSession *ms_ws_connection_session(MsObj *connection, MsWsConfig *config, MsSpan leftover);
/* A handle (a new reference) on `session`. */
MsObj *ms_ws_handle_new(MsWsSession *session);

/* ms-sig: msstd_websocket_close(handle s: *const ObjCell<SocketH>) @domain=WebSocket */
void msstd_websocket_close(const MsObj *s);
/* ms-sig: msstd_websocket_share(handle s: *const ObjCell<SocketH>) -> *mut ObjCell<SocketH> @handle
 * @domain=WebSocket */
MsObj *msstd_websocket_share(const MsObj *s);
/* Closes the session when `s` is its last handle. */
/* ms-sig: msstd_websocket_close_if_last(handle s: *const ObjCell<SocketH>) @domain=WebSocket */
void msstd_websocket_close_if_last(const MsObj *s);
/* ms-sig: msstd_websocket_subprotocol(handle s: *const ObjCell<SocketH>, out: *mut StrVal) @domain=WebSocket
 */
void msstd_websocket_subprotocol(const MsObj *s, MsString *out);
/* ms-sig: msstd_websocket_ping(handle s: *const ObjCell<SocketH>, data: *const StrVal, err: ErrSlot) -> u8
 * @domain=WebSocket */
uint8_t msstd_websocket_ping(const MsObj *s, const MsString *data, MsString *err);
/* ms-sig: msstd_websocket_ping_bytes(handle s: *const ObjCell<SocketH>, data: *const VecVal, err: ErrSlot) ->
 * u8 @domain=WebSocket */
uint8_t msstd_websocket_ping_bytes(const MsObj *s, const MsBytes *data, MsString *err);
/* ms-sig: msstd_websocket_send_bytes(handle s: *const ObjCell<SocketH>, data: *const VecVal, text: u8, err:
 * ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_send_bytes(const MsObj *s, const MsBytes *data, uint8_t text, MsString *err);
/* The peer's normal close is MS_STATUS_NONE. */
/* ms-sig: msstd_websocket_receive(handle s: *const ObjCell<SocketH>, out: *mut WebSocketMessageType, err:
 * ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_receive(const MsObj *s, MsWebSocketMessage *out, MsString *err);

#endif
