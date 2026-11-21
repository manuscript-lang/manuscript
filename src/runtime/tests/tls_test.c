/* Unit tests for src/runtime/net/tls.c: a client and a server handshake through memory, exchange data both ways,
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

    /* ALPN: the server picks its first protocol the client offered; none when they share none */
    MsTlsCtx *salpn = ms_tls_ctx_new(1, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, NULL, 0);
    MsTlsCtx *calpn = ms_tls_ctx_new(0, NULL, 0, NULL, 0, CERT, sizeof CERT - 1);
    CHECK(ms_tls_ctx_set_alpn(salpn, "h2,http/1.1") == 0 && ms_tls_ctx_set_alpn(calpn, "http/1.1,spdy/3") == 0);
    CHECK(ms_tls_ctx_set_alpn(calpn, "a,,b") == -1);
    CHECK(ms_tls_ctx_set_alpn(calpn, "http/1.1,spdy/3") == 0);
    c = ms_tls_new(calpn, "localhost"); s = ms_tls_new(salpn, NULL);
    CHECK(handshake(c, s) == MS_TLS_DONE);
    CHECK(ms_bytes_equal(ms_tls_alpn(c), ms_bytes_of((const uint8_t *)"http/1.1", 8)));
    CHECK(ms_bytes_equal(ms_tls_alpn(s), ms_bytes_of((const uint8_t *)"http/1.1", 8)));
    ms_tls_free(c); ms_tls_free(s);
    CHECK(ms_tls_ctx_set_alpn(calpn, "h2") == 0);
    c = ms_tls_new(calpn, "localhost"); s = ms_tls_new(salpn, NULL);
    CHECK(handshake(c, s) == MS_TLS_DONE && ms_tls_alpn(c).len == 2 && ms_tls_alpn(s).len == 2);
    ms_tls_free(c); ms_tls_free(s);
    CHECK(ms_tls_ctx_set_alpn(calpn, "spdy/3") == 0);
    c = ms_tls_new(calpn, "localhost"); s = ms_tls_new(salpn, NULL);
    CHECK(handshake(c, s) == MS_TLS_DONE && ms_tls_alpn(c).len == 0 && ms_tls_alpn(s).len == 0);
    ms_tls_free(c); ms_tls_free(s);
    ms_tls_ctx_free(salpn); ms_tls_ctx_free(calpn);

    /* mutual TLS: a server that requires client certificates, a client that presents one, and one that does not */
    MsTlsCtx *mserver = ms_tls_ctx_new(1, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, NULL, 0);
    MsTlsCtx *mclient = ms_tls_ctx_new(0, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, CERT, sizeof CERT - 1);
    CHECK(mserver && mclient && ms_tls_ctx_verify_clients(mserver, CERT, sizeof CERT - 1, 1) == 0);
    CHECK(ms_tls_ctx_verify_clients(cctx, CERT, sizeof CERT - 1, 1) == -1); /* a client context has no clients */
    c = ms_tls_new(mclient, "localhost"); s = ms_tls_new(mserver, NULL);
    CHECK(handshake(c, s) == MS_TLS_DONE && ms_tls_verified(s) == 1 && ms_tls_verified(c) == 1);
    ms_tls_free(c); ms_tls_free(s);
    c = ms_tls_new(cctx, "localhost"); s = ms_tls_new(mserver, NULL);
    CHECK(handshake(c, s) != MS_TLS_DONE);
    ms_tls_free(c); ms_tls_free(s);
    MsTlsCtx *optional = ms_tls_ctx_new(1, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, NULL, 0);
    CHECK(optional && ms_tls_ctx_verify_clients(optional, CERT, sizeof CERT - 1, 0) == 0);
    c = ms_tls_new(cctx, "localhost"); s = ms_tls_new(optional, NULL);
    CHECK(handshake(c, s) == MS_TLS_DONE && ms_tls_verified(s) == 0); /* none offered, none required */
    ms_tls_free(c); ms_tls_free(s);
    ms_tls_ctx_free(mserver); ms_tls_ctx_free(mclient); ms_tls_ctx_free(optional);

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
