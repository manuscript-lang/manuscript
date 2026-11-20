/* ms_rt/xchg.h: the server side of one HTTP/1 request and response on a connection (runtime/net/exchange.c over the
 * connection rows). An exchange (ExchH) is made by `next` from an accepted connection and lives until `finish`.
 * Request heads, the body framing (length or chunked, trailers dropped) and the response head and body framing are
 * here; limits (413, 431 policy), timeouts, routing and the accept loop are standard-library code. The HTTP/2 half
 * supplies the same natives in runtime/net/exchange_h2.c behind the same ExchH.
 *
 * Fallible functions return a status (0 ok, STATUS_NONE for "no more", otherwise the runtime's STATUS_* code;
 * STATUS_FAILED carries its text through `err`) and write results through out parameters only on success. Times
 * are nanoseconds. Symbols are listed in runtime/symbols/xchg.txt. */
#ifndef MS_RT_XCHG_H
#define MS_RT_XCHG_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms: domain HTTP */

/* Reads the next request head from the connection (the bytes left over by the previous exchange come first) and
 * answers an exchange for it. STATUS_NONE: the peer closed before sending a byte, so there is no exchange.
 * STATUS_INVALID_DATA: the head is malformed or longer than `head_limit`; msstd_xchg_reject_status then answers the
 * status to send (400, 431 or 501) with msstd_xchg_reject. */
/* ms-sig: msstd_xchg_next(handle c: *const ObjCell<ConnH>, head_limit: i64, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ExchH>, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_xchg_next(const void *conn, int64_t head_limit, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err);

/* The status to answer for the head the last msstd_xchg_next on this connection refused; 0 when it did not refuse one. */
/* ms-sig: msstd_xchg_reject_status(handle c: *const ObjCell<ConnH>) -> i64 @domain=HTTP */
int64_t msstd_xchg_reject_status(const void *conn);

/* Answers a refused head: the status line, `Connection: close` and an empty body; the connection is not reusable. */
/* ms-sig: msstd_xchg_reject(handle c: *const ObjCell<ConnH>, status: i64, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_xchg_reject(const void *conn, int64_t status, uint8_t has_timeout, int64_t timeout, MsStr *err);

/* The request line and fields, one native each: the method as sent, the request target as sent, "HTTP/1.0" or
 * "HTTP/1.1", and the fields (names in canonical form, values as bytes) as a table the exchange keeps: the handle is
 * the caller's own. */
/* ms-sig: msstd_xchg_method(handle x: *const ObjCell<ExchH>, out: *mut StrVal) @domain=HTTP */
void msstd_xchg_method(const void *handle, MsStr *out);
/* ms-sig: msstd_xchg_target(handle x: *const ObjCell<ExchH>, out: *mut StrVal) @domain=HTTP */
void msstd_xchg_target(const void *handle, MsStr *out);
/* ms-sig: msstd_xchg_protocol(handle x: *const ObjCell<ExchH>, out: *mut StrVal) @domain=HTTP */
void msstd_xchg_protocol(const void *handle, MsStr *out);
/* ms-sig: msstd_xchg_headers(handle x: *const ObjCell<ExchH>) -> *mut ObjCell<HeadersH> @handle @domain=HTTP */
void *msstd_xchg_headers(const void *handle);

/* The next piece of the request body with the framing removed: STATUS_OK with up to `max` bytes (default 64 KiB),
 * STATUS_NONE at the end of the body. A truncated or malformed body is STATUS_INVALID_DATA. */
/* ms-sig: msstd_xchg_read(handle x: *const ObjCell<ExchH>, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_xchg_read(const void *handle, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsVec *out, MsStr *err);

/* Sends the response head. With `has_length` the body is `length` bytes (Content-Length), else it is chunked
 * (HTTP/1.1) or runs to the close (HTTP/1.0). `headers` are the response fields; a Content-Length or
 * Transfer-Encoding among them is ignored. The head is refused (STATUS_INVALID_INPUT) when a name or value could
 * split the response, the status is not 100 to 999, or a head was already sent. A 1xx status sends the head only and
 * leaves the final one to come. */
