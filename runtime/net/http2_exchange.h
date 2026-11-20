/* An HTTP/2 exchange on a connection row, the h2 twin of http1_exchange.h: one request out, one response head and a
 * body stream back. The row is already connected with TLS and ALPN "h2" (dial.h, tls.h). The caller owns the h2
 * connection (`session`, from ms_h2conn_new(0, NULL)) and keeps it for as long as the row lives, so the exchanges
 * that follow run as further streams on it; closing the body ends the stream and leaves the row open (a stream
 * not read to its end is reset). One exchange is open on a row at a time: pooling and multiplexing several requests
 * over one connection is policy for the caller to build on ms_h2conn_*. A failed call or body read leaves the
 * session unusable; the caller closes the row.
 *
 * The request is the same MsHttpRequest as HTTP/1: Host is sent as :authority, the scheme comes from the row (https
 * with TLS), and the same fields are refused (Host, Content-Length, Transfer-Encoding) plus the connection-specific
 * ones HTTP/2 forbids. Field names are sent in lower case.
 */
#ifndef MS_NET_HTTP2_EXCHANGE_H
#define MS_NET_HTTP2_EXCHANGE_H

#include "conn_io.h"
#include "h2conn.h"
#include "http_client.h"

MS_NODISCARD MsNetStatus ms_http2_exchange(MsConnTable *table, MsConnId id, MsH2Conn *session, const MsHttpRequest *request, int64_t deadline_ns,
                                           MsHttpResponse *response, MsHttpBody **body);

#endif
