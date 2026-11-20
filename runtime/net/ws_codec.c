/* WebSocket frame encoding and decoding (ws_codec.h). */
#include "ws_codec.h"

#include <limits.h>
#include <openssl/rand.h>
#include <stdio.h>
#include <string.h>
#include <zlib.h>

#include "ms_rt/alloc.h"
#include "ms_rt/utf8.h"

/* ---- buffers ---- */

static bool buf_reserve(MsWsBuf *buf, size_t extra) {
    size_t need;
    if (!ms_size_add(buf->len, extra, &need)) {
        return false;
    }
    if (need <= buf->cap) {
        return true;
    }
    size_t cap = buf->cap < 256 ? 256 : buf->cap;
    while (cap < need) {
        if (!ms_size_mul(cap, 2, &cap)) {
            cap = need;
        }
    }
    uint8_t *grown = msrt_realloc(buf->ptr, cap);
    if (grown == NULL) {
        return false;
    }
    buf->ptr = grown;
    buf->cap = cap;
    return true;
}

bool ms_ws_buf_append(MsWsBuf *buf, MsBytes bytes) {
    if (bytes.len == 0) {
        return true;
    }
    if (!buf_reserve(buf, bytes.len)) {
        return false;
    }
    memcpy(buf->ptr + buf->len, bytes.ptr, bytes.len);
    buf->len += bytes.len;
    return true;
}

void ms_ws_buf_free(MsWsBuf *buf) {
    msrt_free(buf->ptr);
    *buf = (MsWsBuf){0};
}

/* ---- close codes ---- */

bool ms_ws_format_close(MsWsBuf *out, unsigned code, MsBytes reason) {
    if (code == MS_WS_CLOSE_NO_STATUS) {
        return true;
    }
    const uint8_t head[2] = {(uint8_t)(code >> 8), (uint8_t)code};
    return ms_ws_buf_append(out, ms_bytes_of(head, 2)) && ms_ws_buf_append(out, reason);
}

static const char *close_name(unsigned code) {
    switch (code) {
    case MS_WS_CLOSE_NORMAL: return " (normal)";
    case MS_WS_CLOSE_GOING_AWAY: return " (going away)";
    case MS_WS_CLOSE_PROTOCOL: return " (protocol error)";
    case MS_WS_CLOSE_UNSUPPORTED: return " (unsupported data)";
    case MS_WS_CLOSE_NO_STATUS: return " (no status)";
    case MS_WS_CLOSE_ABNORMAL: return " (abnormal closure)";
    case MS_WS_CLOSE_INVALID_PAYLOAD: return " (invalid payload data)";
    case MS_WS_CLOSE_POLICY: return " (policy violation)";
    case MS_WS_CLOSE_TOO_BIG: return " (message too big)";
    case MS_WS_CLOSE_MANDATORY_EXTENSION: return " (mandatory extension missing)";
    case MS_WS_CLOSE_INTERNAL: return " (internal server error)";
    case MS_WS_CLOSE_TLS_HANDSHAKE: return " (TLS handshake error)";
    default: return "";
    }
}

void ms_ws_close_text(unsigned code, MsBytes reason, char *out, size_t cap) {
    if (cap == 0) {
        return;
    }
    const int shown = reason.len > INT_MAX ? INT_MAX : (int)reason.len;
    const char *separator = reason.len > 0 ? ": " : "";
    (void)snprintf(out, cap, "websocket: close %u%s%s%.*s", code, close_name(code), separator, shown,
                   (const char *)reason.ptr);
}

/* ---- encoding ---- */

bool ms_ws_mask_key(uint8_t key[4]) { return RAND_bytes(key, 4) == 1; }

bool ms_ws_encode_frame(MsWsBuf *out, uint8_t opcode, bool fin, bool rsv1, MsBytes payload, const uint8_t mask[4]) {
    enum { MAX_HEAD = 14 };
    size_t total;
    if (!ms_size_add(payload.len, MAX_HEAD, &total) || !buf_reserve(out, total)) {
        return false;
    }
    uint8_t *frame = out->ptr + out->len;
    const size_t head = ms_ws_write_head(frame, opcode, fin, rsv1, payload.len, mask);
    if (payload.len > 0) {
        memcpy(frame + head, payload.ptr, payload.len);
    }
    if (mask != NULL) {
        ms_ws_unmask(frame + head, payload.len, mask, 0);
    }
    out->len += head + payload.len;
    return true;
}

