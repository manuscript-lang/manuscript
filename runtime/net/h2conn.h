/* One HTTP/2 connection with its streams, for both ends. It sits on the sans-io nghttp2 layer (h2.h) and, like it,
   never touches a socket: the caller moves bytes between the network (after TLS, if any) and ms_h2conn_input and
   ms_h2conn_output.

   What this layer adds to h2.h is the per-stream state a request or response needs between events: the head
   (pseudo-header values and regular fields), the trailers, the body bytes received and not yet read, and an opaque
   word for the caller. Header validity (pseudo-header order, lowercase names, connection-specific fields,
   content-length against the bytes that arrived) is checked by nghttp2 before a head reaches this layer; a stream
   that fails is reset there and appears as MS_H2C_RESET.

   A stream is one request/response exchange. The server side creates it when a request head arrives, the client
   side when ms_h2conn_open sends one. It lives until ms_h2conn_release, so a handler can still read what arrived
   before a reset. Every pointer a head hands out stays valid until that release. */
#ifndef MS_NET_H2CONN_H
#define MS_NET_H2CONN_H
#include <stddef.h>
#include <stdint.h>
#include "h2.h"
#include "ms_rt/safe.h"

typedef struct MsH2Conn MsH2Conn;

typedef struct { MsBytes name, value; } MsH2Header;

/* A request head (server: method, scheme, authority, path), a response head (client: status), or trailers. Absent
   pseudo-headers are empty. `fields` holds the regular fields in the order received. */
typedef struct {
    MsBytes method, scheme, authority, path;
    uint32_t status; /* 0 when there is no :status */
    const MsH2Header *fields;
    size_t nfields;
} MsH2Head;

/* What happened. The caller wakes whoever waits on `stream`.
   HEAD: the request (server) or final response (client) head is available; interim 1xx responses are dropped.
   READABLE: body bytes, the end of the body, or trailers arrived.
   WRITABLE: room to send again after ms_h2conn_send accepted fewer bytes than offered.
   RESET: the stream was reset or refused; `code` is the HTTP/2 error code.
   GOAWAY: the peer is closing the connection; `stream` is the last stream it processed, `code` the error. */
enum { MS_H2C_HEAD = 1, MS_H2C_READABLE, MS_H2C_WRITABLE, MS_H2C_RESET, MS_H2C_GOAWAY };
typedef struct { int type; int32_t stream; uint32_t code; } MsH2ConnEvent;

/* Stream state bits from ms_h2conn_state. */
enum {
    MS_H2S_HEAD = 1,    /* the head arrived */
    MS_H2S_ENDED = 2,   /* the peer finished sending; the body is all received (read it with ms_h2conn_read) */
    MS_H2S_RESET = 4,   /* reset or refused; see ms_h2conn_reset_code */
    MS_H2S_CLOSED = 8,  /* nothing more will cross the wire */
    MS_H2S_TRAILERS = 16
};

/* `limits->max_concurrent_streams` bounds the streams a peer may have open on this side (default 100) and sizes
   the stream table. Returns NULL when out of memory. The connection owns everything it hands out. */
MsH2Conn *ms_h2conn_new(int server, const MsH2Limits *limits);
void ms_h2conn_free(MsH2Conn *c);

/* Wire bytes in: returns the bytes consumed, or -1 after a fatal protocol error (GOAWAY queued: drain output, then
   close). Events are queued; bytes beyond one buffer's worth are the caller's to pace. */
long ms_h2conn_input(MsH2Conn *c, const void *buf, size_t n);
/* Wire bytes out: the count copied into buf, 0 when nothing is pending. Call after any call that sends. */
long ms_h2conn_output(MsH2Conn *c, void *buf, size_t cap);
int ms_h2conn_pending(MsH2Conn *c); /* 1 when output is waiting */
int ms_h2conn_alive(MsH2Conn *c);   /* 0 once the connection can be closed */
/* 1 when no stream is open and nothing is waiting to be sent. */
int ms_h2conn_idle(MsH2Conn *c);
/* Streams not yet closed on the wire. */
uint32_t ms_h2conn_open_streams(const MsH2Conn *c);
/* Client: 1 when another request can be opened now. Server: 1 until the connection is going away. */
int ms_h2conn_usable(MsH2Conn *c);

int ms_h2conn_next(MsH2Conn *c, MsH2ConnEvent *event); /* 0 when none */

/* Calls fn for every stream the connection still holds (open, or closed and not yet released), in no order. fn must
   not release streams. */
/* `user` points at the two words of the stream: the handler's (ms_h2conn_user) and the watcher's (ms_h2conn_watch). */
void ms_h2conn_for_each(MsH2Conn *c, void (*fn)(void *context, int32_t stream, const uint64_t *user), void *context);

/* Per-stream queries; NULL or 0 for an unknown or released stream. The head and trailers are valid until release. */
const MsH2Head *ms_h2conn_head(const MsH2Conn *c, int32_t stream);
const MsH2Head *ms_h2conn_trailers(const MsH2Conn *c, int32_t stream);
unsigned ms_h2conn_state(const MsH2Conn *c, int32_t stream);
uint32_t ms_h2conn_reset_code(const MsH2Conn *c, int32_t stream);
/* The caller's word for the stream (a parked task, an exchange): starts as 0. */
uint64_t *ms_h2conn_user(MsH2Conn *c, int32_t stream);
/* A second word, for a task that waits for the stream to go away while the first one works on it. */
uint64_t *ms_h2conn_watch(MsH2Conn *c, int32_t stream);

/* Body bytes into buf: the count (> 0), or 0 when none are queued (check ms_h2conn_state for ENDED or RESET), or
   -1 for an unknown stream. Reading returns the bytes to the peer's windows, so output may become pending. */
long ms_h2conn_read(MsH2Conn *c, int32_t stream, void *buf, size_t cap);

/* Client: sends a request and opens its stream. nv holds the pseudo-headers (:method, :scheme, :authority, :path)
   and fields; has_body says ms_h2conn_send calls follow. Returns the stream id, or -1 when the connection cannot
   take another request now (ms_h2conn_usable is 0) or on failure. */
int32_t ms_h2conn_open(MsH2Conn *c, const MsH2Nv *nv, size_t nnv, int has_body);
/* Server: sends the response head of a request stream; has_body says ms_h2conn_send calls follow, else the head
   ends the stream. Returns 0 or -1. */
int ms_h2conn_respond(MsH2Conn *c, int32_t stream, const MsH2Nv *nv, size_t nnv, int has_body);
/* Body bytes (copied) for a stream opened or answered with has_body; `end` finishes the body once everything was
   accepted. Returns the bytes accepted (fewer than offered: wait for MS_H2C_WRITABLE) or -1. */
long ms_h2conn_send(MsH2Conn *c, int32_t stream, const void *data, size_t n, int end);
int ms_h2conn_trailers_send(MsH2Conn *c, int32_t stream, const MsH2Nv *nv, size_t nnv);
int ms_h2conn_reset(MsH2Conn *c, int32_t stream, uint32_t code);
/* Starts a graceful close: a GOAWAY, after which streams in flight finish and no new ones are accepted. */
int ms_h2conn_goaway(MsH2Conn *c, uint32_t code);
/* The exchange is over. Bytes not read go back to the peer's windows; a stream where either side has not finished
   (the peer still sending, or we have not ended our side) is reset with `code`, so pass NO_ERROR (0) for an
   exchange that completed and an error code for one that was abandoned. The stream's memory is freed when it is closed
   on the wire, which may be now. */
void ms_h2conn_release(MsH2Conn *c, int32_t stream, uint32_t code);

#endif
