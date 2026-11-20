/* An HTTP/2 exchange on a connection row, the h2 twin of http1_exchange.h: one request out, one response head and a
 * body stream back. The row is already connected with TLS and ALPN "h2" (dial.h, tls.h). One exchange owns the row
 * and its h2 connection; closing the body ends the connection. Pooling and multiplexing several requests over one
 * connection is policy for the caller (the standard library) to build on ms_h2conn_*.
 *
 * The request is the same MsHttpRequest as HTTP/1: Host is sent as :authority, the scheme comes from the row (https
 * with TLS), and the same fields are refused (Host, Content-Length, Transfer-Encoding) plus the connection-specific
 * ones HTTP/2 forbids. Field names are sent in lower case.
 */
#ifndef MS_NET_HTTP2_EXCHANGE_H
#define MS_NET_HTTP2_EXCHANGE_H

#include "conn_io.h"
#include "http_client.h"

MS_NODISCARD MsNetStatus ms_http2_exchange(MsConnTable *table, MsConnId id, const MsHttpRequest *request, int64_t deadline_ns,
                                           MsHttpResponse *response, MsHttpBody **body);

#endif
