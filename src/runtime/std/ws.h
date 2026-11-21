/* runtime/std/ws.h: WebSocket frames (RFC 6455) and permessage-deflate (RFC 7692, no context takeover):
 * encoders (ws_frame.c), the resumable decoder (ws_decode.c) and the opening handshake (ws_handshake.c).
 * Pure over byte buffers: the sockets are the caller's. */
#ifndef MS_RUNTIME_STD_WS_H
#define MS_RUNTIME_STD_WS_H

#include "base/bytes.h"
#include "base/strbuild.h"
#include "runtime/std/http_headers.h"

enum {
  MS_WS_OP_CONTINUATION = 0,
  MS_WS_OP_TEXT = 1,
  MS_WS_OP_BINARY = 2,
  MS_WS_OP_CLOSE = 8,
  MS_WS_OP_PING = 9,
  MS_WS_OP_PONG = 10,
  MS_WS_MAX_CONTROL_PAYLOAD = 125
};

/* Close status codes (RFC 6455 section 7.4.1). */
enum {
  MS_WS_CLOSE_NORMAL = 1000,
  MS_WS_CLOSE_GOING_AWAY = 1001,
  MS_WS_CLOSE_PROTOCOL_ERROR = 1002,
  MS_WS_CLOSE_UNSUPPORTED_DATA = 1003,
  MS_WS_CLOSE_NO_STATUS = 1005,
  MS_WS_CLOSE_ABNORMAL = 1006,
  MS_WS_CLOSE_INVALID_PAYLOAD = 1007,
  MS_WS_CLOSE_POLICY_VIOLATION = 1008,
  MS_WS_CLOSE_MESSAGE_TOO_BIG = 1009,
  MS_WS_CLOSE_MANDATORY_EXTENSION = 1010,
  MS_WS_CLOSE_INTERNAL_ERROR = 1011,
  MS_WS_CLOSE_SERVICE_RESTART = 1012,
  MS_WS_CLOSE_TRY_AGAIN_LATER = 1013,
  MS_WS_CLOSE_TLS_HANDSHAKE = 1015
};

/* Whether a close code may appear on the wire (RFC 6455 section 7.4). */
bool ms_ws_valid_received_close_code(uint16_t code);
/* `websocket: close 1006 (abnormal closure): reason`. */
void ms_ws_close_error_text(uint16_t code, MsSpan reason, MsStrBuild *out);
/* Two code bytes then the reason; code 1005 has no payload. */
void ms_ws_format_close(uint16_t code, MsSpan reason, MsBytes *out);
/* The payload of a protocol-error close: 1002 and the message, cut to 125 bytes. */
void ms_ws_protocol_error_payload(MsSpan message, MsBytes *out);

/* XORs `data` with the key starting at key offset `pos`; returns the next offset. */
size_t ms_ws_mask_bytes(const uint8_t key[4], size_t pos, uint8_t *data, size_t length);
/* A fresh masking key from the operating system; false when it has none. */
MS_NODISCARD bool ms_ws_new_mask_key(uint8_t key[4]);

/* Appends one frame; a masked frame (`key` not null) carries the payload XORed with the key. */
void ms_ws_encode_frame(MsBytes *out, uint8_t opcode, bool fin, bool rsv1, MsSpan payload,
                        const uint8_t *key);
/* A control frame; false when the payload exceeds 125 bytes (or the key cannot be made). */
MS_NODISCARD bool ms_ws_encode_control(MsBytes *out, uint8_t opcode, MsSpan payload, bool masked);
/* A whole data message as one or more frames. `compress` deflates the payload and sets RSV1 on the first
 * frame; `max_frame` splits the (possibly compressed) payload into fragments of at most that many bytes (0 is
 * one frame). Each frame of a client gets its own key. False when a key cannot be made. */
MS_NODISCARD bool ms_ws_encode_message(MsBytes *out, uint8_t opcode, MsSpan payload, bool masked,
                                       bool compress, size_t max_frame);
