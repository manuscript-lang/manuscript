/* runtime/std/ws_session.h: a WebSocket message session over a byte transport (ws_session.c): reading and
 * answering control frames, the close handshake, and sending whole messages. The transport is a connection
 * of @std/net in production (ws_abi.c) and a pair of buffers in a test.
 *
 * Statuses: OK, NONE (the peer ended the session with close 1000 or 1001), CLOSED, INVALID_INPUT,
 * INVALID_DATA, LIMIT_EXCEEDED, TIMED_OUT (the session stays usable), or FAILED with the text in `err`. After
 * a failure other than TIMED_OUT the session is over and later calls give CLOSED. */
#ifndef MS_RUNTIME_STD_WS_SESSION_H
#define MS_RUNTIME_STD_WS_SESSION_H

#include "abi/status.h"
#include "runtime/std/ws.h"

typedef struct MsWsTransport {
  void *context;
  /* Appends bytes read (a negative timeout waits for ever): OK with data, NONE at the end of the stream,
   * TIMED_OUT, CLOSED, or FAILED with text. */
  uint8_t (*read)(void *context, int64_t timeout_ns, MsBytes *out, MsString *err);
  uint8_t (*write)(void *context, MsSpan data, int64_t timeout_ns, MsString *err);
  void (*close)(void *context);
  bool (*is_closed)(void *context);
  void (*release)(void *context); /* when the session ends */
} MsWsTransport;

typedef struct MsWsConfig {
  bool client;    /* clients mask their frames */
  bool compress;  /* permessage-deflate was negotiated */
  bool has_limit; /* max_message_bytes bounds a message in either direction */
  uint64_t max_message_bytes;
  MsString subprotocol; /* moved into the session; empty when none */
} MsWsConfig;

typedef struct MsWsSession MsWsSession;
typedef struct MsWsMessage {
  MsBytes data;
  bool text;
} MsWsMessage;

/* `leftover` are bytes already read past the handshake head. Takes the transport and the config's string. */
MsWsSession *ms_ws_session_new(const MsWsTransport *transport, MsWsConfig *config, MsSpan leftover);
/* One more handle on the session (handles count; the last release frees it, closing nothing). */
MsWsSession *ms_ws_session_retain(MsWsSession *session);
void ms_ws_session_release(MsWsSession *session);
/* Whether this is the only handle. */
bool ms_ws_session_is_last(const MsWsSession *session);
const MsString *ms_ws_session_subprotocol(const MsWsSession *session);

/* Closed in order: the session ended, over the limit, invalid UTF-8 text, then the write. */
MS_NODISCARD uint8_t ms_ws_session_send(MsWsSession *session, MsSpan data, bool text, int64_t timeout_ns,
                                        MsString *err);
/* A ping with a one second write limit; more than 125 bytes is INVALID_INPUT. */
MS_NODISCARD uint8_t ms_ws_session_ping(MsWsSession *session, MsSpan data, MsString *err);
/* A close frame (normal closure) within about 100 ms, then the transport. Idempotent. */
void ms_ws_session_close(MsWsSession *session);
/* Like close with a status code and a reason (cut to 123 bytes). */
void ms_ws_session_close_with(MsWsSession *session, uint16_t code, MsSpan reason);
/* The next message; pings are answered and pongs dropped. */
MS_NODISCARD uint8_t ms_ws_session_receive(MsWsSession *session, int64_t timeout_ns, MsWsMessage *out,
                                           MsString *err);
/* Sends close `code`, waits for the peer's close frame (messages before it are dropped) for at most
 * `timeout_ns`, and closes the transport. */
MS_NODISCARD uint8_t ms_ws_session_close_handshake(MsWsSession *session, uint16_t code, MsSpan reason,
                                                   int64_t timeout_ns, MsString *err);

#endif
