/* Unit test for src/runtime/net/ws_codec.c: the RFC 6455 examples, length forms, fragmentation, the decoder's failures,
 * close events and permessage-deflate. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../net/ws_codec.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "ws_codec_test.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static const uint8_t KEY[4] = {0x37, 0xfa, 0x21, 0x3d};

static MsBytes bytes(const char *text) { return ms_bytes_of((const uint8_t *)text, strlen(text)); }
static MsBytes raw(const uint8_t *p, size_t n) { return ms_bytes_of(p, n); }

static bool same(MsBytes a, const char *text) { return a.len == strlen(text) && (a.len == 0 || memcmp(a.ptr, text, a.len) == 0); }

static void push(MsWsDecoder *d, const uint8_t *p, size_t n) { CHECK(ms_ws_decoder_push(d, raw(p, n))); }

static MsWsEvent poll(MsWsDecoder *d) {
    MsWsEvent event;
    ms_ws_decoder_poll(d, &event);
    return event;
}

static void test_rfc_examples(void) {
    MsWsBuf out = {0};
    CHECK(ms_ws_encode_frame(&out, MS_WS_TEXT, true, false, bytes("Hello"), NULL));
    const uint8_t plain[] = {0x81, 0x05, 'H', 'e', 'l', 'l', 'o'};
    CHECK(out.len == sizeof plain && memcmp(out.ptr, plain, sizeof plain) == 0);
    out.len = 0;
    CHECK(ms_ws_encode_frame(&out, MS_WS_TEXT, true, false, bytes("Hello"), KEY));
    const uint8_t masked[] = {0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58};
    CHECK(out.len == sizeof masked && memcmp(out.ptr, masked, sizeof masked) == 0);

    MsWsDecoder server, client;
    ms_ws_decoder_init(&server, true, false, 100);
    ms_ws_decoder_init(&client, false, false, 100);
    push(&server, masked, sizeof masked);
    MsWsEvent e = poll(&server);
    CHECK(e.kind == MS_WSE_MESSAGE && e.text && same(e.data, "Hello"));
    CHECK(poll(&server).kind == MS_WSE_NEED_MORE);

    const uint8_t first[] = {0x01, 0x03, 'H', 'e', 'l'}, last[] = {0x80, 0x02, 'l', 'o'};
    push(&client, first, sizeof first);
    CHECK(poll(&client).kind == MS_WSE_NEED_MORE && ms_ws_decoder_in_message(&client));
    push(&client, last, sizeof last);
    e = poll(&client);
    CHECK(e.kind == MS_WSE_MESSAGE && e.text && same(e.data, "Hello") && !ms_ws_decoder_in_message(&client));

    const uint8_t ping[] = {0x89, 0x05, 'H', 'e', 'l', 'l', 'o'}, pong[] = {0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58};
    push(&client, ping, sizeof ping);
    e = poll(&client);
    CHECK(e.kind == MS_WSE_PING && same(e.data, "Hello"));
    push(&server, pong, sizeof pong);
    e = poll(&server);
    CHECK(e.kind == MS_WSE_PONG && same(e.data, "Hello"));
    ms_ws_buf_free(&out);
    ms_ws_decoder_free(&server);
    ms_ws_decoder_free(&client);
}

static void test_length_forms_and_byte_at_a_time(void) {
    uint8_t *payload = malloc(65536);
    memset(payload, 7, 65536);
    MsWsBuf out = {0};
    CHECK(ms_ws_encode_frame(&out, MS_WS_BINARY, true, false, raw(payload, 256), NULL));
    CHECK(out.ptr[1] == 126 && out.ptr[2] == 1 && out.ptr[3] == 0);
    out.len = 0;
    CHECK(ms_ws_encode_frame(&out, MS_WS_BINARY, true, false, raw(payload, 65536), NULL));
    CHECK(out.ptr[1] == 127 && out.ptr[7] == 1);
    MsWsDecoder d;
    ms_ws_decoder_init(&d, false, false, 1 << 20);
    for (size_t i = 0; i < out.len; i++) {
        CHECK(poll(&d).kind == MS_WSE_NEED_MORE);
        push(&d, out.ptr + i, 1);
    }
    MsWsEvent e = poll(&d);
    CHECK(e.kind == MS_WSE_MESSAGE && !e.text && e.data.len == 65536 && memcmp(e.data.ptr, payload, 65536) == 0);
    ms_ws_decoder_free(&d);
    ms_ws_buf_free(&out);
    free(payload);
}

static void test_failures(void) {
    MsWsDecoder d;
    const uint8_t nonminimal[] = {0x82, 126, 0x00, 0x05};
    ms_ws_decoder_init(&d, false, false, UINT64_MAX);
    push(&d, nonminimal, sizeof nonminimal);
    MsWsEvent e = poll(&d);
    CHECK(e.kind == MS_WSE_FAIL && e.failure == MS_WSF_PROTOCOL && !strcmp(e.reason, "nonminimal payload length") && !e.body);
    ms_ws_decoder_free(&d);

    /* a masked frame to a client, and RSV1 without deflate, are reported together */
    const uint8_t bad[] = {0xc1, 0x80};
    ms_ws_decoder_init(&d, false, false, 10);
    push(&d, bad, sizeof bad);
    e = poll(&d);
    CHECK(e.kind == MS_WSE_FAIL && !strcmp(e.reason, "RSV1 set, bad MASK"));
    ms_ws_decoder_free(&d);

    /* over the limit: on the wire, summed over fragments; the second frame fails with body set */
    const uint8_t a[] = {0x01, 0x03, 'a', 'b', 'c'}, b[] = {0x80, 0x03, 'd', 'e', 'f'};
    ms_ws_decoder_init(&d, false, false, 5);
    push(&d, a, sizeof a);
    CHECK(poll(&d).kind == MS_WSE_NEED_MORE);
    push(&d, b, sizeof b);
    e = poll(&d);
    CHECK(e.kind == MS_WSE_FAIL && e.failure == MS_WSF_LIMIT && e.reply_close && e.body);
    ms_ws_decoder_free(&d);

    const uint8_t huge[] = {0x82, 127, 0x80, 0, 0, 0, 0, 0, 0, 0};
    ms_ws_decoder_init(&d, false, false, UINT64_MAX);
    push(&d, huge, sizeof huge);
    e = poll(&d);
    CHECK(e.kind == MS_WSE_FAIL && e.failure == MS_WSF_LIMIT && e.reply_close);
    ms_ws_decoder_free(&d);
}

