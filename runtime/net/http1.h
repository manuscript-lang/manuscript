/* HTTP/1 request heads on llhttp. A head is offsets into the caller's read buffer: nothing is copied, and the
   buffer must stay unchanged until the handler is done with the head. */
#ifndef MS_NET_HTTP1_H
#define MS_NET_HTTP1_H
#include <stddef.h>
#include <stdint.h>

/* A byte range of the read buffer. */
typedef struct { uint32_t off, len; } MsSpan;
typedef struct { MsSpan name, value; } MsH1Field;

typedef struct {
    uint8_t method;      /* llhttp method code */
    uint8_t minor;       /* 0 or 1 */
    uint16_t status;     /* when BAD: the status to answer */
    uint32_t nfields;
    uint32_t head_len;   /* bytes of the head, blank line included */
    MsSpan target;
    MsH1Field *fields; /* caller storage, capacity passed to parse */
} MsH1Request;

enum { MS_H1_PARTIAL = 0, MS_H1_COMPLETE = 1, MS_H1_BAD = 2 };

/* Parses one request head from buf[0..len). On COMPLETE, `out` holds the head. On BAD, out->status is the
   status to send (400, 431, 501). len above 4 GiB is refused. head_limit bounds the head; nothing is
   allocated. */
int ms_h1_parse_request(const char *buf, size_t len, size_t head_limit, MsH1Request *out, uint32_t field_cap);

#endif

/* Response writing. All writers append to a caller buffer `dst` of capacity `cap` at `*used` and return 0, or -1
   with nothing written when the output does not fit (the caller grows the buffer and retries). */
int ms_h1_write_status(char *dst, size_t cap, size_t *used, int minor, unsigned status, const char *reason, size_t reason_len);
/* One header line. A name that is empty or holds a byte outside the token set, or a value holding CR, LF or NUL,
   returns -2 (refused: response splitting); nothing is written. */
int ms_h1_write_field(char *dst, size_t cap, size_t *used, const char *name, size_t name_len, const char *value, size_t value_len);
/* The blank line that ends a head. */
int ms_h1_write_head_end(char *dst, size_t cap, size_t *used);
/* One chunk (size line, data, CRLF); n == 0 writes the terminating chunk "0\r\n\r\n". */
int ms_h1_write_chunk(char *dst, size_t cap, size_t *used, const char *data, size_t n);
