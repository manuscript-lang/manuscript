/* A WebSocket message session over a connection row (ws_codec.h over conn_io.h).
 *
 * One session serves both ends: the client after ws_client.c's handshake, the server after the upgrade. It reads and
 * writes through ms_conn_read and ms_conn_write, so a call parks the calling task like any connection I/O.
 *
 * Calls may overlap from different tasks: one receive at a time (a second fails), and sends that arrive while another
 * write is running are queued behind it and written by it, in order. Deadlines are absolute ms_sys_monotonic_ns times,
 * negative for none.
 *
 * After a failure other than MS_WSS_TIMEOUT the session is over and later calls give MS_WSS_CLOSED. A timed-out
 * receive leaves it intact and the next call resumes where it stopped.
 */
#ifndef MS_NET_WS_SOCKET_H
#define MS_NET_WS_SOCKET_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "conn_object.h"
#include "ms_rt/safe.h"

typedef struct MsWsSocket MsWsSocket;

typedef enum MsWsRole { MS_WS_ROLE_CLIENT, MS_WS_ROLE_SERVER } MsWsRole;

typedef enum MsWsStatus {
    MS_WSS_OK = 0,
    MS_WSS_CLOSED,        /* the session ended */
    MS_WSS_INVALID_INPUT, /* a control payload over 125 bytes */
    MS_WSS_LIMIT,         /* a message over the limit (the limit's own error, not a failed exchange) */
    MS_WSS_INVALID_DATA,  /* text that is not valid UTF-8 */
    MS_WSS_TIMEOUT,
    MS_WSS_CANCELLED,     /* a stop request ended the wait */
    MS_WSS_FAILED,        /* anything else: ms_ws_socket_error has the text */
    MS_WSS_NOMEM
} MsWsStatus;

typedef struct MsWsConfig {
    uint64_t max_message_bytes; /* UINT64_MAX for no limit */
    bool compress;              /* permessage-deflate (no context takeover) was negotiated */
    MsBytes subprotocol;        /* the subprotocol selected in the handshake, empty for none */
} MsWsConfig;

/* A session over the connection `conn` (a handle of conn_object.h, which the session keeps a counted reference to).
 * Bytes the HTTP layer already read past the handshake and kept in the row are taken as the first input. NULL when out
 * of memory. */
MS_NODISCARD MsWsSocket *ms_ws_socket_new(MsObj *conn, MsWsRole role, const MsWsConfig *config);
/* The session is shared by counted references: ms_ws_socket_new gives the first, retain adds one and release drops one.
 * The last release frees the session and drops its reference to the connection, which closes the row when it was the
 * last; it does not send a close frame (ms_ws_socket_close). */
MsWsSocket *ms_ws_socket_retain(MsWsSocket *socket);
void ms_ws_socket_release(MsWsSocket *socket);
/* How many references there are: close_if_last closes the session when this is 1. */
unsigned ms_ws_socket_refs(const MsWsSocket *socket);
/* Hands the session input bytes the caller read itself (a handshake leftover not kept in the row). */
MS_NODISCARD MsWsStatus ms_ws_socket_feed(MsWsSocket *socket, MsBytes bytes);

MsBytes ms_ws_socket_subprotocol(const MsWsSocket *socket);
/* Whether the session ended: closed locally, failed by a read error, or its connection was closed. */
bool ms_ws_socket_is_closed(const MsWsSocket *socket);
/* The text of the last MS_WSS_FAILED, for example "websocket: close 1006 (abnormal closure): unexpected EOF". */
const char *ms_ws_socket_error(const MsWsSocket *socket);

/* Sends one text or binary message. Errors in order: closed, over the message limit, invalid UTF-8 text, the write. */
MsWsStatus ms_ws_socket_send(MsWsSocket *socket, MsBytes data, bool text, int64_t deadline_ns);
/* Sends a ping with a one-second write deadline and does not wait for the pong. */
MsWsStatus ms_ws_socket_ping(MsWsSocket *socket, MsBytes data);

typedef struct MsWsMessage {
    MsBytes data; /* valid until the next call on the session */
    bool text;    /* a text message: the data is valid UTF-8 */
} MsWsMessage;

/* Waits for the next message. Pings are answered and pongs dropped. On MS_WSS_OK, `*ended` is true when the peer
 * closed normally (code 1000 or 1001) and `message` is then unset. */
MsWsStatus ms_ws_socket_receive(MsWsSocket *socket, int64_t deadline_ns, MsWsMessage *message, bool *ended);

/* Sends a normal-closure frame within about 100 ms, then closes the connection. Idempotent. */
void ms_ws_socket_close(MsWsSocket *socket);
/* Like close, with a status code and a reason (cut to 123 bytes at a character boundary). */
void ms_ws_socket_close_with(MsWsSocket *socket, unsigned code, MsBytes reason);
/* Closes with a handshake: sends the close frame, waits for the peer's (discarding messages that arrive first) until
 * the deadline, and closes the connection either way. A peer that closes the stream counts as answered. */
MsWsStatus ms_ws_socket_close_handshake(MsWsSocket *socket, unsigned code, MsBytes reason, int64_t deadline_ns);

#endif
