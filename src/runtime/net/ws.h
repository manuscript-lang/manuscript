/* WebSocket frames (RFC 6455): header parsing with the Rust decoder's checks and failure texts, masking, header
   writing and the handshake accept key. Pure functions over caller buffers; payload bytes are never copied here. */
#ifndef MS_NET_WS_H
#define MS_NET_WS_H
#include <stddef.h>
#include <stdint.h>

enum { MS_WS_CONT = 0, MS_WS_TEXT = 1, MS_WS_BINARY = 2, MS_WS_CLOSE = 8, MS_WS_PING = 9, MS_WS_PONG = 10 };

/* What the parser needs to know about the stream so far. */
typedef struct {
    uint8_t server;      /* this end is the server: frames must be masked, else they must not be */
    uint8_t deflate;     /* permessage-deflate negotiated: RSV1 allowed on the first data frame */
    uint8_t fragmenting; /* inside a fragmented message: the last data frame had FIN clear */
} MsWsState;

typedef struct {
    uint8_t fin, opcode, compressed, masked;
    uint8_t mask[4];
    uint32_t head_len;
    uint64_t payload_len;
} MsWsHead;

enum { MS_WS_PARTIAL = 0, MS_WS_OK = 1, MS_WS_BAD = 2, MS_WS_TOO_BIG = 3 /* the payload length passes 2^63 - 1 */ };

/* Parses one frame header from buf[0..len). BAD fills `reason` (at most `cap` bytes, NUL-terminated) with the
   comma-separated failure text, for example "RSV1 set, bad MASK". The checks that need only the first two bytes
   run before the rest of the header arrives, so a bad frame fails early. On OK the caller updates
   `state->fragmenting` with ms_ws_after_head. */
int ms_ws_parse_head(const MsWsState *state, const uint8_t *buf, size_t len, MsWsHead *out, char *reason, size_t cap);
void ms_ws_after_head(MsWsState *state, const MsWsHead *head);

/* XORs buf[0..n) with the mask, where `pos` is how many payload bytes of this frame came before it. */
void ms_ws_unmask(uint8_t *buf, size_t n, const uint8_t mask[4], uint64_t pos);

/* Writes a frame header into dst (at least 14 bytes); returns its length. mask == NULL writes an unmasked one. */
size_t ms_ws_write_head(uint8_t *dst, uint8_t opcode, int fin, int compressed, uint64_t payload_len, const uint8_t *mask);

/* Close codes allowed on the wire (RFC 6455 7.4). */
int ms_ws_valid_close_code(unsigned code);

/* Sec-WebSocket-Accept for a client key: 28 base64 characters plus NUL written to out (29 bytes). 0 on success. */
int ms_ws_accept_key(const char *key, size_t key_len, char out[29]);

#endif
