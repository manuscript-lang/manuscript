/* runtime/std/http_serve_internal.h: the structures behind http_serve.h, shared by the connection loop, the
 * exchange and the natives. */
#ifndef MS_RUNTIME_STD_HTTP_SERVE_INTERNAL_H
#define MS_RUNTIME_STD_HTTP_SERVE_INTERNAL_H

#include "base/strbuild.h"
#include "runtime/std/h2.h"
#include "runtime/std/http_serve.h"

typedef struct MsServeConn MsServeConn;
typedef struct MsH2Conn MsH2Conn;
typedef struct MsH2Stream MsH2Stream;
typedef struct MsServeIdle MsServeIdle;

struct MsServeConn {
  MsServeWorker *worker;
  MsServeConn *prev;
  MsServeConn *next;
  MsWsTransport io;
  MsBytes in; /* bytes read and not yet consumed start at `pos` */
  size_t pos;
  bool idle; /* between requests: closing it loses nothing */
  bool eof;
  bool h2;
  MsStrBuild head; /* the response head and first body bytes of the exchange in flight; its capacity lasts the connection */
  MsTaskHandle task;
  size_t listed_at;  /* its place in the idle list while it waits for a request (http_serve_steal.c) */
  bool listed;
  MsH2Conn *owner;   /* an HTTP/2 connection's state, once its task has made it */
  MsH2 *session;     /* the HTTP/2 session a take moved here, for the task to continue with */
  bool resumed;      /* taken from another thread's connection: its handshake is done */
  bool taken;        /* another thread took the connection: its task ends without closing it */
  bool idle_swept;   /* worker close already closed it while it was idle */
  bool cancelled;    /* worker close already cancelled its task */
};

struct MsServeWorker {
  MsServeShared *shared;
  MsServeConn *conns;
  size_t count;
  bool closing;
  MsServeIdle *idle; /* NULL when connections of this worker cannot be taken */
};

struct MsExchange {
  MsObj header;
  int refs;
  MsServeConn *conn; /* NULL once the request ended: later calls are CLOSED */
  const MsServeLimits *limits;
  bool tls;
  MsString method;
  MsString path;
  MsString query;
  const char *protocol;
  MsHeaders *headers;
  MsH1Body body;
  MsBytes decoded;
  size_t decoded_pos;
  size_t remaining_read;
  size_t remaining_write;
  MsHeaders *staged; /* handler headers, written with the first body bytes */
  uint16_t status;
  uint8_t minor;
  bool body_over_limit;
  bool body_malformed;
  bool expect_continue;
  bool is_head;
  bool sent;
  bool response_complete;
  bool head_written;
  bool chunked;
  bool close_conn;
  bool closed;
  bool upgraded;
  bool rejected;
  MsH2Stream *h2;         /* the HTTP/2 stream this exchange answers; NULL on HTTP/1 */
  MsWsSession *websocket; /* after an upgrade; closed when the handler returns */
  int failure;            /* how the handler ended: 0 ok, 1 error, 2 fault, 3 out of time or stopped */
  int64_t deadline;       /* on ms_sched_now's clock; MS_NO_DEADLINE: none */
};

/* Time left until `deadline` in nanoseconds, negative when there is none. */
static inline int64_t ms_serve_left(int64_t deadline) {
  if (deadline == MS_NO_DEADLINE) {
    return -1;
  }
  const int64_t left = deadline - ms_sched_now();
  return left > 0 ? left : 0;
}

/* ---- connection (http_serve_conn.c) ---- */

MsSpan ms_serve_unread(const MsServeConn *conn);
void ms_serve_consume(MsServeConn *conn, size_t n);
/* Reads more input: OK, NONE at the end of the stream, TIMED_OUT, CLOSED or FAILED. */
uint8_t ms_serve_fill(MsServeConn *conn, int64_t deadline, MsString *err);
uint8_t ms_serve_send(MsServeConn *conn, MsSpan data, int64_t deadline, MsString *err);
/* `http.Error`: a plain text answer with a Date field; `close` adds Connection: close. */
void ms_serve_error_bytes(MsStrBuild *out, uint16_t status, const char *message, bool close);
bool ms_serve_body_allowed(int64_t status);
void ms_serve_date_line(MsStrBuild *out);

/* Runs the handler in a guard on the running task: 0 it returned, 1 it returned an error, 2 it faulted, 3 it
 * ran out of time or was stopped. */
int ms_serve_call_handler(MsServeShared *shared, MsExchange *exchange);
void ms_serve_conn_close(MsServeConn *conn);
/* Takes one request slot of the serving's admission limit; false when none is free. Return it by decrementing
 * `admitted`. */
bool ms_serve_admit(MsServeShared *shared);

/* Serves `stream` (taken) and the request bytes already read from it, in a task of `worker` (a connection another
 * worker's thread took): closes the stream and returns false when the worker is closing. */
bool ms_serve_worker_resume(MsServeWorker *worker, const MsWsTransport *stream, MsBytes first, MsH2 *session);

/* ---- taking idle connections from a held-up thread (http_serve_steal.c) ---- */

