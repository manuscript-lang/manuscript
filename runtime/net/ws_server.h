/* The server side of the WebSocket opening handshake and the session it opens, over an exchange of the HTTP layer.
 * `msstd_ws_handshake` checks an upgrade request and answers what to send; standard-library code sends it with the
 * exchange natives (a 1xx head, `msstd_xchg_send_head`), takes the connection (`msstd_xchg_take_conn`) and calls
 * `msstd_ws_serve` on it. Declared here until the standard library switches to them: the switch moves these
 * declarations to ms_rt/ and lists the symbols in runtime/symbols (the symbols check would reject them before then). */
#ifndef MS_NET_WS_SERVER_H
#define MS_NET_WS_SERVER_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* Checks an upgrade request in this order: Connection (token "upgrade"), Upgrade ("websocket"), method GET, a
 * Sec-WebSocket-Version of 13 (426 when the field is present without it, else 400), the origin, and a Sec-WebSocket-Key
 * of 16 base64 bytes that appears once. `host` is the request's Host and `tls` whether the connection is TLS. A missing
 * or empty Origin is accepted; otherwise it must be a bare http(s) origin that equals an entry of `origins` or, with
 * `origins` empty, has the request's scheme and host (host compared without case). The first subprotocol of
 * `subprotocols` (server order) that the client offered is selected.
 *
 * STATUS_OK: `*status` is 101 and `response` holds the fields to send (Upgrade, Connection, Sec-WebSocket-Accept and
 * the selected Sec-WebSocket-Protocol), `subprotocol` the selected one ("" for none). Or `*status` is the refusal to
 * answer (400, 403, 405, 426) and `err` its text, such as "websocket: request origin not allowed"; the refusal also
 * wants `Sec-WebSocket-Version: 13` and `Connection: close` on its response. A subprotocol that is not an HTTP token is
 * STATUS_INVALID_INPUT. */
/* ms-sig: msstd_ws_handshake(method: *const StrVal, host: *const StrVal, tls: u8, handle request: *const ObjCell<HeadersH>, origins: *const VecVal, subprotocols: *const VecVal, handle response: *const ObjCell<HeadersH>, status: *mut i64, subprotocol: *mut StrVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_ws_handshake(const MsStr *method, const MsStr *host, uint8_t tls, const void *request, const MsVec *origins,
                           const MsVec *subprotocols, const void *response, int64_t *status, MsStr *subprotocol, MsStr *err);

/* The session over `conn`, a ConnH taken from an exchange after the 101 head was sent; bytes the HTTP layer read ahead
 * come first. `subprotocol` is the one msstd_ws_handshake selected; `max` limits one message (default none). The
 * session holds its own handle on the connection; the caller keeps theirs. */
/* ms-sig: msstd_ws_serve(handle conn: *const ObjCell<ConnH>, subprotocol: *const StrVal, has_max: HasRaw, max: i64, out: *mut *mut ObjCell<SocketH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_ws_serve(const void *conn, const MsStr *subprotocol, uint8_t has_max, int64_t max, void **out, MsStr *err);

#endif
