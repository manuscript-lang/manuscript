/* runtime/std/http_serve_internal.h: the structures behind http_serve.h, shared by the connection loop, the
 * exchange and the natives. */
#ifndef MS_RUNTIME_STD_HTTP_SERVE_INTERNAL_H
#define MS_RUNTIME_STD_HTTP_SERVE_INTERNAL_H

#include "runtime/std/http_serve.h"

typedef struct MsServeConn MsServeConn;

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
  MsTaskHandle task;
};

struct MsServeWorker {
  MsServeShared *shared;
  MsServeConn *conns;
  size_t count;
  bool closing;
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

/* ---- exchange (http_serve_exchange.c) ---- */

/* What a parsed request becomes; takes the head's strings and fields. */
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

/* Completes the request after its handler ended (`failure`: 0 ok, 1 error, 2 fault, 3 timed out or stopped);
 * writes what the response still lacks and reports whether the connection stays open. */
bool ms_exchange_finish(MsExchange *exchange, int failure);

#endif