/* The idle list of `worker` (on the calling thread's isolate), registered so the watcher can send a resting worker
 * of the same server to take from it; NULL when the server cannot (one isolate). */
MsServeIdle *ms_serve_idle_open(MsServeWorker *worker);
/* Unregisters and releases the list; takers that still hold it find no worker. */
void ms_serve_idle_close(MsServeIdle *idle);
/* Frees the registry table once no list is open (a process that balances its books at exit). */
void ms_serve_idle_release_registry(void);
/* The connection waits for the first byte of a request: another thread may take it. */
void ms_serve_idle_list(MsServeConn *conn);
/* The wait ended. Whether another thread took the connection meanwhile (then it is theirs and this task ends
 * without closing it). Also safe for a connection that was never listed. */
bool ms_serve_idle_unlist(MsServeConn *conn);
/* Whether another thread took the connection (it is theirs to close). */
bool ms_serve_idle_taken(MsServeConn *conn);

/* ---- HTTP/2 (http_serve_h2.c, http_serve_h2_exchange.c) ---- */

struct MsH2Stream {
  uint32_t id;
  MsH2Conn *owner;
  MsExchange *exchange;
  uint64_t token; /* the handler parks here for body bytes, window and resets */
  MsBytes inbox;  /* request body bytes from `pos` */
  size_t pos;
  bool end_in; /* the peer's side ended */
  bool reset;  /* the peer reset the stream, or the connection ended */
  MsTaskHandle task;
};

struct MsH2Conn {
  MsServeConn *conn;
  MsH2 *h2;
  int refs; /* the pump, the writer and each stream */
  bool dead;
  bool writer_done;
  _Atomic bool writer_parked; /* the writer waits with nothing to send (read by a thread that takes the connection) */
  bool handed;                /* a take moved the session to another thread: the writer ends without touching it */
  uint64_t out_token; /* the writer parks here until output is queued */
  MsH2Stream **streams;
  size_t count;
  size_t capacity;
};

/* Serves an HTTP/2 connection until it ends (the connection task's body). */
void ms_serve_h2(MsServeConn *conn);
void ms_h2_wake(uint64_t token);
/* Whether another thread may take this connection while it waits for a frame: no stream, no output queued, and
 * the writer parked (http_serve_steal.c). */
bool ms_h2_movable(const MsH2Conn *owner);
/* Queues output for the writer. */
void ms_h2_flush(MsH2Conn *owner);

uint8_t ms_h2x_read(MsExchange *exchange, size_t want, MsBytes *out, MsString *err);
uint8_t ms_h2x_write(MsExchange *exchange, MsSpan data, int64_t content_length, MsString *err);
/* Completes the response of a stream after its handler: whatever the response still lacks. */
void ms_h2x_finish(MsExchange *exchange, int failure, bool late);

/* ---- exchange (http_serve_exchange.c) ---- */

/* What a parsed request becomes; takes the head's strings and fields. */
/* An exchange for an HTTP/2 stream from its request head (names lower-case, pseudo-fields first); NULL with
 * *status and *reason set when the head is refused. */
MsExchange *ms_exchange_new_h2(MsServeConn *conn, MsH2Stream *stream, const MsList *fields, bool end_stream,
                               int64_t deadline, uint16_t *status, const char **reason);
MsExchange *ms_exchange_alloc(MsServeConn *conn, int64_t deadline);
MsExchange *ms_exchange_new(MsServeConn *conn, MsH1Request *head, MsHttpTarget *target, MsH1Framing framing,
                            bool keep_alive, bool expect_continue, int64_t deadline);
void ms_exchange_retain(MsExchange *exchange);
void ms_exchange_release(MsExchange *exchange);
uint8_t ms_exchange_read(MsExchange *exchange, bool has_max, int64_t max, MsBytes *out, MsString *err);
uint8_t ms_exchange_send_headers(MsExchange *exchange, int64_t status, const MsHeaders *headers);
uint8_t ms_exchange_send(MsExchange *exchange, int64_t status, const MsHeaders *headers, MsSpan body,
                         MsString *err);
uint8_t ms_exchange_write(MsExchange *exchange, MsSpan data, MsString *err);
void ms_exchange_close(MsExchange *exchange);
/* The WebSocket handshake: on success the connection belongs to the returned session (one reference). */
uint8_t ms_exchange_upgrade(MsExchange *exchange, const MsSpan *origins, size_t origin_count,
                            const MsSpan *subprotocols, size_t subprotocol_count, bool has_max, int64_t max,
                            MsWsSession **out, MsString *err);

/* The HTTP/2 head fields of the response (:status first, handler fields sorted, date, type sniffed from
 * `first`, length when >= 0). */
size_t ms_exchange_h2_fields(MsExchange *exchange, MsSpan first, int64_t length, MsH2Field **out);
void ms_h2_fields_release(MsH2Field *fields, size_t count);

/* Completes the request after its handler ended (`failure`: 0 ok, 1 error, 2 fault, 3 timed out or stopped);
 * writes what the response still lacks and reports whether the connection stays open. */
bool ms_exchange_finish(MsExchange *exchange, int failure);

#endif
