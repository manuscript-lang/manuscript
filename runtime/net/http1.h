/* HTTP/1 request heads on llhttp. A head is offsets into the caller's read buffer: nothing is copied, and the
   buffer must stay unchanged until the handler is done with the head. */
#ifndef MS_NET_HTTP1_H
#define MS_NET_HTTP1_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "ms_rt/safe.h"

/* A byte range of the read buffer. */
typedef struct { uint32_t off, len; } MsSpan;
typedef struct { MsSpan name, value; } MsH1Field;

typedef struct {
    uint8_t method;      /* llhttp method code */
    uint8_t minor;       /* 0 or 1 */
    uint16_t status;     /* when BAD: the status to answer */
    uint8_t keep_alive;  /* the connection can carry another request once this one is answered */
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

/* A response head, as offsets into the read buffer like a request head. */
typedef struct {
    uint16_t status;
    uint8_t minor;
    uint8_t keep_alive; /* the connection can carry another exchange once the body is read */
    uint32_t nfields;
    uint32_t head_len;  /* bytes of the head, blank line included */
    MsSpan reason;
    MsH1Field *fields;  /* caller storage, capacity passed to parse */
} MsH1Response;

/* Follows one response from its head through its body. The caller provides the storage and passes it to the
   functions below; it holds the llhttp parser (opaque here, so users of this header need no llhttp include path),
   so it must not move while a response is being read. */
enum { MS_H1_READER_BYTES = 128 };
typedef struct {
    _Alignas(8) unsigned char opaque[MS_H1_READER_BYTES];
} MsH1Reader;

/* Like ms_h1_parse_request, and on COMPLETE starts `reader` on the request's body, so ms_h1_read_body returns it with
   the chunked or length framing removed. A request with neither a length nor chunked framing has no body: the first
   ms_h1_read_body call answers DONE, even with no bytes. */
int ms_h1_parse_request_body(MsH1Reader *reader, const char *buf, size_t len, size_t head_limit, MsH1Request *out,
                             uint32_t field_cap);

/* Call after copying or moving a reader that ms_h1_parse_request_body or ms_h1_parse_response started: the parser
   keeps a pointer to its state, which must follow the copy. */
void ms_h1_reader_moved(MsH1Reader *reader);

/* Parses one response head from buf[0..len) and starts `reader` on its body. PARTIAL: keep the bytes and call again
   with more (the reader restarts each time). `head_request` is set when the request was HEAD. A 1xx head is
   COMPLETE like any other (the caller drops it and parses the next). */
int ms_h1_parse_response(MsH1Reader *reader, const char *buf, size_t len, size_t head_limit, MsH1Response *out,
                         uint32_t field_cap, int head_request);

/* What reading a body found. DATA: `*data` is a span of body bytes (chunk framing removed) inside `buf`. */
enum { MS_H1_BODY_DATA = 0, MS_H1_BODY_NEED_MORE = 1, MS_H1_BODY_DONE = 2, MS_H1_BODY_BAD = 3 };

/* Feeds body bytes. `*used` is how many of `buf` were consumed, whatever the result; on DATA call again with the
   rest, even when none is left, until it says NEED_MORE or DONE. */
int ms_h1_read_body(MsH1Reader *reader, const char *buf, size_t len, MsSpan *data, size_t *used);

/* The peer closed the stream: DONE when that ends a body that had no length, else BAD (a truncated body). */
int ms_h1_read_body_eof(MsH1Reader *reader);

/* The first field of `fields` called `name` (ASCII case-insensitive); NULL when there is none. Spans are offsets into
   `base`. */
const MsH1Field *ms_h1_find_field(const char *base, const MsH1Field *fields, uint32_t count, MsBytes name);
/* Whether the comma-separated `value` lists `token` (ASCII case-insensitive, blanks around a token ignored). */
bool ms_h1_value_has_token(MsBytes value, MsBytes token);

/* Whether `text` is a non-empty HTTP token: a field name or a method. */
bool ms_h1_is_token(MsBytes text);

/* The request line: method SP target SP HTTP/1.1 CRLF. A method that is not a token, or a target holding a space or
   a control byte, returns -2; nothing is written. */
int ms_h1_write_request_line(char *dst, size_t cap, size_t *used, const char *method, size_t method_len,
                             const char *target, size_t target_len);

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

#endif
