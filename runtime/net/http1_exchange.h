/* An HTTP/1 exchange on a connection row: one request out, one response head and a body stream back (http_client.h).
 * The row is already connected, and TLS if the scheme asks for it (dial.h). The exchange follows no redirects, keeps no
 * cookies and decodes no content-encoding; the body it hands back is the bytes of the message body with the chunk
 * framing removed.
 *
 * Every call parks the running task on the row (conn_io.h). On the first failure of a read the exchange is over; the
 * caller closes the body, which closes the row.
 */
#ifndef MS_NET_HTTP1_EXCHANGE_H
#define MS_NET_HTTP1_EXCHANGE_H

#include <stddef.h>
#include <stdint.h>

#include "conn_io.h"
#include "http1.h"
#include "http_client.h"

enum { MS_HTTP1_MAX_FIELDS = 128, MS_HTTP1_HEAD_LIMIT = 64 * 1024 };

/* A response head read from a row: the bytes (kept for the spans in `response`) and any bytes after the head. */
typedef struct MsHttp1Head {
    uint8_t *bytes;     /* owned; `length` bytes read, the head first */
    size_t length, capacity;
    MsH1Response response;
    MsH1Field fields[MS_HTTP1_MAX_FIELDS];
    MsH1Reader reader;  /* positioned at the start of the body */
} MsHttp1Head;

/* Reads a response head into `head`, skipping interim 1xx heads other than 101. `head_request` is set for a reply to
 * HEAD. A head over MS_HTTP1_HEAD_LIMIT, or one that is malformed, is MS_NET_FAILED. Release with ms_http1_head_free. */
MS_NODISCARD MsNetStatus ms_http1_read_head(MsConnTable *table, MsConnId id, int head_request, int64_t deadline_ns,
                                            MsHttp1Head *head);
void ms_http1_head_free(MsHttp1Head *head);

/* Sends `request` on the row and reads the response head. On MS_NET_OK `*response` describes it (its spans point into
 * memory the body owns) and `*body` reads the message body; closing the body ends the exchange and closes the row. On
 * failure nothing is allocated and the row is left open for the caller to close. The request's own fields are written
 * after Host and Content-Length; a field named either of those, or Transfer-Encoding, is refused (MS_NET_FAILED). */
MS_NODISCARD MsNetStatus ms_http1_exchange(MsConnTable *table, MsConnId id, const MsHttpRequest *request, int64_t deadline_ns,
                                           MsHttpResponse *response, MsHttpBody **body);

#endif