bool ms_ws_encode_control(MsWsBuf *out, uint8_t opcode, MsBytes payload, bool masked, bool *too_long) {
    *too_long = payload.len > MS_WS_MAX_CONTROL;
    uint8_t key[4];
    if (*too_long || (masked && !ms_ws_mask_key(key))) {
        return false;
    }
    return ms_ws_encode_frame(out, opcode, true, false, payload, masked ? key : NULL);
}

bool ms_ws_encode_message(MsWsBuf *out, uint8_t opcode, MsBytes payload, bool masked, bool compress) {
    uint8_t key[4];
    if (masked && !ms_ws_mask_key(key)) {
        return false;
    }
    if (!compress) {
        return ms_ws_encode_frame(out, opcode, true, false, payload, masked ? key : NULL);
    }
    MsWsBuf deflated = {0};
    bool ok = ms_ws_deflate(&deflated, payload) &&
              ms_ws_encode_frame(out, opcode, true, true, ms_bytes_of(deflated.ptr, deflated.len), masked ? key : NULL);
    ms_ws_buf_free(&deflated);
    return ok;
}

/* ---- permessage-deflate ---- */

/* An empty stored block, then a final empty block: what ends a message whose sync tail was stripped. */
static const uint8_t inflate_tail[9] = {0x00, 0x00, 0xff, 0xff, 0x01, 0x00, 0x00, 0xff, 0xff};
static const uint8_t sync_tail[4] = {0x00, 0x00, 0xff, 0xff};
enum { DEFLATE_LEVEL = 1, WINDOW_BITS = -15, INFLATE_CHUNK = 32 * 1024 };

/* Points the stream's input at `bytes`: zlib's pointer is not const-qualified, and it never writes through it. */
static void aim_input(z_stream *z, MsBytes bytes) {
    memcpy(&z->next_in, &bytes.ptr, sizeof bytes.ptr);
    z->avail_in = bytes.len > UINT_MAX ? UINT_MAX : (uInt)bytes.len;
}

/* Sets the stream's next_out to the free space of out, at most what a uInt counts. */
static void aim_output(z_stream *z, MsWsBuf *out) {
    const size_t room = out->cap - out->len;
    z->next_out = out->ptr + out->len;
    z->avail_out = room > UINT_MAX ? UINT_MAX : (uInt)room;
}

