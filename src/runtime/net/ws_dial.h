/* The client side of a WebSocket connection over a connection the caller already dialed (TLS included): sends the
 * upgrade request, reads the answer and hands back the message session. The caller owns the address, the network
 * policy and the TLS (the connection is a ConnH of conn_object.h); this adds only the handshake. */
#ifndef MS_NET_WS_DIAL_H
#define MS_NET_WS_DIAL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "headers.h"
#include "ms_rt/safe.h"
#include "ws_socket.h"

typedef struct MsWsDial {
    MsBytes authority;           /* the Host field: host[:port] */
    MsBytes target;              /* the request target: path and query, at least "/" */
    const MsBytes *protocols;    /* subprotocols to offer, in order; each an HTTP token */
    size_t protocol_count;
    const MsHeaders *headers;    /* the caller's fields, or NULL */
    bool compression;            /* offer permessage-deflate */
    uint64_t max_message_bytes;  /* UINT64_MAX for no limit */
} MsWsDial;

/* Does the handshake on `conn` within `deadline_ns` (absolute, negative for none). On MS_WSS_OK `*out` is a session
* holding its own handle on the connection (alias); the caller keeps and drops theirs. MS_WSS_INVALID_INPUT: a field the caller may
 * not set (Host, Upgrade, Connection, Sec-WebSocket-*), a bad name, value or subprotocol. MS_WSS_FAILED: `*why` is a
 * static text, for a refused or malformed answer. MS_WSS_CLOSED, MS_WSS_TIMEOUT, MS_WSS_CANCELLED as in ws_socket.h.
 * The connection is not closed on failure; the caller closes it. */
MS_NODISCARD MsWsStatus ms_ws_dial(const MsObj *conn, const MsWsDial *dial, int64_t deadline_ns, MsWsSocket **out,
                                   const char **why);

#endif