/* ms-sig: msstd_xchg_send_head(handle x: *const ObjCell<ExchH>, status: i64, handle headers: *const ObjCell<HeadersH>, has_length: HasRaw, length: i64, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_xchg_send_head(const void *handle, int64_t status, const void *headers_handle, uint8_t has_length, int64_t length, uint8_t has_timeout, int64_t timeout, MsStr *err);

/* Writes body bytes after the head. More than the declared length is STATUS_OUT_OF_RANGE and sends nothing. */
/* ms-sig: msstd_xchg_write(handle x: *const ObjCell<ExchH>, data: *const VecVal, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_xchg_write(const void *handle, const MsVec *data, uint8_t has_timeout, int64_t timeout, MsStr *err);

/* Ends the response (the closing chunk when chunked) and answers whether the connection can carry another request:
 * `*keep` is 1 when the request allowed it, the response was framed, and the request body was read to its end. A
 * body shorter than the declared length is STATUS_INVALID_DATA and the connection is not reusable. */
/* ms-sig: msstd_xchg_finish(handle x: *const ObjCell<ExchH>, has_timeout: HasRaw, timeout: i64, out: *mut u8, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_xchg_finish(const void *handle, uint8_t has_timeout, int64_t timeout, uint8_t *keep, MsStr *err);

/* Reads and drops what is left of the request body, at most `max` bytes, so the connection can be reused after a
 * handler that did not read it. STATUS_LIMIT_EXCEEDED when more is left: close the connection instead. */
/* ms-sig: msstd_xchg_reset(handle x: *const ObjCell<ExchH>, max: i64, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_xchg_reset(const void *handle, int64_t max, uint8_t has_timeout, int64_t timeout, MsStr *err);

/* Another handle on the same exchange: the handler owns one as its `HttpExchange`, the connection loop keeps the other
 * to finish the response after the handler returns. The exchange ends with its last handle. */
/* ms-sig: msstd_xchg_share(handle x: *const ObjCell<ExchH>) -> *mut ObjCell<ExchH> @handle @domain=HTTP */
void *msstd_xchg_share(const void *handle);

/* Parks until the peer is gone from this exchange: an HTTP/1 peer that closed or half-closed its side (bytes it sent
 * ahead stay queued), an HTTP/2 stream the peer reset or a connection that ended. Returns OK then; the error is the
 * task's cancellation. A handler runs next to a task waiting here and is cancelled when it returns. */
/* ms-sig: msstd_xchg_wait_gone(handle x: *const ObjCell<ExchH>, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_xchg_wait_gone(const void *handle, MsStr *err);

/* Hands the connection on for a protocol switch (WebSocket) before any response head is sent: the handle is a new
 * stream end of the same connection; bytes read ahead stay on the row and come first from msstd_conn_read. The
 * exchange is spent afterwards. STATUS_INVALID_INPUT once a head was sent. */
/* ms-sig: msstd_xchg_take_conn(handle x: *const ObjCell<ExchH>, out: *mut *mut ObjCell<ConnH>) -> u8 @domain=HTTP */
uint8_t msstd_xchg_take_conn(const void *handle, void **out);

/* The count of requests running at once, shared by the tasks of every thread (runtime/net/admission.c). `enter`
 * is STATUS_LIMIT_EXCEEDED when `max` requests already run (nothing is counted then); `leave` ends one that entered. */
/* ms-sig: msstd_admit_new(has_max: HasRaw, max: i64) -> *mut ObjCell<AdmitH> @handle @domain=HTTP */
void *msstd_admit_new(uint8_t has_max, int64_t max);
/* ms-sig: msstd_admit_share(handle a: *const ObjCell<AdmitH>) -> *mut ObjCell<AdmitH> @handle @domain=HTTP */
void *msstd_admit_share(const void *handle);
/* ms-sig: msstd_admit_enter(handle a: *const ObjCell<AdmitH>) -> u8 @domain=HTTP */
uint8_t msstd_admit_enter(const void *handle);
/* ms-sig: msstd_admit_leave(handle a: *const ObjCell<AdmitH>) @domain=HTTP */
void msstd_admit_leave(const void *handle);

