#include "tls.h"
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509_vfy.h>
#include <stdlib.h>
#include <string.h>

struct ms_tls_ctx { SSL_CTX *ssl; int server; };
struct ms_tls { SSL *ssl; BIO *in, *out; char err[160]; };

static X509 *first_cert(const char *pem, size_t n, STACK_OF(X509) *rest) {
    BIO *b = BIO_new_mem_buf(pem, (int)n);
    X509 *first = NULL, *c;
    if (!b) return NULL;
    while ((c = PEM_read_bio_X509(b, NULL, NULL, NULL)) != NULL) {
        if (!first) first = c;
        else if (rest) sk_X509_push(rest, c);
        else X509_free(c);
    }
    BIO_free(b);
    ERR_clear_error();
    return first;
}

ms_tls_ctx *ms_tls_ctx_new(int server, const char *cert_pem, size_t cert_len, const char *key_pem, size_t key_len,
                           const char *ca_pem, size_t ca_len) {
    ms_tls_ctx *ctx = calloc(1, sizeof *ctx);
    if (!ctx) return NULL;
    ctx->server = server;
    ctx->ssl = SSL_CTX_new(server ? TLS_server_method() : TLS_client_method());
    if (!ctx->ssl) goto fail;
    SSL_CTX_set_min_proto_version(ctx->ssl, TLS1_2_VERSION);
    SSL_CTX_set_mode(ctx->ssl, SSL_MODE_RELEASE_BUFFERS | SSL_MODE_ENABLE_PARTIAL_WRITE | SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);
    SSL_CTX_set_session_cache_mode(ctx->ssl, SSL_SESS_CACHE_OFF);
    SSL_CTX_set_options(ctx->ssl, SSL_OP_NO_TICKET | SSL_OP_NO_COMPRESSION | SSL_OP_NO_RENEGOTIATION);
    if (server) {
        STACK_OF(X509) *chain = sk_X509_new_null();
        X509 *leaf = cert_pem ? first_cert(cert_pem, cert_len, chain) : NULL;
        BIO *kb = key_pem ? BIO_new_mem_buf(key_pem, (int)key_len) : NULL;
        EVP_PKEY *key = kb ? PEM_read_bio_PrivateKey(kb, NULL, NULL, NULL) : NULL;
        int ok = leaf && key && SSL_CTX_use_certificate(ctx->ssl, leaf) == 1 && SSL_CTX_use_PrivateKey(ctx->ssl, key) == 1 &&
                 SSL_CTX_check_private_key(ctx->ssl) == 1;
        for (int i = 0; ok && i < sk_X509_num(chain); i++) ok = SSL_CTX_add_extra_chain_cert(ctx->ssl, X509_dup(sk_X509_value(chain, i))) == 1;
        sk_X509_pop_free(chain, X509_free);
        X509_free(leaf); EVP_PKEY_free(key); BIO_free(kb);
        if (!ok) goto fail;
    } else {
        SSL_CTX_set_verify(ctx->ssl, SSL_VERIFY_PEER, NULL);
        if (ca_pem) {
            X509_STORE *store = SSL_CTX_get_cert_store(ctx->ssl);
            STACK_OF(X509) *cas = sk_X509_new_null();
            X509 *c = first_cert(ca_pem, ca_len, cas);
            int ok = c != NULL && X509_STORE_add_cert(store, c) == 1;
            for (int i = 0; ok && i < sk_X509_num(cas); i++) ok = X509_STORE_add_cert(store, sk_X509_value(cas, i)) == 1;
            X509_free(c);
            sk_X509_pop_free(cas, X509_free);
            if (!ok) goto fail;
        } else if (SSL_CTX_set_default_verify_paths(ctx->ssl) != 1) goto fail;
    }
    return ctx;
fail:
    ERR_clear_error();
    ms_tls_ctx_free(ctx);
    return NULL;
}

void ms_tls_ctx_free(ms_tls_ctx *ctx) {
    if (!ctx) return;
    SSL_CTX_free(ctx->ssl);
    free(ctx);
}

ms_tls *ms_tls_new(ms_tls_ctx *ctx, const char *host) {
    ms_tls *t = calloc(1, sizeof *t);
    if (!t) return NULL;
    t->ssl = SSL_new(ctx->ssl);
    t->in = BIO_new(BIO_s_mem());
    t->out = BIO_new(BIO_s_mem());
    if (!t->ssl || !t->in || !t->out) { BIO_free(t->in); BIO_free(t->out); SSL_free(t->ssl); free(t); return NULL; }
    BIO_set_mem_eof_return(t->in, -1); /* an empty input BIO means "retry", not end of file */
    SSL_set_bio(t->ssl, t->in, t->out); /* the SSL owns both BIOs from here */
    if (ctx->server) SSL_set_accept_state(t->ssl);
    else {
        SSL_set_connect_state(t->ssl);
        if (host && *host) {
            SSL_set_tlsext_host_name(t->ssl, host);
            SSL_set1_host(t->ssl, host);
        }
    }
    return t;
}

void ms_tls_free(ms_tls *t) {
    if (!t) return;
    SSL_free(t->ssl);
    free(t);
}

long ms_tls_incoming(ms_tls *t, const void *buf, size_t n) {
    if (n > 0x7fffffff) return -1;
    int w = BIO_write(t->in, buf, (int)n);
    return w < 0 ? -1 : w;
}

long ms_tls_outgoing(ms_tls *t, void *buf, size_t cap) {
    if (cap > 0x7fffffff) cap = 0x7fffffff;
    if (BIO_ctrl_pending(t->out) == 0) return 0;
    int r = BIO_read(t->out, buf, (int)cap);
    return r < 0 ? 0 : r;
}

static void note(ms_tls *t) {
    unsigned long e = ERR_get_error();
    if (e) ERR_error_string_n(e, t->err, sizeof t->err);
    ERR_clear_error();
}

static int classify(ms_tls *t, int rc) {
    int e = SSL_get_error(t->ssl, rc);
    if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE) return MS_TLS_WANT_IO;
    if (e == SSL_ERROR_ZERO_RETURN) return MS_TLS_CLOSED;
    note(t);
    if (!t->err[0]) strcpy(t->err, "TLS I/O error");
    return MS_TLS_ERROR;
}

int ms_tls_handshake(ms_tls *t) {
    int rc = SSL_do_handshake(t->ssl);
    return rc == 1 ? MS_TLS_DONE : classify(t, rc);
}

long ms_tls_read(ms_tls *t, void *buf, size_t n) {
    if (n > 0x7fffffff) n = 0x7fffffff;
    int rc = SSL_read(t->ssl, buf, (int)n);
    return rc > 0 ? rc : classify(t, rc);
}

long ms_tls_write(ms_tls *t, const void *buf, size_t n) {
    if (n > 0x7fffffff) n = 0x7fffffff;
    int rc = SSL_write(t->ssl, buf, (int)n);
    return rc > 0 ? rc : classify(t, rc);
}

int ms_tls_shutdown(ms_tls *t) { return SSL_shutdown(t->ssl) >= 0 ? 0 : -1; }
const char *ms_tls_error(ms_tls *t) { return t->err; }
