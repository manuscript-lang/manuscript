/* The HTTP client's exchange, shared by the HTTP/1 and HTTP/2 paths: one request out, one response head and a body
   stream back. An exchange is one hop: it follows no redirects, keeps no cookies and decodes no content-encoding;
   that policy is in the standard library .ms files. The request and response heads use the MsH1Field spans of http1.h, so both
   protocols hand a head over without copying it. */
#ifndef MS_NET_HTTP_CLIENT_H
#define MS_NET_HTTP_CLIENT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "http1.h"
#include "ms_rt/safe.h"

typedef struct {
    MsBytes method;     /* "GET" */
    MsBytes authority;  /* host[:port], sent as Host (HTTP/1) or :authority (HTTP/2) */
    MsBytes target;     /* path and query, "/" at least */
    MsBytes head;       /* the bytes `fields` points into */
    const MsH1Field *fields;
    uint32_t nfields;
    MsBytes body;       /* sent with a content-length; empty for none */
} MsHttpRequest;

typedef struct {
    uint16_t status;
    MsBytes head;       /* the bytes `fields` points into; valid until the body is closed */
    const MsH1Field *fields;
    uint32_t nfields;
} MsHttpResponse;

/* Whether a caller's request field is one the exchange writes itself (Host, Content-Length, Transfer-Encoding) or, for
   HTTP/2, one the protocol forbids (Connection, Keep-Alive, Proxy-Connection, Upgrade). Such a request is refused
   whole, not rewritten. */
bool ms_http_field_refused(MsBytes name, bool http2);

/* A response body, read until the stream ends. HTTP/1 and HTTP/2 each embed this as the first member of their own
   body type and set the two functions. */
typedef struct MsHttpBody MsHttpBody;
struct MsHttpBody {
    /* Reads up to out.len decoded bytes (chunk framing and HTTP/2 frames removed) into out and sets *n; *n == 0 with
       a return of 0 is the end of the body. Returns 0, or a negative MsNetStatus (timeout, cancelled, reset,
       failed) as in conn_io.h. deadline_ns is an absolute monotonic time, negative for none. */
    int (*read)(MsHttpBody *body, MsBytesMut out, int64_t deadline_ns, size_t *n);
    /* Ends the exchange: a body read to its end returns its connection for reuse, any other closes it. */
    void (*close)(MsHttpBody *body);
};

#endif
