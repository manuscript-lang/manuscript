/* The SocketH natives of @std/net/websocket.ms over ws_socket.h, declared here until the standard library switches to
 * them: the Rust SocketH natives of the same names still produce the sessions the standard library holds, so the switch
 * (client dial, server upgrade and these natives together) moves these declarations to ms_rt/ and lists the symbols in
 * runtime/symbols (the symbols check rejects it before then). */
#ifndef MS_NET_WS_SOCKET_NATIVES_H
#define MS_NET_WS_SOCKET_NATIVES_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"
#include "ws_socket.h"

/* The runtime status for a WebSocket status; `why` is the text for MS_WSS_FAILED (the session's own error when NULL). A
 * cancelled wait ends the native through the scheduler. */
uint8_t ms_ws_finish(MsWsStatus status, const char *why, MsStr *err);

/* One received message at its natural layout: the payload, then 1 for a text frame. */
typedef struct MsNetWsMessage {
    MsVec data;
    uint8_t text;
} MsNetWsMessage;

/* ms-sig: msstd_websocket_close(handle s: *const ObjCell<SocketH>) @domain=WebSocket */
void msstd_websocket_close(const void *handle);
/* ms-sig: msstd_websocket_share(handle s: *const ObjCell<SocketH>) -> *mut ObjCell<SocketH> @handle @domain=WebSocket */
void *msstd_websocket_share(const void *handle);
/* ms-sig: msstd_websocket_close_if_last(handle s: *const ObjCell<SocketH>) @domain=WebSocket */
void msstd_websocket_close_if_last(const void *handle);
/* ms-sig: msstd_websocket_subprotocol(handle s: *const ObjCell<SocketH>, out: *mut StrVal) @domain=WebSocket */
void msstd_websocket_subprotocol(const void *handle, MsStr *out);
/* ms-sig: msstd_websocket_ping(handle s: *const ObjCell<SocketH>, data: *const StrVal, err: ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_ping(const void *handle, const MsStr *data, MsStr *err);
/* ms-sig: msstd_websocket_ping_bytes(handle s: *const ObjCell<SocketH>, data: *const VecVal, err: ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_ping_bytes(const void *handle, const MsVec *data, MsStr *err);
/* ms-sig: msstd_websocket_send_bytes(handle s: *const ObjCell<SocketH>, data: *const VecVal, text: u8, err: ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_send_bytes(const void *handle, const MsVec *data, uint8_t text, MsStr *err);
/* The next message; STATUS_NONE (nothing written) when the peer closed normally. */
/* ms-sig: msstd_websocket_receive(handle s: *const ObjCell<SocketH>, out: *mut WebSocketMessageType, err: ErrSlot) -> u8 @domain=WebSocket */
uint8_t msstd_websocket_receive(const void *handle, MsNetWsMessage *out, MsStr *err);

#endif
