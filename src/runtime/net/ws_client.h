/* The client side of the WebSocket opening handshake (RFC 6455 4.1): the upgrade request, and the check of the
   101 answer. Frames after it are ws.h. Sans-io: it writes into and reads from caller buffers. */
#ifndef MS_NET_WS_CLIENT_H
#define MS_NET_WS_CLIENT_H
#include <stdbool.h>
#include <stddef.h>
#include "http1.h"
#include "ms_rt/safe.h"

enum { MS_WS_KEY_LEN = 24 };

/* A fresh Sec-WebSocket-Key: 16 random bytes in base64, MS_WS_KEY_LEN characters and a NUL. -1 when the system has
   no randomness. */
int ms_ws_client_key(char out[MS_WS_KEY_LEN + 1]);

/* Writes the upgrade request line and the fields that make it an upgrade (Host, Upgrade, Connection,
   Sec-WebSocket-Key, Sec-WebSocket-Version, and Sec-WebSocket-Protocol when `protocols` is not empty). The caller adds
   its own fields and the blank line. Same result codes as the ms_h1_write functions: 0, -1 (does not fit), -2 (refused). */
int ms_ws_write_upgrade(char *dst, size_t cap, size_t *used, MsBytes authority, MsBytes target, const char *key,
                        MsBytes protocols);

/* Whether `response` accepts the upgrade for `key`: status 101, Upgrade: websocket, Connection: upgrade and the right
   Sec-WebSocket-Accept. Returns 0, or -1 with *why set to the reason (a static string). */
int ms_ws_check_upgrade(const char *base, const MsH1Response *response, const char *key, const char **why);


/* What the server's 101 answer selected. */
typedef struct MsWsAccepted {
    MsBytes subprotocol; /* inside the response buffer; empty for none */
    bool compress;       /* permessage-deflate with both no-context-takeover parameters */
} MsWsAccepted;

/* The extension this client offers (Sec-WebSocket-Extensions) when compression is on. */
#define MS_WS_OFFER_DEFLATE "permessage-deflate; server_no_context_takeover; client_no_context_takeover"

/* ms_ws_check_upgrade plus the negotiation: a Sec-WebSocket-Protocol the client did not offer (`offered`, the
   comma-separated list sent) fails, as does permessage-deflate without both no-context-takeover parameters. Returns 0,
   or -1 with *why set to a static reason. */
int ms_ws_client_accept(const char *base, const MsH1Response *response, const char *key, MsBytes offered,
                        MsWsAccepted *out, const char **why);

#endif
