/* The client WebSocket native, declared here until the standard library switches to the C natives: the switch moves
 * this declaration to ms_rt/ and lists the symbol in runtime/symbols (the symbols check rejects it before then). */
#ifndef MS_NET_WS_CONNECT_H
#define MS_NET_WS_CONNECT_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* Runs the WebSocket handshake on `conn`, a ConnH the caller dialed and checked against its policy (TLS included),
 * and gives the SocketH in *out. `headers` is a HeadersH or NULL; `subprotocols` a list of Str to offer. The handle
 * holds its own alias of the connection; the caller keeps theirs. A field the caller may not set (Host, Upgrade,
 * Connection, Sec-WebSocket-*) is STATUS_INVALID_INPUT; a refused or malformed answer is STATUS_FAILED with the reason
 * in `err`. `max` limits one message (default none). */
/* ms-sig: msstd_ws_connect(handle conn: *const ObjCell<ConnH>, authority: *const StrVal, target: *const StrVal, handle headers: *const ObjCell<HeadersH>, subprotocols: *const VecVal, compression: u8, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<SocketH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_ws_connect(const void *conn, const MsStr *authority, const MsStr *target, const void *headers,
                         const MsVec *subprotocols, uint8_t compression, uint8_t has_max, int64_t max,
                         uint8_t has_timeout, int64_t timeout, void **out, MsStr *err);

#endif
