/* runtime/std/http_serve.h: the HTTP server engine. A worker owns the connections it adopts, one task each; a
 * request runs its handler in a task of its own, so a fault or a time limit ends only that request. The
 * engine speaks to a byte stream (MsWsTransport, which a WebSocket reuses after an upgrade) and never to a
 * socket. */
#ifndef MS_RUNTIME_STD_HTTP_SERVE_H
#define MS_RUNTIME_STD_HTTP_SERVE_H

#include <stdatomic.h>

#include "base/list.h"
#include "runtime/core/task.h"
#include "runtime/std/http_h1.h"
#include "runtime/std/http_wire.h"
#include "runtime/std/ws_session.h"

/* SIZE_MAX: no limit. Times are nanoseconds, negative for none. */
typedef struct MsServeLimits {
  size_t admission; /* requests handled at once */
  size_t body;
  size_t response;
  size_t header;
  int64_t timeout_ns;
  int64_t grace_ns; /* negative: wait for ever; 0: cancel at once */
} MsServeLimits;

typedef struct MsExchange MsExchange;

/* How a handler ended. */
typedef enum MsHandlerEnd { MS_HANDLER_OK, MS_HANDLER_ERROR } MsHandlerEnd;
/* Runs the program's handler on `exchange`; a fault or a stop leaves by a jump the caller's task guards. */
typedef MsHandlerEnd (*MsServeHandler)(void *context, MsExchange *exchange);

/* Runs the server handshake on a stream that was just accepted; sets `*h2` when HTTP/2 was negotiated. The
 * stream is closed by the caller on failure. */
typedef uint8_t (*MsServeSecure)(void *context, MsWsTransport *io, int64_t timeout_ns, bool *h2,
                                 MsString *err);

/* What every worker of one `serve` call shares. */
typedef struct MsServeShared {
  atomic_int refs;
  MsServeLimits limits;
  atomic_size_t admitted;
  MsServeHandler handler;
  void *handler_context;
  void (*handler_release)(void *context);
  MsServeSecure secure; /* NULL: plain connections */
  void *secure_context;
  void (*secure_release)(void *context);
} MsServeShared;

MsServeShared *ms_serve_shared_new(const MsServeLimits *limits, MsServeHandler handler, void *context,
                                   void (*release)(void *));
MsServeShared *ms_serve_shared_retain(MsServeShared *shared);
void ms_serve_shared_release(MsServeShared *shared);

typedef struct MsServeWorker MsServeWorker;
MsServeWorker *ms_serve_worker_new(MsServeShared *shared);
/* Serves `stream` (taken) in a task of the worker; `secure` streams are already past their handshake. */
void ms_serve_worker_adopt(MsServeWorker *worker, const MsWsTransport *stream, bool h2);
/* Drains: idle connections close at once, requests in flight finish within the grace period, the rest are
 * cancelled. Frees the worker. */
void ms_serve_worker_close(MsServeWorker *worker);

/* ---- exchanges (http_serve_exchange.c) ---- */

/* The handle object natives take; each retain is one owner. */
MsObj *ms_exchange_handle(MsExchange *exchange);

#endif
