/* HTTP/2 on nghttp2 over memory buffers, like tls.h: this layer never touches a socket. The caller feeds the bytes
   it received (after TLS, if any) to ms_h2_input, sends what ms_h2_output returns, and reads what happened as
   events. Header names and values and body bytes of an event are spans into the session's arena, valid until the
   event queue is drained (ms_h2_next returns 0). */
#ifndef MS_NET_H2_H
#define MS_NET_H2_H
#include <stddef.h>
#include <stdint.h>

typedef struct MsH2 MsH2;
typedef struct { uint32_t off, len; } MsH2Span;
typedef struct { MsH2Span name, value; } MsH2Field;

/* A header or trailer field the caller sends. Pointers are copied by the call. */
typedef struct { const char *name; size_t name_len; const char *value; size_t value_len; } MsH2Nv;

enum { MS_H2_HEADERS = 1, MS_H2_DATA, MS_H2_RESET, MS_H2_CLOSED, MS_H2_GOAWAY };

typedef struct {
    int type;
    int32_t stream;
    uint8_t end_stream;     /* HEADERS and DATA: the peer will send nothing more on this stream */
    uint32_t error_code;    /* RESET, CLOSED, GOAWAY */
    const MsH2Field *fields; /* HEADERS: nfields entries */
    uint32_t nfields;
    MsH2Span data;        /* DATA */
} MsH2Event;

typedef struct {
    uint32_t max_concurrent_streams; /* 0: nghttp2's default (unlimited), use 100 for servers */
    uint32_t max_header_list_size;   /* 0: nghttp2's default */
} MsH2Limits;

MsH2 *ms_h2_new(int server, const MsH2Limits *limits);
void ms_h2_free(MsH2 *h);

/* Bytes from the network. Returns the bytes consumed (all, unless the connection failed) or -1 after a fatal
   protocol error, when the output holds a GOAWAY to send before closing. */
long ms_h2_input(MsH2 *h, const void *buf, size_t n);
/* Bytes to send. Returns the count copied (0 when nothing is pending). */
long ms_h2_output(MsH2 *h, void *buf, size_t cap);
/* 1 while output is pending or the session still wants to read or write, 0 once it can be closed. */
int ms_h2_alive(MsH2 *h);

/* Next event; 0 when none. */
int ms_h2_next(MsH2 *h, MsH2Event *ev);
const char *ms_h2_arena(const MsH2 *h);

/* Client: opens a stream with a request; the body (copied) is sent when body_len > 0. Returns the stream id or -1. */
int32_t ms_h2_submit_request(MsH2 *h, const MsH2Nv *nv, size_t nnv, const void *body, size_t body_len);
/* Server: answers a stream; the body is copied and sent as flow control allows. Returns 0 or -1. */
int ms_h2_submit_response(MsH2 *h, int32_t stream, const MsH2Nv *nv, size_t nnv, const void *body, size_t body_len);
int ms_h2_reset(MsH2 *h, int32_t stream, uint32_t error_code);
int ms_h2_goaway(MsH2 *h, uint32_t error_code);

#endif