/* Raw-deflates one message with a sync flush and strips the trailing 00 00 ff ff (RFC 7692 section 7.2.1). */
void ms_ws_deflate_message(MsSpan data, MsBytes *out);

typedef enum MsWsInflate { MS_WS_INFLATE_OK, MS_WS_INFLATE_OVERFLOW, MS_WS_INFLATE_CORRUPT } MsWsInflate;
/* Inflates a message payload per RFC 7692, failing as soon as the output passes `max` bytes. */
MsWsInflate ms_ws_inflate_message(MsSpan data, uint64_t max, MsBytes *out);

/* ---- decoder ---- */

typedef enum MsWsEventKind { MS_WS_MESSAGE, MS_WS_PING, MS_WS_PONG, MS_WS_CLOSE } MsWsEventKind;

typedef struct MsWsEvent {
  MsWsEventKind kind;
  bool text;     /* a message: text payloads are not yet checked for UTF-8 */
  uint16_t code; /* a close: 1005 when it carried none */
  MsBytes data;  /* the message, the ping or pong payload, or the close reason; owned */
} MsWsEvent;

typedef enum MsWsErrorKind {
  MS_WS_ERR_PROTOCOL,        /* send close 1002 with `text`; the error reads `websocket: <text>` */
  MS_WS_ERR_LIMIT,           /* `websocket: read limit exceeded`; reply_close asks for close 1009 first */
  MS_WS_ERR_INVALID_PAYLOAD, /* a close reason that is not UTF-8: send close 1007 */
  MS_WS_ERR_OVERFLOW,        /* a compressed message inflated past the limit */
  MS_WS_ERR_CORRUPT          /* a compressed message that is not valid deflate data */
} MsWsErrorKind;

typedef struct MsWsError {
  MsWsErrorKind kind;
  MsString text;    /* protocol */
  bool body;        /* after the first frame of a data message: worded as a truncated exchange */
  bool reply_close; /* limit */
} MsWsError;

typedef enum MsWsFrameStage { MS_WS_STAGE_HEADER, MS_WS_STAGE_PAYLOAD } MsWsFrameStage;

typedef struct MsWsDecoder {
  bool server; /* frames must be masked for a server and unmasked for a client */
  bool deflate;
  uint64_t limit;
  MsBytes input;
  size_t start;
  MsWsFrameStage stage;
  uint8_t opcode; /* of the frame being read */
  bool fin;
  bool masked;
  uint8_t key[4];
  uint64_t remaining; /* payload bytes of the frame still to come */
  size_t mask_pos;
  MsBytes control;  /* the control frame payload being collected */
  bool fragmenting; /* a data message is split and not yet finished */
  bool in_body;     /* the first frame of the current message was accepted */
  uint8_t kind;
  bool compressed;
  uint64_t wire_len;
  MsBytes message;
} MsWsDecoder;

typedef enum MsWsPoll { MS_WS_NEED_MORE, MS_WS_GOT_EVENT, MS_WS_GOT_ERROR } MsWsPoll;

/* `limit` bounds a message in bytes (the wire sum of its frames, and after inflation). */
MsWsDecoder ms_ws_decoder_new(bool server, bool deflate, uint64_t limit);
void ms_ws_decoder_free(MsWsDecoder *decoder);
void ms_ws_decoder_push(MsWsDecoder *decoder, MsSpan bytes);
/* Whether the first frame of a data message was accepted and the message is unfinished. */
bool ms_ws_decoder_in_message(const MsWsDecoder *decoder);
/* Pulls the next event (ownership of event->data moves to the caller) or error (release with
 * ms_ws_error_release). */
MsWsPoll ms_ws_decoder_poll(MsWsDecoder *decoder, MsWsEvent *event, MsWsError *error);
void ms_ws_error_release(MsWsError *error);

/* ---- opening handshake (ws_handshake.c) ---- */

