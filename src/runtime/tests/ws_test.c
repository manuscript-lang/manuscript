/* Unit tests for src/runtime/net/ws.c: the RFC 6455 examples, the checks and texts of the Rust decoder, masking. */
#include <stdio.h>
#include <string.h>
#include "../net/ws.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

static int parse(MsWsState *s, const uint8_t *b, size_t n, MsWsHead *h, char *r) { return ms_ws_parse_head(s, b, n, h, r, 96); }

int main(void) {
    MsWsHead h; char r[96]; MsWsState srv = {1, 0, 0}, cli = {0, 0, 0};
    /* RFC 6455 5.7: masked "Hello", unmasked "Hello" */
    const uint8_t masked[] = {0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58};
    CHECK(parse(&srv, masked, sizeof masked, &h, r) == MS_WS_OK && h.fin && h.opcode == MS_WS_TEXT && h.masked);
    CHECK(h.payload_len == 5 && h.head_len == 6);
    uint8_t body[5]; memcpy(body, masked + 6, 5);
    ms_ws_unmask(body, 5, h.mask, 0);
    CHECK(!memcmp(body, "Hello", 5));
    uint8_t split[5]; memcpy(split, masked + 6, 5); /* unmask in two parts */
    ms_ws_unmask(split, 2, h.mask, 0); ms_ws_unmask(split + 2, 3, h.mask, 2);
    CHECK(!memcmp(split, "Hello", 5));
    const uint8_t plain[] = {0x81, 0x05, 'H', 'e', 'l', 'l', 'o'};
    CHECK(parse(&cli, plain, sizeof plain, &h, r) == MS_WS_OK && h.head_len == 2 && !h.masked);

    /* every prefix of a header is partial */
    for (size_t n = 0; n < 6; n++) CHECK(parse(&srv, masked, n, &h, r) == MS_WS_PARTIAL);

    /* wrong masking direction fails at once, from the first two bytes */
    CHECK(parse(&cli, masked, 2, &h, r) == MS_WS_BAD && !strcmp(r, "bad MASK"));
    CHECK(parse(&srv, plain, 2, &h, r) == MS_WS_BAD && !strcmp(r, "bad MASK"));

    /* reasons are collected in order */
    const uint8_t rsv[] = {0xf1, 0x00};
    CHECK(parse(&cli, rsv, 2, &h, r) == MS_WS_BAD && !strcmp(r, "RSV1 set, RSV2 set, RSV3 set"));
    const uint8_t badop[] = {0x83, 0x00};
    CHECK(parse(&cli, badop, 2, &h, r) == MS_WS_BAD && !strcmp(r, "bad opcode 3"));
    const uint8_t longping[] = {0x09, 126};
    CHECK(parse(&cli, longping, 2, &h, r) == MS_WS_BAD && !strcmp(r, "len > 125 for control, FIN not set on control"));
    const uint8_t cont[] = {0x80, 0x00};
    CHECK(parse(&cli, cont, 2, &h, r) == MS_WS_BAD && !strcmp(r, "continuation after FIN"));

    /* fragmentation state */
    const uint8_t first[] = {0x01, 0x00};
    CHECK(parse(&cli, first, 2, &h, r) == MS_WS_OK);
    ms_ws_after_head(&cli, &h);
    CHECK(cli.fragmenting);
    CHECK(parse(&cli, plain, sizeof plain, &h, r) == MS_WS_BAD && !strcmp(r, "data before FIN"));
    CHECK(parse(&cli, cont, 2, &h, r) == MS_WS_OK);
    ms_ws_after_head(&cli, &h);
    CHECK(!cli.fragmenting);

    /* deflate: RSV1 only on data frames when negotiated */
    MsWsState z = {0, 1, 0};
    const uint8_t rsv1text[] = {0xc1, 0x00}, rsv1ping[] = {0xc9, 0x00};
    CHECK(parse(&z, rsv1text, 2, &h, r) == MS_WS_OK && h.compressed);
    CHECK(parse(&z, rsv1ping, 2, &h, r) == MS_WS_BAD);

    /* lengths: 16-bit and 64-bit forms, and the minimal-length rule */
    uint8_t big[16];
    size_t n = ms_ws_write_head(big, MS_WS_BINARY, 1, 0, 300, NULL);
    CHECK(n == 4 && parse(&cli, big, n, &h, r) == MS_WS_OK && h.payload_len == 300);
    n = ms_ws_write_head(big, MS_WS_BINARY, 1, 0, 70000, NULL);
    CHECK(n == 10 && parse(&cli, big, n, &h, r) == MS_WS_OK && h.payload_len == 70000);
    const uint8_t mask[4] = {1, 2, 3, 4};
    n = ms_ws_write_head(big, MS_WS_TEXT, 0, 1, 5, mask);
    CHECK(n == 6 && big[0] == 0x41 && big[1] == 0x85 && !memcmp(big + 2, mask, 4));
    const uint8_t nonmin[] = {0x82, 126, 0x00, 0x05};
    CHECK(parse(&cli, nonmin, sizeof nonmin, &h, r) == MS_WS_BAD && !strcmp(r, "nonminimal payload length"));
    const uint8_t huge[] = {0x82, 127, 0x80, 0, 0, 0, 0, 0, 0, 0};
    CHECK(parse(&cli, huge, sizeof huge, &h, r) == MS_WS_TOO_BIG);

    /* close codes */
    CHECK(ms_ws_valid_close_code(1000) && ms_ws_valid_close_code(1013) && ms_ws_valid_close_code(3000) && ms_ws_valid_close_code(4999));
    CHECK(!ms_ws_valid_close_code(1004) && !ms_ws_valid_close_code(1005) && !ms_ws_valid_close_code(1006) && !ms_ws_valid_close_code(1015) && !ms_ws_valid_close_code(999) && !ms_ws_valid_close_code(5000));

    /* RFC 6455 1.3 handshake example */
    char accept[29];
    CHECK(ms_ws_accept_key("dGhlIHNhbXBsZSBub25jZQ==", 24, accept) == 0 && !strcmp(accept, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="));
    if (!failed) printf("ws ok\n");
    return failed;
}