/* The request handler of a server, shared by the tasks of every thread (runtime/net/handler.c). `new` takes the
 * `fn() Void` closure that serves one request: it calls `take` first for the exchange `call` hands it (a new handle on
 * the one the caller passed), and sets `keep` (1: the connection can carry another request) before it returns. */
/* ms-sig: msstd_handler_new(run: *mut Closure) -> *mut ObjCell<HandlerH> @handle @keeps:run @domain=HTTP */
void *msstd_handler_new(void *run);
/* ms-sig: msstd_handler_share(handle h: *const ObjCell<HandlerH>) -> *mut ObjCell<HandlerH> @handle @domain=HTTP */
void *msstd_handler_share(const void *handle);
/* ms-sig: msstd_handler_call(handle h: *const ObjCell<HandlerH>, handle x: *const ObjCell<ExchH>, out: *mut u8, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_handler_call(const void *handle, const void *exchange, uint8_t *keep, MsStr *err);
/* ms-sig: msstd_handler_take() -> *mut ObjCell<ExchH> @handle @domain=HTTP */
void *msstd_handler_take(void);
/* ms-sig: msstd_handler_keep(keep: u8) @domain=HTTP */
void msstd_handler_keep(uint8_t keep);

/* Idle connections (runtime/net/idle_natives.c over runtime/core/idle.c). After a response that keeps the connection
 * alive the serving task hands it here and ends: the connection waits as a row, without a task, so a resting thread can
 * take it when this one is held up by a long handler. When the peer sends a request (or input is already held) the
 * pool starts `next`, a plain function value, as a promise of the thread that serves it; `next` reads the head, serves
 * the request and parks the connection again, or closes it. `timeout` bounds the wait; an expired one closes the
 * connection. The pool owns `next` from the call, also when it fails (STATUS_CLOSED: the connection is gone). */
/* ms-sig: msstd_idle_park(handle c: *const ObjCell<ConnH>, next: *mut Closure, group: i64, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=HTTP @keeps:next */
uint8_t msstd_idle_park(const void *conn, void *next, int64_t group, uint8_t has_timeout, int64_t timeout, MsStr *err);
/* A number that names one server's idle connections, for msstd_idle_drain. */
/* ms-sig: msstd_idle_group() -> i64 @domain=HTTP */
int64_t msstd_idle_group(void);
/* Closes the idle connections of `group` now; requests in flight finish. */
/* ms-sig: msstd_idle_drain(group: i64) @domain=HTTP */
void msstd_idle_drain(int64_t group);
/* The requests of `group` running or waiting to run. */
/* ms-sig: msstd_idle_inflight(group: i64) -> i64 @domain=HTTP */
int64_t msstd_idle_inflight(int64_t group);
/* Asks the requests in flight of `group` to end as a cancelled promise does (the grace period of a close ran out). */
/* ms-sig: msstd_idle_cancel(group: i64) @domain=HTTP */
void msstd_idle_cancel(int64_t group);

/* HTTP/2 connections (runtime/net/exchange_h2_natives.c over exchange_h2.c). After a handshake that chose h2 (see
 * msstd_conn_alpn), `open` starts HTTP/2 on the connection (limits of 0 are the defaults, `idle` bounds a wait with
 * no stream open). One task runs `run` for the life of the connection; another loops on `next`, which answers an
 * exchange for each request (the same ExchH the msstd_xchg_* natives above work on, so a handler cannot tell h1 from
 * h2) and STATUS_NONE once the connection is over. `drain` sends GOAWAY and lets requests in flight finish. */