/* `Sec-WebSocket-Accept` for a challenge key. */
void ms_ws_accept_key(MsSpan challenge, MsStrBuild *out);
/* A fresh `Sec-WebSocket-Key`: 16 random bytes in base64; false when the system has no entropy. */
MS_NODISCARD bool ms_ws_generate_key(MsStrBuild *out);
/* Whether `text` is the base64 text of exactly 16 bytes. */
bool ms_ws_valid_challenge_key(MsSpan text);
/* Whether a comma-separated field holds `value` as a token, ignoring ASCII case; a malformed element skips
 * the rest of that line. */
bool ms_ws_token_list_contains(const MsHeaders *fields, const char *name, const char *value);

/* The only extension offered or accepted; both context takeovers are always off. */
#define MS_WS_DEFLATE_RESPONSE "permessage-deflate; server_no_context_takeover; client_no_context_takeover"

/* Server side: the request, the policy, and the outcome. */
typedef struct MsWsRequest {
  MsSpan method;
  MsSpan host; /* the request's Host */
  bool tls;
  const MsHeaders *fields;
} MsWsRequest;

typedef struct MsWsServerOptions {
  const MsSpan *allowed_origins; /* empty: same origin only */
  size_t allowed_origin_count;
  const MsSpan *subprotocols; /* in order of preference */
  size_t subprotocol_count;
  bool compression; /* negotiate permessage-deflate when the client offers it */
} MsWsServerOptions;

typedef struct MsWsAccepted {
  MsString subprotocol; /* empty when none; owned */
  bool compress;
  MsBytes response; /* the complete 101 head; owned */
} MsWsAccepted;

/* A refused upgrade: the status answered and the handshake error text (static). */
typedef struct MsWsRejected {
  uint16_t status;
  const char *message;
} MsWsRejected;

/* Validates an upgrade request in this order (Connection, Upgrade, method, version, origin, key) and builds
 * the 101 response. */
MS_NODISCARD bool ms_ws_accept(const MsWsRequest *request, const MsWsServerOptions *options,
                               MsWsAccepted *accepted, MsWsRejected *rejected);
void ms_ws_accepted_release(MsWsAccepted *accepted);
/* The error response for a refusal; `date` is the Unix time of the Date field; `close` appends
 * `Connection: close`. */
void ms_ws_rejected_response(const MsWsRejected *rejected, int64_t date, bool close, MsBytes *out);
/* The origin policy: a missing or empty Origin is accepted; otherwise it must be a bare http or https origin
 * that equals an allowed entry, or (with none allowed) has the request's scheme and host. */
bool ms_ws_origin_allowed(const MsHeaders *fields, MsSpan host, bool tls, const MsSpan *allowed,
                          size_t count);

/* Client side. */
typedef struct MsWsClientRequest {
  MsSpan target; /* path and query */
  MsSpan host;   /* the Host value */
  MsSpan key;    /* from ms_ws_generate_key */
  const MsSpan *subprotocols;
  size_t subprotocol_count;
  const MsHeaders *headers; /* the caller's, already validated; may be null */
  bool compression;
} MsWsClientRequest;

/* The upgrade request: request line, Host, User-Agent, then the other fields sorted by name. */
void ms_ws_client_request(const MsWsClientRequest *request, MsBytes *out);

typedef enum MsWsClientResult {
  MS_WS_CLIENT_OK,
  MS_WS_CLIENT_BAD_HANDSHAKE,
  MS_WS_CLIENT_INVALID_COMPRESSION
} MsWsClientResult;
/* The error text of a failed result. */
const char *ms_ws_client_message(MsWsClientResult result);
/* The client's checks on the response: status 101, Upgrade and Connection tokens, the accept key, a
 * subprotocol it offered, then the extension. *subprotocol (owned) is the response's, empty when absent. */
MsWsClientResult ms_ws_check_response(uint16_t status, const MsHeaders *fields, MsSpan key,
                                      const MsSpan *offered, size_t offered_count, MsString *subprotocol,
                                      bool *compress);

#endif
