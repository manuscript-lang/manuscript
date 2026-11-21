/* Serving HTTP/2 on a connection row: the loop that moves bytes between the row and an h2conn.h connection, and the
 * calls a request handler makes on its stream. It sits on conn_io.h (bytes) and h2conn.h (streams) and knows nothing
 * of exchanges: the server's exchange layer starts a handler task per request and calls these.
 *
 * Tasks. The connection task runs ms_h2_serve_run: it owns reading. Handler tasks never read the socket; they
 * park on their stream (a token each) until the connection task has events for it. Writing is shared: whichever
 * task produced output flushes it, one at a time (a flush in progress picks up what others add), so the bytes of
 * two tasks never interleave. A flush that fails or is cancelled leaves the connection closed.
 *
 * `deadline_ns` is an absolute ms_sys_monotonic_ns time, or negative for none. A call on a stream whose
 * connection has gone away gives MS_NET_CLOSED; a stream the peer reset gives MS_NET_RESET.
 */
#ifndef MS_NET_H2_SERVE_H
#define MS_NET_H2_SERVE_H

#include <stddef.h>
#include <stdint.h>

#include "conn_io.h"
#include "h2conn.h"

typedef struct MsH2Serve MsH2Serve;

typedef struct MsH2ServeHooks {
    void *context;
    /* A request head arrived on `stream`. Called on the connection task, so it must not park: start a handler task
       and return. The handler ends with ms_h2_serve_release. */
    void (*on_request)(void *context, MsH2Serve *serve, int32_t stream);
    /* How long an idle connection (no stream open) may wait for bytes; 0 for no limit. */
    int64_t idle_ns;
} MsH2ServeHooks;

/* Takes ownership of `h2` (a server MsH2Conn) and hangs the serve state on the row, which frees both when it closes.
 * Returns NULL when out of memory (the caller still owns `h2`) or the id is stale. */
MsH2Serve *ms_h2_serve_new(MsConnTable *table, MsConnId id, MsH2Conn *h2, const MsH2ServeHooks *hooks);

/* One turn of the connection task: a read (parked on the row), the bytes fed to the connection, events dispatched and
 * output flushed. MS_NET_OK to go on; anything else means the connection is over (CLOSED at a clean end, TIMEOUT
 * when idle too long, FAILED after a protocol error, once its GOAWAY is flushed). */
MS_NODISCARD MsNetStatus ms_h2_serve_step(MsH2Serve *serve);
/* The connection task: steps until the connection is over, sends a GOAWAY, wakes every handler, waits for them to
 * release their streams and closes the row (which frees `serve`). Returns why it ended. */
MsNetStatus ms_h2_serve_run(MsH2Serve *serve);
/* Starts a graceful close: a GOAWAY now; streams in flight finish. */
void ms_h2_serve_drain(MsH2Serve *serve);

/* Handler calls. */
/* Body bytes into buffer; `*count` is 0 at the end of the request body. Parks until bytes arrive. */
MS_NODISCARD MsNetStatus ms_h2_stream_read(MsH2Serve *serve, int32_t stream, uint8_t *buffer, size_t capacity,
                                           int64_t deadline_ns, size_t *count);
/* The request head and trailers; NULL before the head or after release. */
const MsH2Head *ms_h2_stream_head(MsH2Serve *serve, int32_t stream);
const MsH2Head *ms_h2_stream_trailers(MsH2Serve *serve, int32_t stream);
/* Sends the response head; with `has_body` write calls follow, else the head ends the stream. */
MS_NODISCARD MsNetStatus ms_h2_stream_respond(MsH2Serve *serve, int32_t stream, const MsH2Nv *nv, size_t nnv, int has_body);
/* Sends all `length` body bytes, parking while the peer's window is full; `end` finishes the body. */
MS_NODISCARD MsNetStatus ms_h2_stream_write(MsH2Serve *serve, int32_t stream, const uint8_t *data, size_t length, int end,
                                            int64_t deadline_ns);
MS_NODISCARD MsNetStatus ms_h2_stream_trailers_send(MsH2Serve *serve, int32_t stream, const MsH2Nv *nv, size_t nnv);
/* Parks until the peer resets the stream or the connection goes away (RESET or CLOSED), or the task is cancelled. */
MsNetStatus ms_h2_stream_wait_gone(MsH2Serve *serve, int32_t stream);
MsNetStatus ms_h2_stream_reset(MsH2Serve *serve, int32_t stream, uint32_t code);
/* The handler is done (NO_ERROR code 0 after a complete exchange). Must be called exactly once per request. */
void ms_h2_serve_release(MsH2Serve *serve, int32_t stream, uint32_t code);

#endif