bool ms_ws_deflate(MsWsBuf *out, MsBytes data) {
    z_stream z = {0};
    if (deflateInit2(&z, DEFLATE_LEVEL, Z_DEFLATED, WINDOW_BITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return false;
    }
    const size_t base = out->len;
    size_t offset = 0;
    bool ok = true;
    bool done = false;
    while (ok && !done) {
        const size_t left = data.len - offset;
        aim_input(&z, ms_bytes_of(data.ptr == NULL ? NULL : data.ptr + offset, left));
        const uInt offered = z.avail_in;
        ok = buf_reserve(out, 256 + offered / 2);
        if (!ok) {
            break;
        }
        aim_output(&z, out);
        const uInt room = z.avail_out;
        const int rc = deflate(&z, offered == left ? Z_SYNC_FLUSH : Z_NO_FLUSH);
        out->len += room - z.avail_out;
        offset += offered - z.avail_in;
        ok = rc == Z_OK || rc == Z_BUF_ERROR;
        done = offset == data.len && z.avail_out > 0;
    }
    (void)deflateEnd(&z);
    if (!ok) {
        out->len = base;
        return false;
    }
    if (out->len - base >= sizeof sync_tail && memcmp(out->ptr + out->len - sizeof sync_tail, sync_tail, sizeof sync_tail) == 0) {
        out->len -= sizeof sync_tail;
    }
    return true;
}

MsWsInflate ms_ws_inflate(MsWsBuf *out, MsBytes data, uint64_t max) {
    z_stream z = {0};
    if (inflateInit2(&z, WINDOW_BITS) != Z_OK) {
        return MS_WS_INFLATE_NOMEM;
    }
    const MsBytes parts[2] = {data, ms_bytes_of(inflate_tail, sizeof inflate_tail)};
    size_t part = 0, in_offset = 0;
    size_t produced = 0;
    MsWsInflate result = MS_WS_INFLATE_CORRUPT;
    for (;;) {
        if (z.avail_in == 0 && part < 2 && in_offset >= parts[part].len) {
            part++;
            in_offset = 0;
        }
        if (z.avail_in == 0 && part < 2) {
            const size_t left = parts[part].len - in_offset;
            aim_input(&z, ms_bytes_of(parts[part].ptr + in_offset, left));
            in_offset += z.avail_in;
        }
        if (!buf_reserve(out, INFLATE_CHUNK)) {
            result = MS_WS_INFLATE_NOMEM;
            break;
        }
        aim_output(&z, out);
        const uInt room = z.avail_out;
        const int rc = inflate(&z, Z_NO_FLUSH);
        produced += room - z.avail_out;
        out->len += room - z.avail_out;
        if (produced > max) {
            result = MS_WS_INFLATE_OVERFLOW;
            break;
        }
        if (rc == Z_STREAM_END) {
            result = MS_WS_INFLATE_OK;
            break;
        }
        const bool input_ended = z.avail_in == 0 && part >= 2 && in_offset >= parts[1].len;
        if (rc == Z_BUF_ERROR && input_ended && z.avail_out > 0) {
            break; /* the stream wants more than there is */
        }
        if (rc != Z_OK && rc != Z_BUF_ERROR) {
            break;
        }
    }
    (void)inflateEnd(&z);
    return result;
}

/* ---- decoding ---- */

void ms_ws_decoder_init(MsWsDecoder *d, bool server, bool deflate, uint64_t limit) {
    *d = (MsWsDecoder){0};
    d->state.server = server;
    d->state.deflate = deflate;
    d->limit = limit;
    d->kind = MS_WS_BINARY;
}

void ms_ws_decoder_free(MsWsDecoder *d) {
    ms_ws_buf_free(&d->input);
    ms_ws_buf_free(&d->message);
    ms_ws_buf_free(&d->inflated);
}

bool ms_ws_decoder_push(MsWsDecoder *d, MsBytes bytes) {
    if (d->start > 0 && d->start == d->input.len) {
        d->input.len = 0;
        d->start = 0;
    } else if (d->start > (size_t)1 << 16) {
        d->input.len -= d->start;
        memmove(d->input.ptr, d->input.ptr + d->start, d->input.len);
        d->start = 0;
    }
    return ms_ws_buf_append(&d->input, bytes);
}

bool ms_ws_decoder_in_message(const MsWsDecoder *d) { return d->in_body; }

static void fail(const MsWsDecoder *d, MsWsEvent *event, MsWsFailure failure) {
    *event = (MsWsEvent){.kind = MS_WSE_FAIL, .failure = failure, .body = d->in_body};
}

static void fail_protocol(const MsWsDecoder *d, MsWsEvent *event, const char *reason) {
    fail(d, event, MS_WSF_PROTOCOL);
    (void)snprintf(event->reason, sizeof event->reason, "%s", reason);
}

static void fail_limit(const MsWsDecoder *d, MsWsEvent *event) {
    fail(d, event, MS_WSF_LIMIT);
    event->reply_close = true;
}

/* Size accounting of a data frame; a text or binary frame starts a new message. False after filling `event`. */
static bool accept_data_head(MsWsDecoder *d, const MsWsHead *head, MsWsEvent *event) {
    const bool starts = head->opcode != MS_WS_CONT;
    const uint64_t base = starts ? 0 : d->wire_len;
    if (head->payload_len > (uint64_t)INT64_MAX - base || base + head->payload_len > d->limit) {
        fail_limit(d, event);
        return false;
    }
    d->wire_len = base + head->payload_len;
    if (starts) {
        d->kind = head->opcode;
        d->compressed = head->compressed;
        d->message.len = 0;
        d->in_body = true;
    }
    return true;
}

/* Parses a frame head if it is complete. Returns true when a frame began, false when more bytes are needed or
 * `event` holds a failure (kind FAIL). */
static bool read_head(MsWsDecoder *d, MsWsEvent *event) {
    const size_t available = d->input.len - d->start;
    char reason[sizeof event->reason];
    MsWsHead head;
    const int rc = ms_ws_parse_head(&d->state, d->input.ptr + d->start, available, &head, reason, sizeof reason);
    if (rc == MS_WS_PARTIAL) {
        return false;
    }
    if (rc == MS_WS_BAD) {
        fail_protocol(d, event, reason);
        return false;
    }
    if (rc == MS_WS_TOO_BIG) {
        fail_limit(d, event);
        return false;
    }
    const bool control = head.opcode >= MS_WS_CLOSE;
    if (!control && !accept_data_head(d, &head, event)) {
        return false;
    }
    ms_ws_after_head(&d->state, &head);
    d->start += head.head_len;
    d->head = head;
    d->remaining = head.payload_len;
    d->mask_pos = 0;
    d->control_len = 0;
    d->in_payload = true;
    return true;
}

/* Copies what has arrived of the frame's payload into its sink, unmasked. False when out of memory. */
static bool take_payload(MsWsDecoder *d) {
    const size_t available = d->input.len - d->start;
    const size_t take = available < d->remaining ? available : (size_t)d->remaining;
    if (take == 0) {
        return true;
    }
    const MsBytes chunk = ms_bytes_of(d->input.ptr + d->start, take);
    uint8_t *sink;
    if (d->head.opcode >= MS_WS_CLOSE) {
        sink = d->control + d->control_len;
        memcpy(sink, chunk.ptr, take);
        d->control_len += take;
    } else {
        if (!ms_ws_buf_append(&d->message, chunk)) {
            return false;
        }
        sink = d->message.ptr + d->message.len - take;
    }
    if (d->head.masked) {
        ms_ws_unmask(sink, take, d->head.mask, d->mask_pos);
    }
    d->mask_pos += take;
    d->remaining -= take;
    d->start += take;
    return true;
}

static void control_event(MsWsDecoder *d, MsWsEvent *event) {
    const MsBytes payload = ms_bytes_of(d->control, d->control_len);
    *event = (MsWsEvent){.kind = MS_WSE_PING, .data = payload};
    if (d->head.opcode == MS_WS_PONG) {
        event->kind = MS_WSE_PONG;
    } else if (d->head.opcode == MS_WS_CLOSE) {
        if (payload.len == 0) {
            *event = (MsWsEvent){.kind = MS_WSE_CLOSE, .code = MS_WS_CLOSE_NO_STATUS};
            return;
        }
        if (payload.len == 1) {
            fail_protocol(d, event, "close payload has one byte");
            return;
        }
        const unsigned code = (unsigned)payload.ptr[0] << 8 | payload.ptr[1];
        const bool allowed = ms_ws_valid_close_code(code);
        if (!allowed) {
            char text[sizeof event->reason];
            (void)snprintf(text, sizeof text, "bad close code %u", code);
            fail_protocol(d, event, text);
        } else if (!ms_utf8_is_valid(payload.ptr + 2, payload.len - 2)) {
            fail(d, event, MS_WSF_INVALID_PAYLOAD);
        } else {
            *event = (MsWsEvent){.kind = MS_WSE_CLOSE, .code = (uint16_t)code, .data = ms_bytes_of(payload.ptr + 2, payload.len - 2)};
        }
    }
}

static MsWsFailure inflate_failure(MsWsInflate rc) {
    if (rc == MS_WS_INFLATE_OVERFLOW) {
        return MS_WSF_OVERFLOW;
    }
    return rc == MS_WS_INFLATE_CORRUPT ? MS_WSF_CORRUPT : MS_WSF_NOMEM;
}

static void message_event(MsWsDecoder *d, MsWsEvent *event) {
    d->in_body = false;
    MsBytes data = ms_bytes_of(d->message.ptr, d->message.len);
    if (d->compressed) {
        d->inflated.len = 0;
        const MsWsInflate rc = ms_ws_inflate(&d->inflated, data, d->limit);
        if (rc != MS_WS_INFLATE_OK) {
            fail(d, event, inflate_failure(rc));
            return;
        }
        data = ms_bytes_of(d->inflated.ptr, d->inflated.len);
    }
    *event = (MsWsEvent){.kind = MS_WSE_MESSAGE, .text = d->kind == MS_WS_TEXT, .data = data};
}

void ms_ws_decoder_poll(MsWsDecoder *d, MsWsEvent *event) {
    *event = (MsWsEvent){.kind = MS_WSE_NEED_MORE};
    for (;;) {
        if (!d->in_payload) {
            if (!read_head(d, event)) {
                return;
            }
            continue;
        }
        if (!take_payload(d)) {
            fail(d, event, MS_WSF_NOMEM);
            return;
        }
        if (d->remaining > 0) {
            return;
        }
        d->in_payload = false;
        if (d->head.opcode >= MS_WS_CLOSE) {
            control_event(d, event);
            return;
        }
        if (d->head.fin) {
            message_event(d, event);
            return;
        }
    }
}
