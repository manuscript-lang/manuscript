/* Unit tests for runtime/net/tls.c: a client and a server handshake through memory, exchange data both ways,
   refuse a wrong host name and an untrusted certificate, and close cleanly. */
#include <stdio.h>
#include <string.h>
#include "../net/tls.h"
#include "test_cert.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

/* Moves pending ciphertext one way. */
static void pump(MsTls *from, MsTls *to) {
    char b[4096];
    long n;
    while ((n = ms_tls_outgoing(from, b, sizeof b)) > 0) ms_tls_incoming(to, b, (size_t)n);
}

/* Runs both handshakes to the end. */
static int handshake(MsTls *c, MsTls *s) {
    int cs = MS_TLS_WANT_IO, ss = MS_TLS_WANT_IO;
    for (int i = 0; i < 20 && (cs == MS_TLS_WANT_IO || ss == MS_TLS_WANT_IO); i++) {
        if (cs == MS_TLS_WANT_IO) cs = ms_tls_handshake(c);
        pump(c, s);
        if (ss == MS_TLS_WANT_IO) ss = ms_tls_handshake(s);
        pump(s, c);
        if (cs < 0 || ss < 0) break;
    }
    return cs == MS_TLS_DONE && ss == MS_TLS_DONE ? MS_TLS_DONE : (cs < 0 ? cs : ss);
}

int main(void) {
    MsTlsCtx *sctx = ms_tls_ctx_new(1, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, NULL, 0);
    MsTlsCtx *cctx = ms_tls_ctx_new(0, NULL, 0, NULL, 0, CERT, sizeof CERT - 1);
    MsTlsCtx *bare = ms_tls_ctx_new(0, NULL, 0, NULL, 0, NULL, 0); /* system store: does not trust the test cert */
    CHECK(sctx && cctx && bare);
    CHECK(ms_tls_ctx_new(1, CERT, sizeof CERT - 1, CERT, sizeof CERT - 1, NULL, 0) == NULL); /* key is not a key */
    CHECK(ms_tls_ctx_new(1, NULL, 0, NULL, 0, NULL, 0) == NULL);

    MsTls *c = ms_tls_new(cctx, "localhost"), *s = ms_tls_new(sctx, NULL);
    CHECK(handshake(c, s) == MS_TLS_DONE);
    char b[64];
    CHECK(ms_tls_read(s, b, sizeof b) == MS_TLS_WANT_IO); /* nothing yet: wait, not an error */
    CHECK(ms_tls_write(c, "ping", 4) == 4);
    pump(c, s);
    CHECK(ms_tls_read(s, b, sizeof b) == 4 && !memcmp(b, "ping", 4));
    CHECK(ms_tls_write(s, "pong!", 5) == 5);
    pump(s, c);
    CHECK(ms_tls_read(c, b, sizeof b) == 5 && !memcmp(b, "pong!", 5));
    CHECK(ms_tls_shutdown(c) >= 0);
    pump(c, s);
    CHECK(ms_tls_read(s, b, sizeof b) == MS_TLS_CLOSED);
    ms_tls_free(c); ms_tls_free(s);

    /* wrong host name */
    c = ms_tls_new(cctx, "example.invalid"); s = ms_tls_new(sctx, NULL);
    CHECK(handshake(c, s) == MS_TLS_ERROR && ms_tls_error(c)[0] != 0);
    ms_tls_free(c); ms_tls_free(s);

    /* untrusted certificate */
    c = ms_tls_new(bare, "localhost"); s = ms_tls_new(sctx, NULL);
    CHECK(handshake(c, s) == MS_TLS_ERROR);
    ms_tls_free(c); ms_tls_free(s);

    /* garbage from the network */
    s = ms_tls_new(sctx, NULL);
    ms_tls_incoming(s, "GET / HTTP/1.1\r\n\r\n", 18);
    CHECK(ms_tls_handshake(s) == MS_TLS_ERROR);
    ms_tls_free(s);

    ms_tls_ctx_free(sctx); ms_tls_ctx_free(cctx); ms_tls_ctx_free(bare);
    if (!failed) printf("tls ok\n");
    return failed;
}