static void test_close_events(void) {
    MsWsDecoder d;
    ms_ws_decoder_init(&d, false, false, 100);
    const uint8_t none[] = {0x88, 0x00};
    push(&d, none, sizeof none);
    MsWsEvent e = poll(&d);
    CHECK(e.kind == MS_WSE_CLOSE && e.code == 1005 && e.data.len == 0);
    const uint8_t with_reason[] = {0x88, 0x05, 0x03, 0xe8, 'b', 'y', 'e'};
    push(&d, with_reason, sizeof with_reason);
    e = poll(&d);
    CHECK(e.kind == MS_WSE_CLOSE && e.code == 1000 && same(e.data, "bye"));
    const uint8_t one_byte[] = {0x88, 0x01, 0x03};
    push(&d, one_byte, sizeof one_byte);
    e = poll(&d);
    CHECK(e.kind == MS_WSE_FAIL && !strcmp(e.reason, "close payload has one byte"));
    ms_ws_decoder_free(&d);

    ms_ws_decoder_init(&d, false, false, 100);
    const uint8_t bad_code[] = {0x88, 0x02, 0x03, 0xed};
    push(&d, bad_code, sizeof bad_code);
    e = poll(&d);
    CHECK(e.kind == MS_WSE_FAIL && !strcmp(e.reason, "bad close code 1005"));
    ms_ws_decoder_free(&d);

    ms_ws_decoder_init(&d, false, false, 100);
    const uint8_t bad_utf8[] = {0x88, 0x03, 0x03, 0xe8, 0xff};
    push(&d, bad_utf8, sizeof bad_utf8);
    e = poll(&d);
    CHECK(e.kind == MS_WSE_FAIL && e.failure == MS_WSF_INVALID_PAYLOAD);
    ms_ws_decoder_free(&d);

    char text[96];
    ms_ws_close_text(1006, bytes("unexpected EOF"), text, sizeof text);
    CHECK(!strcmp(text, "websocket: close 1006 (abnormal closure): unexpected EOF"));
    ms_ws_close_text(4001, bytes(""), text, sizeof text);
    CHECK(!strcmp(text, "websocket: close 4001"));
    MsWsBuf out = {0};
    CHECK(ms_ws_format_close(&out, 1005, bytes("x")) && out.len == 0);
    CHECK(ms_ws_format_close(&out, 1001, bytes("go")) && out.len == 4 && out.ptr[0] == 0x03 && out.ptr[1] == 0xe9);
    ms_ws_buf_free(&out);
}

