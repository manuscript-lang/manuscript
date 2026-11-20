/* WebSocket messages over frames (RFC 6455) with permessage-deflate (RFC 7692, no context takeover): a resumable
 * decoder that turns pushed bytes into events, and encoders that build whole frames. Sans-io: nothing here reads or
 * writes a socket. Frame heads, masking and close codes are ws.h; the session that moves these bytes over a
 * connection is ws_socket.h.
 */
#ifndef MS_NET_WS_CODEC_H
#define MS_NET_WS_CODEC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/safe.h"
#include "ws.h"

/* A growable byte buffer; `ptr` is NULL until the first append. Release it with ms_ws_buf_free. */
typedef struct MsWsBuf {
    uint8_t *ptr;
    size_t len, cap;
} MsWsBuf;

/* Appends `bytes`; false when out of memory (the buffer is unchanged). */
MS_NODISCARD bool ms_ws_buf_append(MsWsBuf *buf, MsBytes bytes);
void ms_ws_buf_free(MsWsBuf *buf);

/* Largest payload of a control frame. */
enum { MS_WS_MAX_CONTROL = 125 };

/* Close status codes (RFC 6455 7.4.1). */
enum {
    MS_WS_CLOSE_NORMAL = 1000,
    MS_WS_CLOSE_GOING_AWAY = 1001,
    MS_WS_CLOSE_PROTOCOL = 1002,
    MS_WS_CLOSE_UNSUPPORTED = 1003,
    MS_WS_CLOSE_NO_STATUS = 1005,
    MS_WS_CLOSE_ABNORMAL = 1006,
    MS_WS_CLOSE_INVALID_PAYLOAD = 1007,
    MS_WS_CLOSE_POLICY = 1008,
    MS_WS_CLOSE_TOO_BIG = 1009,
    MS_WS_CLOSE_MANDATORY_EXTENSION = 1010,
    MS_WS_CLOSE_INTERNAL = 1011,
    MS_WS_CLOSE_TLS_HANDSHAKE = 1015
};

/* ---- encoding ---- */

/* A fresh masking key; false when the system has no randomness. */
MS_NODISCARD bool ms_ws_mask_key(uint8_t key[4]);
/* Appends one frame. `mask` NULL writes an unmasked frame (a server's), else the payload is XORed with the key. */
MS_NODISCARD bool ms_ws_encode_frame(MsWsBuf *out, uint8_t opcode, bool fin, bool rsv1, MsBytes payload,
                                     const uint8_t mask[4]);
/* Appends a control frame (close, ping, pong), masked with a fresh key when `masked`. False when the payload exceeds
 * MS_WS_MAX_CONTROL bytes or on out of memory; `too_long` says which. */
MS_NODISCARD bool ms_ws_encode_control(MsWsBuf *out, uint8_t opcode, MsBytes payload, bool masked, bool *too_long);
/* Appends a data message as one frame; `compress` deflates the payload and sets RSV1. */
MS_NODISCARD bool ms_ws_encode_message(MsWsBuf *out, uint8_t opcode, MsBytes payload, bool masked, bool compress);
/* A close frame's payload: the code in two bytes then the reason (code 1005 has no payload). */
MS_NODISCARD bool ms_ws_format_close(MsWsBuf *out, unsigned code, MsBytes reason);
/* The text of a close error, `websocket: close 1006 (abnormal closure): unexpected EOF`, written to out (NUL-terminated,
 * cut to cap). */
void ms_ws_close_text(unsigned code, MsBytes reason, char *out, size_t cap);

/* Raw-deflates one message with a sync flush and no trailing 00 00 ff ff. Appends to out; false on failure. */
MS_NODISCARD bool ms_ws_deflate(MsWsBuf *out, MsBytes data);
typedef enum MsWsInflate { MS_WS_INFLATE_OK, MS_WS_INFLATE_OVERFLOW, MS_WS_INFLATE_CORRUPT, MS_WS_INFLATE_NOMEM } MsWsInflate;
/* Inflates a message payload, failing as soon as the output passes `max` bytes. Appends to out. */
MS_NODISCARD MsWsInflate ms_ws_inflate(MsWsBuf *out, MsBytes data, uint64_t max);

/* ---- decoding ---- */

typedef enum MsWsEventKind {
    MS_WSE_NEED_MORE, /* push more bytes */
    MS_WSE_MESSAGE,   /* a whole data message (decompressed); `text` says which kind, not yet checked as UTF-8 */
    MS_WSE_PING,      /* `data` is the payload */
    MS_WSE_PONG,
    MS_WSE_CLOSE,     /* `code` (1005 when none) and `data` the reason, valid UTF-8 */
    MS_WSE_FAIL       /* the stream is broken: see `failure` */
} MsWsEventKind;

typedef enum MsWsFailure {
    MS_WSF_PROTOCOL,        /* a violation: reply close 1002 with `reason`; the error reads `websocket: <reason>` */
    MS_WSF_LIMIT,           /* a message passed the limit: reply close 1009 first when `reply_close` */
    MS_WSF_INVALID_PAYLOAD, /* a close reason that is not UTF-8: reply close 1007 */
    MS_WSF_OVERFLOW,        /* a compressed message inflated past the limit */
    MS_WSF_CORRUPT,         /* a compressed message that is not valid deflate data */
    MS_WSF_NOMEM
} MsWsFailure;

typedef struct MsWsEvent {
    MsWsEventKind kind;
    bool text;
    uint16_t code;
    MsBytes data;      /* valid until the next call on the decoder */
    MsWsFailure failure;
    bool reply_close;
    bool body;         /* a failure after the first frame of a data message was accepted */
    char reason[96];   /* the protocol violation, comma-separated */
} MsWsEvent;

/* Reads frames for one direction. Zero-initialise, then ms_ws_decoder_init. */
typedef struct MsWsDecoder {
    MsWsState state;
    uint64_t limit;
    MsWsBuf input;
    size_t start;
    bool in_payload;
    MsWsHead head;
    uint64_t remaining, mask_pos;
    uint8_t control[MS_WS_MAX_CONTROL];
    size_t control_len;
    bool in_body, compressed;
    uint8_t kind;
    uint64_t wire_len;
    MsWsBuf message, inflated;
} MsWsDecoder;

/* `server` is true when this end is the server (frames must be masked). `limit` bounds a message in bytes, on the wire
 * and after inflation. */
void ms_ws_decoder_init(MsWsDecoder *d, bool server, bool deflate, uint64_t limit);
void ms_ws_decoder_free(MsWsDecoder *d);
/* Appends received bytes; false when out of memory. */
MS_NODISCARD bool ms_ws_decoder_push(MsWsDecoder *d, MsBytes bytes);
/* Whether the first frame of a data message was accepted and the message is unfinished: an end of stream then reads as a
 * truncated exchange. */
bool ms_ws_decoder_in_message(const MsWsDecoder *d);
/* Pulls the next event. After MS_WSE_FAIL the decoder must not be used again. */
void ms_ws_decoder_poll(MsWsDecoder *d, MsWsEvent *event);

#endif
