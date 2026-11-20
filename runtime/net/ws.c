#include "ws.h"
#include <openssl/evp.h>
#include <stdio.h>
#include <string.h>

static void add(char *reason, size_t cap, size_t *n, const char *text) {
    size_t t = strlen(text);
    if (*n && *n + 2 < cap) { reason[(*n)++] = ','; reason[(*n)++] = ' '; }
    if (*n + t < cap) { memcpy(reason + *n, text, t); *n += t; }
    if (cap) reason[*n < cap ? *n : cap - 1] = 0;
}

/* Bytes of extended payload length that follow the two-byte head for this 7-bit length field. */
static size_t extended_length_bytes(uint64_t shortlen) {
    if (shortlen == 126) return 2;
    if (shortlen == 127) return 8;
    return 0;
}

int ms_ws_parse_head(const MsWsState *s, const uint8_t *buf, size_t len, MsWsHead *out, char *reason, size_t cap) {
    if (cap) reason[0] = 0;
    if (len < 2) return MS_WS_PARTIAL;
    uint8_t b0 = buf[0], b1 = buf[1];
    uint8_t opcode = b0 & 0x0f, fin = b0 >> 7, masked = b1 >> 7, shortlen = b1 & 0x7f;
    size_t n = 0;
    char text[24];
    if (b0 & 0x40 && (!s->deflate || (opcode != MS_WS_TEXT && opcode != MS_WS_BINARY))) add(reason, cap, &n, "RSV1 set");
    if (b0 & 0x20) add(reason, cap, &n, "RSV2 set");
    if (b0 & 0x10) add(reason, cap, &n, "RSV3 set");
    switch (opcode) {
    case MS_WS_CLOSE: case MS_WS_PING: case MS_WS_PONG:
        if (shortlen > 125) add(reason, cap, &n, "len > 125 for control");
        if (!fin) add(reason, cap, &n, "FIN not set on control");
        break;
    case MS_WS_TEXT: case MS_WS_BINARY:
        if (s->fragmenting) add(reason, cap, &n, "data before FIN");
        break;
    case MS_WS_CONT:
        if (!s->fragmenting) add(reason, cap, &n, "continuation after FIN");
        break;
    default:
        snprintf(text, sizeof text, "bad opcode %u", opcode);
        add(reason, cap, &n, text);
    }
    if ((masked != 0) != (s->server != 0)) add(reason, cap, &n, "bad MASK");
    if (n) return MS_WS_BAD;

    size_t ext = extended_length_bytes(shortlen);
    size_t total = 2 + ext + (masked ? 4 : 0);
    if (len < total) return MS_WS_PARTIAL;
    uint64_t length = shortlen;
    if (ext) {
        length = 0;
        for (size_t i = 0; i < ext; i++) length = length << 8 | buf[2 + i];
    }
    if ((shortlen == 126 && length < 126) || (shortlen == 127 && length < 65536)) {
        add(reason, cap, &n, "nonminimal payload length");
        return MS_WS_BAD;
    }
    if (length > (uint64_t)INT64_MAX) {
        return MS_WS_TOO_BIG;
    }
    memset(out, 0, sizeof *out);
    out->fin = fin; out->opcode = opcode; out->masked = masked; out->payload_len = length; out->head_len = (uint32_t)total;
    out->compressed = (b0 & 0x40) != 0 && s->deflate;
    if (masked) memcpy(out->mask, buf + 2 + ext, 4);
    return MS_WS_OK;
}

void ms_ws_after_head(MsWsState *s, const MsWsHead *h) {
    if (h->opcode == MS_WS_TEXT || h->opcode == MS_WS_BINARY || h->opcode == MS_WS_CONT) s->fragmenting = !h->fin;
}

void ms_ws_unmask(uint8_t *buf, size_t n, const uint8_t mask[4], uint64_t pos) {
    for (size_t i = 0; i < n; i++) buf[i] ^= mask[(pos + i) & 3];
}

size_t ms_ws_write_head(uint8_t *dst, uint8_t opcode, int fin, int compressed, uint64_t len, const uint8_t *mask) {
    size_t n = 0;
    dst[n++] = (uint8_t)((fin ? 0x80 : 0) | (compressed ? 0x40 : 0) | (opcode & 0x0f));
    uint8_t m = mask ? 0x80 : 0;
    if (len < 126) dst[n++] = m | (uint8_t)len;
    else if (len < 65536) { dst[n++] = m | 126; dst[n++] = (uint8_t)(len >> 8); dst[n++] = (uint8_t)len; }
    else { dst[n++] = m | 127; for (int sh = 56; sh >= 0; sh -= 8) dst[n++] = (uint8_t)(len >> sh); }
    if (mask) { memcpy(dst + n, mask, 4); n += 4; }
    return n;
}

int ms_ws_valid_close_code(unsigned c) {
    return (c >= 1000 && c <= 1003) || (c >= 1007 && c <= 1013) || (c >= 3000 && c <= 4999);
}

int ms_ws_accept_key(const char *key, size_t key_len, char out[29]) {
    static const char guid[] = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    unsigned char buf[256], md[20];
    unsigned int mdl = 0;
    if (key_len > 128) return -1;
    memcpy(buf, key, key_len);
    memcpy(buf + key_len, guid, sizeof guid - 1);
    if (!EVP_Digest(buf, key_len + sizeof guid - 1, md, &mdl, EVP_sha1(), NULL) || mdl != 20) return -1;
    return EVP_EncodeBlock((unsigned char *)out, md, 20) == 28 ? 0 : -1;
}
