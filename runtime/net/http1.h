/* HTTP/1 request heads on llhttp. A head is offsets into the caller's read buffer: nothing is copied, and the
   buffer must stay unchanged until the handler is done with the head. */
#ifndef MS_NET_HTTP1_H
#define MS_NET_HTTP1_H
#include <stddef.h>
#include <stdint.h>

/* A byte range of the read buffer. */
typedef struct { uint32_t off, len; } ms_span;
typedef struct { ms_span name, value; } ms_h1_field;

typedef struct {
    uint8_t method;      /* llhttp method code */
    uint8_t minor;       /* 0 or 1 */
    uint16_t status;     /* when BAD: the status to answer */
    uint32_t nfields;
    uint32_t head_len;   /* bytes of the head, blank line included */
    ms_span target;
    ms_h1_field *fields; /* caller storage, capacity passed to parse */
} ms_h1_request;

enum { MS_H1_PARTIAL = 0, MS_H1_COMPLETE = 1, MS_H1_BAD = 2 };

/* Parses one request head from buf[0..len). On COMPLETE, `out` holds the head. On BAD, out->status is the
   status to send (400, 431, 501). len above 4 GiB is refused. head_limit bounds the head; nothing is
   allocated. */
int ms_h1_parse_request(const char *buf, size_t len, size_t head_limit, ms_h1_request *out, uint32_t field_cap);

#endif
