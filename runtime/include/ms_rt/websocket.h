/* ms_rt/websocket.h: the natives of a WebSocket session (SocketH), over runtime/net/ws_socket.c. Fallible functions
 * return a status (0 ok, STATUS_NONE for the peer's normal close, otherwise the runtime's STATUS_* code; STATUS_FAILED
 * carries its text through `err`) and write their result through an out parameter only on success. A SocketH handle
 * (`object`) is an MsObj whose `drop` releases one reference to the session; `share` is another handle on the same
 * session. Symbols are listed in runtime/symbols/websocket.txt. */
#ifndef MS_RT_WEBSOCKET_H
#define MS_RT_WEBSOCKET_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms: domain WebSocket */

/* WebSocketMessage at its natural layout. */
typedef struct MsWebSocketMessage {
    MsVec data;
    uint8_t text;
} MsWebSocketMessage;

/* ms-sig: msstd_websocket_close(handle s: *const ObjCell<SocketH>) @domain=WebSocket */
void msstd_websocket_close(const void *handle);
/* ms-sig: msstd_websocket_close_if_last(handle s: *const ObjCell<SocketH>) @domain=WebSocket */
void msstd_websocket_close_if_last(const void *handle);
/* ms-sig: msstd_websocket_ping(handle s: *const ObjCell<SocketH>, data: *const StrVal, err: ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_ping(const void *handle, const MsStr *data, MsStr *err);
/* ms-sig: msstd_websocket_ping_bytes(handle s: *const ObjCell<SocketH>, data: *const VecVal, err: ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_ping_bytes(const void *handle, const MsVec *data, MsStr *err);
/* ms-sig: msstd_websocket_receive(handle s: *const ObjCell<SocketH>, out: *mut WebSocketMessageType, err: ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_receive(const void *handle, MsWebSocketMessage *out, MsStr *err);
/* ms-sig: msstd_websocket_send_bytes(handle s: *const ObjCell<SocketH>, data: *const VecVal, text: u8, err: ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_send_bytes(const void *handle, const MsVec *data, uint8_t text, MsStr *err);
/* ms-sig: msstd_websocket_share(handle s: *const ObjCell<SocketH>) -> *mut ObjCell<SocketH> @handle @domain=WebSocket */
void *msstd_websocket_share(const void *handle);
/* ms-sig: msstd_websocket_subprotocol(handle s: *const ObjCell<SocketH>, out: *mut StrVal) @domain=WebSocket */
void msstd_websocket_subprotocol(const void *handle, MsStr *out);

/* The server end of a session over the connection `conn` (ConnH), which the upgrade handshake has just answered with its
 * 101: bytes the HTTP layer read past the request stay in the connection and are the first frames. `compress` is
 * whether permessage-deflate was negotiated, `subprotocol` the one selected (empty for none), and the limit must be
 * positive when given (STATUS_INVALID_INPUT). */
/* ms-sig: msstd_ws_server_new(handle conn: *const ObjCell<ConnH>, compress: u8, subprotocol: *const StrVal, has_max: HasRaw, max: i64, out: *mut *mut ObjCell<SocketH>, err: ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_ws_server_new(const void *conn, uint8_t compress, const MsStr *subprotocol, uint8_t has_max, int64_t max,
                            void **out, MsStr *err);
/* The Sec-WebSocket-Accept value for a client's Sec-WebSocket-Key (RFC 6455 4.2.2); STATUS_INVALID_INPUT for a key
 * longer than 128 bytes. */
/* ms-sig: msstd_ws_accept_key(key: *const StrVal, out: *mut StrVal) -> u8 @domain=WebSocket */
uint8_t msstd_ws_accept_key(const MsStr *key, MsStr *out);

#endif
