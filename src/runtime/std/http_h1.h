/* runtime/std/http_h1.h: the HTTP/1.1 wire format of the server: request heads (on llhttp), body framing,
 * the incremental body decoder and the writers of status lines, fields and chunks. Everything works on byte
 * buffers and never touches a socket (http_h1.c, http_h1_body.c, http_h1_write.c).
 *
 * The head parser is llhttp's strict one: line ends must be CRLF, no obsolete line folding, no invalid field
 * bytes. Methods are llhttp's table, so an extension method is a 400. */
#ifndef MS_RUNTIME_STD_HTTP_H1_H
#define MS_RUNTIME_STD_HTTP_H1_H

#include "base/strbuild.h"
#include "runtime/std/http_headers.h"

enum {
  MS_H1_DEFAULT_HEAD_LIMIT = 1 << 20, /* request line plus fields when no limit is configured */
  MS_H1_MAX_FIELDS = 256              /* more fields than this are refused (431) */
};

/* Why a message was refused: the status a server answers and its text. */
typedef struct MsH1Bad {
  uint16_t status;
  const char *reason; /* static */
} MsH1Bad;

typedef enum MsH1Parse { MS_H1_PARTIAL, MS_H1_COMPLETE, MS_H1_BAD } MsH1Parse;

typedef struct MsH1Request {
  MsString method;
  MsString target;
  uint8_t minor;     /* 0 or 1 */
  MsHeaders *fields; /* canonical names, sorted, as handlers see them; owned */
  size_t length;     /* bytes of the head, including the blank line */
} MsH1Request;

/* Parses a request head from the front of `buf`. `limit` bounds the head (and a partial one). */
MsH1Parse ms_h1_parse_request(MsSpan buf, size_t limit, MsH1Request *out, MsH1Bad *bad);
void ms_h1_request_release(MsH1Request *request);

/* ---- framing ---- */

typedef enum MsH1FramingKind {
  MS_H1_NO_BODY,
  MS_H1_LENGTH,
  MS_H1_CHUNKED,
  MS_H1_UNTIL_CLOSE
} MsH1FramingKind;

typedef struct MsH1Framing {
  MsH1FramingKind kind;
  uint64_t length; /* for MS_H1_LENGTH */
} MsH1Framing;

/* What the server asks of a request head's fields. Spans borrow the fields. */
typedef struct MsH1Scan {
  size_t hosts; /* how many Host fields, and the last one */
  MsSpan host;
  bool expect_continue;
  bool connection_close;
  bool connection_keep_alive;
  bool content_length;
  bool transfer_encoding;
  bool text; /* every value is UTF-8 */
} MsH1Scan;

MsH1Scan ms_h1_scan(const MsHeaders *fields);
/* Whether the connection stays open after this request. */
bool ms_h1_scan_keep_alive(const MsH1Scan *scan, uint8_t minor);
/* Whether a comma-separated field holds `token` (ASCII case-insensitive). */
bool ms_h1_has_token(const MsHeaders *fields, const char *name, const char *token);
/* Whether the connection stays open after a message of this minor version. */
bool ms_h1_keep_alive(uint8_t minor, const MsHeaders *fields);
/* Request body framing; a message with both Transfer-Encoding and Content-Length is refused. */
bool ms_h1_request_framing(uint8_t minor, const MsHeaders *fields, const MsH1Scan *scan, MsH1Framing *out,
                           MsH1Bad *bad);

/* ---- body decoding ---- */

typedef enum MsH1BodyState {
  MS_H1_S_LENGTH,
  MS_H1_S_SIZE,
  MS_H1_S_DATA,
  MS_H1_S_DATA_END,
  MS_H1_S_TRAILER,
  MS_H1_S_DONE,
  MS_H1_S_UNTIL_CLOSE
} MsH1BodyState;

typedef struct MsH1Body {
  MsH1BodyState state;
  uint64_t left;       /* bytes of the fixed length or of the current chunk */
  MsBytes size_line;   /* a chunk size line being collected, owned */
  size_t trailer_line; /* bytes of the trailer line being skipped */
  bool cr;             /* a CR was read and its LF is due */
} MsH1Body;

typedef enum MsH1Progress { MS_H1_MORE, MS_H1_DONE } MsH1Progress;

MsH1Body ms_h1_body_new(MsH1Framing framing);
void ms_h1_body_free(MsH1Body *body);
bool ms_h1_body_is_done(const MsH1Body *body);
/* How many body bytes the next read may take raw (a fixed length, one chunk's data, or until close), so they
 * can bypass ms_h1_body_feed; false between chunks and once the body is finished. */
bool ms_h1_body_raw_room(const MsH1Body *body, uint64_t *room);
/* Whether the raw bytes ahead are the whole rest of the body. */
bool ms_h1_body_is_fixed_length(const MsH1Body *body);
/* Accounts for `n` raw body bytes taken without feed. */
MsH1Progress ms_h1_body_took_raw(MsH1Body *body, size_t n);
/* Consumes `input`, appending body bytes to `out`; *used is the input consumed. A malformed chunked body
 * returns false and *error is its text. */
MS_NODISCARD bool ms_h1_body_feed(MsH1Body *body, MsSpan input, MsBytes *out, size_t *used,
                                  MsH1Progress *progress, const char **error);
/* Whether end of input completes the body (read until close). */
bool ms_h1_body_finish_on_eof(const MsH1Body *body);

/* ---- writers ---- */

/* http.StatusText: empty for an unknown code. */
const char *ms_h1_status_text(uint16_t code);
/* `HTTP/1.1 200 OK\r\n`; an unknown code reads `status code N`. */
void ms_h1_status_line(MsStrBuild *out, uint16_t status);
/* `name: value\r\n` and `name: <n>\r\n`. */
void ms_h1_header_line(MsStrBuild *out, MsSpan name, MsSpan value);
void ms_h1_header_number(MsStrBuild *out, MsSpan name, uint64_t n);
/* One chunk; an empty one writes nothing (the last chunk is MS_H1_LAST_CHUNK). */
void ms_h1_chunk(MsStrBuild *out, MsSpan data);
#define MS_H1_LAST_CHUNK "0\r\n\r\n"
/* A Date value in the format of http.TimeFormat, for Unix seconds. */
void ms_h1_http_date(MsStrBuild *out, int64_t unix_seconds);

#endif