static void test_control_frames(void) {
    MsWsBuf out = {0};
    bool too_long = false;
    uint8_t big[126] = {0};
    CHECK(!ms_ws_encode_control(&out, MS_WS_PING, raw(big, 126), false, &too_long) && too_long);
    CHECK(ms_ws_encode_control(&out, MS_WS_PING, raw(big, 125), true, &too_long) && !too_long && out.len == 2 + 4 + 125);
    CHECK(out.ptr[0] == 0x89 && out.ptr[1] == (0x80 | 125));
    ms_ws_buf_free(&out);
}

static void test_deflate(void) {
    char text[4000];
    for (size_t i = 0; i < sizeof text; i++) {
        text[i] = (char)('a' + i % 7);
    }
    MsWsBuf compressed = {0}, wire = {0};
    CHECK(ms_ws_deflate(&compressed, raw((const uint8_t *)text, sizeof text)));
    CHECK(compressed.len > 0 && compressed.len < sizeof text / 4);
    CHECK(!(compressed.len >= 4 && !memcmp(compressed.ptr + compressed.len - 4, "\x00\x00\xff\xff", 4)));

    CHECK(ms_ws_encode_message(&wire, MS_WS_TEXT, raw((const uint8_t *)text, sizeof text), true, true));
    CHECK((wire.ptr[0] & 0x40) != 0);
    MsWsDecoder server;
    ms_ws_decoder_init(&server, true, true, 1 << 20);
    push(&server, wire.ptr, wire.len);
    MsWsEvent e = poll(&server);
    CHECK(e.kind == MS_WSE_MESSAGE && e.text && e.data.len == sizeof text && memcmp(e.data.ptr, text, sizeof text) == 0);
    ms_ws_decoder_free(&server);

    /* the same message over a smaller limit overflows after inflation */
    ms_ws_decoder_init(&server, true, true, 1000);
    push(&server, wire.ptr, wire.len);
    e = poll(&server);
    CHECK(e.kind == MS_WSE_FAIL && e.failure == MS_WSF_OVERFLOW);
    ms_ws_decoder_free(&server);

    /* garbage that claims to be deflated */
    MsWsBuf junk = {0};
    const uint8_t garbage[] = {0xff, 0xff, 0xff, 0xff};
    CHECK(ms_ws_encode_frame(&junk, MS_WS_BINARY, true, true, raw(garbage, sizeof garbage), KEY));
    ms_ws_decoder_init(&server, true, true, 1 << 20);
    push(&server, junk.ptr, junk.len);
    e = poll(&server);
    CHECK(e.kind == MS_WSE_FAIL && e.failure == MS_WSF_CORRUPT);
    ms_ws_decoder_free(&server);

    /* an empty message round-trips */
    wire.len = 0;
    CHECK(ms_ws_encode_message(&wire, MS_WS_BINARY, raw(NULL, 0), false, true));
    MsWsDecoder client;
    ms_ws_decoder_init(&client, false, true, 100);
    push(&client, wire.ptr, wire.len);
    e = poll(&client);
    CHECK(e.kind == MS_WSE_MESSAGE && !e.text && e.data.len == 0);
    ms_ws_decoder_free(&client);
    ms_ws_buf_free(&compressed);
    ms_ws_buf_free(&wire);
    ms_ws_buf_free(&junk);
}

int main(void) {
    test_rfc_examples();
    test_length_forms_and_byte_at_a_time();
    test_failures();
    test_close_events();
    test_control_frames();
    test_deflate();
    puts("ws_codec_test: ok");
    return 0;
}