/* ms-sig: msstd_h2_open(handle c: *const ObjCell<ConnH>, max_streams: i64, max_header_list: i64, stream_window: i64, connection_window: i64, has_idle: HasRaw, idle: i64, out: *mut *mut ObjCell<H2ConnH>, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_h2_open(const void *conn, int64_t max_streams, int64_t max_header_list, int64_t stream_window, int64_t connection_window, uint8_t has_idle, int64_t idle, void **out, MsStr *err);
/* ms-sig: msstd_h2_run(handle h: *const ObjCell<H2ConnH>, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_h2_run(const void *h2, MsStr *err);
/* ms-sig: msstd_h2_next(handle h: *const ObjCell<H2ConnH>, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ExchH>, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_h2_next(const void *h2, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err);
/* ms-sig: msstd_h2_drain(handle h: *const ObjCell<H2ConnH>) @domain=HTTP */
void msstd_h2_drain(const void *h2);
/* Another handle on the same connection, for the task that runs it. */
/* ms-sig: msstd_h2_share(handle h: *const ObjCell<H2ConnH>) -> *mut ObjCell<H2ConnH> @handle @domain=HTTP */
void *msstd_h2_share(const void *h2);


/* ---- WebSocket upgrade (runtime/net/ws_server.c) ---- */

/* What a handshake answers: `status` is 101 for an accepted upgrade, whose `response` fields were filled in, or the
 * refusal to answer (400, 403, 405, 426) with `reason` its text; `subprotocol` is the one selected ("" for none). */
typedef struct MsNetWsHandshake {
    int64_t status;
    MsStr subprotocol;
    MsStr reason;
} MsNetWsHandshake;

/* Checks an upgrade request in this order: Connection (token "upgrade"), Upgrade ("websocket"), method GET, a
 * Sec-WebSocket-Version of 13 (426 when the field is present without it, else 400), the origin, and a Sec-WebSocket-Key
 * of 16 base64 bytes that appears once. `host` is the request's Host and `tls` whether the connection is TLS. A missing
 * or empty Origin is accepted; otherwise it must be a bare http(s) origin that equals an entry of `origins` or, with
 * `origins` empty, has the request's scheme and host (host compared without case). The first subprotocol of
 * `subprotocols` (server order) that the client offered is selected.
 *
 * STATUS_OK with `out->status` 101: `response` holds the fields to send (Upgrade, Connection, Sec-WebSocket-Accept and
 * the selected Sec-WebSocket-Protocol). STATUS_OK with a refusal status and its text in `out->reason`, such as
 * "websocket: request origin not allowed": the refusal also wants `Sec-WebSocket-Version: 13` and `Connection: close`
 * on its response. A subprotocol that is not an HTTP token is STATUS_INVALID_INPUT. */
/* ms-sig: msstd_ws_handshake(method: *const StrVal, host: *const StrVal, tls: u8, handle request: *const ObjCell<HeadersH>, origins: *const VecVal, subprotocols: *const VecVal, handle response: *const ObjCell<HeadersH>, out: *mut WsHandshakeWire, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_ws_handshake(const MsStr *method, const MsStr *host, uint8_t tls, const void *request, const MsVec *origins, const MsVec *subprotocols, const void *response, MsNetWsHandshake *out, MsStr *err);

/* The session over `conn`, a ConnH taken from an exchange (msstd_xchg_take_conn) after the 101 head was sent; bytes the
 * HTTP layer read ahead come first. `subprotocol` is the one msstd_ws_handshake selected; `max` limits one message
 * (default none). The session holds its own handle on the connection; the caller keeps theirs. */
/* ms-sig: msstd_ws_serve(handle conn: *const ObjCell<ConnH>, subprotocol: *const StrVal, has_max: HasRaw, max: i64, out: *mut *mut ObjCell<SocketH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_ws_serve(const void *conn, const MsStr *subprotocol, uint8_t has_max, int64_t max, void **out, MsStr *err);

#endif
