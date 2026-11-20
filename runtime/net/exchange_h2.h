/* The HTTP/2 half of the server exchange (ms_rt/xchg.h): what the HTTP/1 exchange does for a request and its
 * response, over one stream of an h2_serve.h connection. The natives dispatch to these calls for an exchange made
 * by this layer; policy (limits, timeouts, error answers, sniffing, routing) stays in the standard library.
 *
 * A connection has two tasks. The connection task runs ms_xchg_h2_conn_run; the accept side calls
 * ms_xchg_h2_conn_next for each request and starts one handler task per exchange. Handlers use the exchange calls
 * and end with ms_xchg_h2_finish or ms_xchg_h2_drop. Each call returns the runtime's STATUS_* codes the natives of
 * xchg.h return, with `err` as there.
 */
#ifndef MS_NET_EXCHANGE_H2_H
#define MS_NET_EXCHANGE_H2_H

#include <stdint.h>

#include "h2_serve.h"
#include "headers.h"
#include "ms_rt/base.h"
#include "ms_rt/string.h"

typedef struct MsXchgH2Conn MsXchgH2Conn;
typedef struct MsXchgH2 MsXchgH2;

/* Serves HTTP/2 on the open row (ALPN h2 or prior knowledge). Returns NULL when out of memory or the id is stale;
 * the row stays the caller's then. `idle_ns` bounds the wait on an idle connection (0: none). */
MsXchgH2Conn *ms_xchg_h2_conn_new(MsConnTable *table, MsConnId id, const MsH2Limits *limits, int64_t idle_ns);
/* The connection task: runs until the connection is over, then waits for the handlers to finish and closes the row.
 * Requests that arrived and were never taken by `next` are released. */
MsNetStatus ms_xchg_h2_conn_run(MsXchgH2Conn *conn);
/* The next request, parking until one arrives or the absolute deadline (negative: none) passes. MS_NET_CLOSED once
 * the connection is over and no request is left; MS_NET_TIMEOUT at the deadline. */
MS_NODISCARD MsNetStatus ms_xchg_h2_conn_next(MsXchgH2Conn *conn, int64_t deadline_ns, MsXchgH2 **out);
/* A graceful close: GOAWAY now, in-flight requests finish. */
void ms_xchg_h2_conn_drain(MsXchgH2Conn *conn);
/* Drops the caller's reference after `run` has returned and no task waits in `next` any more. */
void ms_xchg_h2_conn_free(MsXchgH2Conn *conn);
/* The serve state, for tests that drive the connection task by hand. */
MsH2Serve *ms_xchg_h2_conn_serve(MsXchgH2Conn *conn);

/* Wraps a request as the exchange object (ExchH) of the natives of xchg.h, which dispatch to the calls below
 * (defined in exchange.c). NULL when out of memory. The object drops the request with its last handle. */
MsObj *ms_exchange_from_h2(MsXchgH2 *request);

/* The request. The strings are valid until the exchange is freed; `protocol` is "HTTP/2.0". */
MsBytes ms_xchg_h2_method(const MsXchgH2 *x);
MsBytes ms_xchg_h2_target(const MsXchgH2 *x);
MsBytes ms_xchg_h2_protocol(const MsXchgH2 *x);
/* A new table of the request fields: names canonical, cookie fields joined with "; ", Host from :authority when the
 * request carries none. NULL when out of memory. */
MsHeaders *ms_xchg_h2_headers(const MsXchgH2 *x);

/* The calls of xchg.h on this exchange (see there). `keep` of finish is 1 while the connection can carry more
 * requests. A 1xx status on send_head is accepted and sends nothing. */
uint8_t ms_xchg_h2_read(MsXchgH2 *x, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsVec *out, MsStr *err);
uint8_t ms_xchg_h2_send_head(MsXchgH2 *x, int64_t status, const MsHeaders *headers, uint8_t has_length, int64_t length, MsStr *err);
uint8_t ms_xchg_h2_write(MsXchgH2 *x, MsBytes data, uint8_t has_timeout, int64_t timeout, MsStr *err);
uint8_t ms_xchg_h2_finish(MsXchgH2 *x, uint8_t has_timeout, int64_t timeout, uint8_t *keep, MsStr *err);
uint8_t ms_xchg_h2_reset(MsXchgH2 *x, int64_t max, uint8_t has_timeout, int64_t timeout, MsStr *err);
/* Parks until the stream is reset or the connection ends (OK), or the task is cancelled. */
uint8_t ms_xchg_h2_wait_gone(MsXchgH2 *x, MsStr *err);
/* Ends the exchange; a stream not finished is reset (CANCEL). Safe after finish. */
void ms_xchg_h2_drop(MsXchgH2 *x);

#endif
