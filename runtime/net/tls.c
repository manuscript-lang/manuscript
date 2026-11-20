#include "tls.h"
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509_vfy.h>
#include <openssl/x509v3.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/safe.h"

struct MsTlsCtx {
    SSL_CTX *ssl;
    int server;
    uint8_t alpn[MS_TLS_ALPN_MAX]; /* the protocols in wire format: a length byte before each name */
    size_t alpn_len;
};
struct MsTls { SSL *ssl; BIO *in, *out; char err[160]; };

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

/* The certificate chain and private key this side presents; false when either is missing or they do not match. */
static bool use_identity(SSL_CTX *ssl, const char *cert_pem, size_t cert_len, const char *key_pem, size_t key_len) {
    STACK_OF(X509) *chain = sk_X509_new_null();
    X509 *leaf = cert_pem ? first_cert(cert_pem, cert_len, chain) : NULL;
    BIO *kb = key_pem ? BIO_new_mem_buf(key_pem, (int)key_len) : NULL;
    EVP_PKEY *key = kb ? PEM_read_bio_PrivateKey(kb, NULL, NULL, NULL) : NULL;
    bool ok = leaf && key && SSL_CTX_use_certificate(ssl, leaf) == 1 && SSL_CTX_use_PrivateKey(ssl, key) == 1 &&
              SSL_CTX_check_private_key(ssl) == 1;
    for (int i = 0; ok && i < sk_X509_num(chain); i++) ok = SSL_CTX_add_extra_chain_cert(ssl, X509_dup(sk_X509_value(chain, i))) == 1;
    sk_X509_pop_free(chain, X509_free);
    X509_free(leaf);
    EVP_PKEY_free(key);
    BIO_free(kb);
    return ok;
}

MsTlsCtx *ms_tls_ctx_new(int server, const char *cert_pem, size_t cert_len, const char *key_pem, size_t key_len,
                           const char *ca_pem, size_t ca_len) {
    MsTlsCtx *ctx = calloc(1, sizeof *ctx);
    if (!ctx) return NULL;
    ctx->server = server;
    ctx->ssl = SSL_CTX_new(server ? TLS_server_method() : TLS_client_method());
    if (!ctx->ssl) goto fail;
    SSL_CTX_set_min_proto_version(ctx->ssl, TLS1_2_VERSION);
    SSL_CTX_set_mode(ctx->ssl, SSL_MODE_RELEASE_BUFFERS | SSL_MODE_ENABLE_PARTIAL_WRITE | SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);
    SSL_CTX_set_session_cache_mode(ctx->ssl, SSL_SESS_CACHE_OFF);
    SSL_CTX_set_options(ctx->ssl, SSL_OP_NO_TICKET | SSL_OP_NO_COMPRESSION | SSL_OP_NO_RENEGOTIATION);
    if (server) {
        if (!use_identity(ctx->ssl, cert_pem, cert_len, key_pem, key_len)) goto fail;
    } else {
        SSL_CTX_set_verify(ctx->ssl, SSL_VERIFY_PEER, NULL);
        if (cert_pem && cert_len > 0 && !use_identity(ctx->ssl, cert_pem, cert_len, key_pem, key_len)) goto fail;
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

int ms_tls_ctx_verify_clients(MsTlsCtx *ctx, const char *ca_pem, size_t ca_len, int require) {
    if (!ctx->server) return -1;
    X509_STORE *store = SSL_CTX_get_cert_store(ctx->ssl);
    bool ok = true;
    if (ca_pem != NULL && ca_len > 0) {
        STACK_OF(X509) *cas = sk_X509_new_null();
        X509 *first = first_cert(ca_pem, ca_len, cas);
        ok = first != NULL && X509_STORE_add_cert(store, first) == 1;
        for (int i = 0; ok && i < sk_X509_num(cas); i++) ok = X509_STORE_add_cert(store, sk_X509_value(cas, i)) == 1;
        X509_free(first);
        sk_X509_pop_free(cas, X509_free);
    } else {
        ok = SSL_CTX_set_default_verify_paths(ctx->ssl) == 1;
    }
    if (!ok) {
        ERR_clear_error();
        return -1;
    }
    SSL_CTX_set_verify(ctx->ssl, SSL_VERIFY_PEER | (require ? SSL_VERIFY_FAIL_IF_NO_PEER_CERT : 0), NULL);
    return 0;
}

void ms_tls_ctx_free(MsTlsCtx *ctx) {
    if (!ctx) return;
    SSL_CTX_free(ctx->ssl);
    free(ctx);
}

/* The server's ALPN choice: the first of its own protocols that the client offered; none otherwise. */
static int select_alpn(SSL *ssl, const unsigned char **out, unsigned char *out_len, const unsigned char *offered,
                       unsigned int offered_len, void *arg) {
    (void)ssl;
    const MsTlsCtx *ctx = arg;
    unsigned char *chosen = NULL;
    /* OpenSSL's signatures take the lists as non-const pointers but only read them. */
    const int found = SSL_select_next_proto(&chosen, out_len, (const unsigned char *)ctx->alpn, (unsigned int)ctx->alpn_len,
                                            offered, offered_len);
    if (found != OPENSSL_NPN_NEGOTIATED) return SSL_TLSEXT_ERR_NOACK;
    *out = chosen;
    return SSL_TLSEXT_ERR_OK;
}

int ms_tls_ctx_set_alpn(MsTlsCtx *ctx, const char *names) {
    size_t used = 0;
    const char *name = names;
    while (*name != '\0') {
        const char *end = strchr(name, ',');
        const size_t length = end != NULL ? (size_t)(end - name) : strlen(name);
        if (length == 0 || length > 255 || used + 1 + length > sizeof ctx->alpn) return -1;
        ctx->alpn[used] = (uint8_t)length;
        memcpy(ctx->alpn + used + 1, name, length);
        used += 1 + length;
        name += length + (end != NULL ? 1 : 0);
    }
    ctx->alpn_len = used;
    if (ctx->server) {
        SSL_CTX_set_alpn_select_cb(ctx->ssl, select_alpn, ctx);
        return 0;
    }
    return SSL_CTX_set_alpn_protos(ctx->ssl, ctx->alpn, (unsigned int)used) == 0 ? 0 : -1; /* 0 means success here */
}

MsBytes ms_tls_alpn(const MsTls *t) {
    const unsigned char *name = NULL;
    unsigned int length = 0;
    SSL_get0_alpn_selected(t->ssl, &name, &length);
    return ms_bytes_of(name, length);
}

/* Sets the SNI name and the name the certificate must match. OpenSSL's SNI macro casts away const, so the name
 * is copied into a local buffer; a name longer than a DNS name can be is refused. */
static bool set_server_name(SSL *ssl, const char *host) {
    char name[256];
    const size_t length = strlen(host);
    if (length >= sizeof name) return false;
    memcpy(name, host, length + 1);
    /* Names are matched against the subject alternative names only, never the common name. */
    SSL_set_hostflags(ssl, X509_CHECK_FLAG_NEVER_CHECK_SUBJECT);
    ASN1_OCTET_STRING *address = a2i_IPADDRESS(name);
    const bool is_ip = address != NULL;
    ASN1_OCTET_STRING_free(address);
    if (is_ip) return X509_VERIFY_PARAM_set1_ip_asc(SSL_get0_param(ssl), name) == 1; /* no SNI for an address */
#if OPENSSL_VERSION_MAJOR >= 4
    /* SSL_set1_host is deprecated in OpenSSL 4.0 (Windows takes MSYS2's current package). */
    return SSL_set_tlsext_host_name(ssl, name) == 1 && SSL_set1_dnsname(ssl, name) == 1;
#else
    return SSL_set_tlsext_host_name(ssl, name) == 1 && SSL_set1_host(ssl, name) == 1;
#endif
}

MsTls *ms_tls_new(MsTlsCtx *ctx, const char *host) {
    MsTls *t = calloc(1, sizeof *t);
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
        if (host && *host && !set_server_name(t->ssl, host)) {
            SSL_free(t->ssl);
            free(t);
            return NULL;
        }
    }
    return t;
}

void ms_tls_free(MsTls *t) {
    if (!t) return;
    SSL_free(t->ssl);
    free(t);
}

long ms_tls_incoming(MsTls *t, const void *buf, size_t n) {
    if (n > 0x7fffffff) return -1;
    int w = BIO_write(t->in, buf, (int)n);
    return w < 0 ? -1 : w;
}

long ms_tls_outgoing(MsTls *t, void *buf, size_t cap) {
    if (cap > 0x7fffffff) cap = 0x7fffffff;
    if (BIO_ctrl_pending(t->out) == 0) return 0;
    int r = BIO_read(t->out, buf, (int)cap);
    return r < 0 ? 0 : r;
}

static void note(MsTls *t) {
    unsigned long e = ERR_get_error();
    if (e) ERR_error_string_n(e, t->err, sizeof t->err);
    ERR_clear_error();
}

static int classify(MsTls *t, int rc) {
    int e = SSL_get_error(t->ssl, rc);
    if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE) return MS_TLS_WANT_IO;
    if (e == SSL_ERROR_ZERO_RETURN) return MS_TLS_CLOSED;
    note(t);
    if (!t->err[0]) (void)snprintf(t->err, sizeof t->err, "%s", "TLS I/O error");
    return MS_TLS_ERROR;
}

int ms_tls_handshake(MsTls *t) {
    int rc = SSL_do_handshake(t->ssl);
    return rc == 1 ? MS_TLS_DONE : classify(t, rc);
}

long ms_tls_read(MsTls *t, void *buf, size_t n) {
    if (n > 0x7fffffff) n = 0x7fffffff;
    int rc = SSL_read(t->ssl, buf, (int)n);
    return rc > 0 ? rc : classify(t, rc);
}

long ms_tls_write(MsTls *t, const void *buf, size_t n) {
    if (n > 0x7fffffff) n = 0x7fffffff;
    int rc = SSL_write(t->ssl, buf, (int)n);
    return rc > 0 ? rc : classify(t, rc);
}

int ms_tls_shutdown(MsTls *t) { return SSL_shutdown(t->ssl) >= 0 ? 0 : -1; }
const char *ms_tls_error(MsTls *t) { return t->err; }

int ms_tls_version(const MsTls *t) { return SSL_version(t->ssl); }

uint32_t ms_tls_cipher(const MsTls *t) {
    const SSL_CIPHER *cipher = SSL_get_current_cipher(t->ssl);
    return cipher == NULL ? 0 : SSL_CIPHER_get_protocol_id(cipher);
}

/* The peer's certificates leaf first. A client sees the whole chain the server sent; a server sees the chain without
 * the leaf, which it keeps apart. */
static X509 *peer_at(const MsTls *t, size_t index, X509 **leaf) {
    STACK_OF(X509) *chain = SSL_get_peer_cert_chain(t->ssl);
    *leaf = SSL_get1_peer_certificate(t->ssl);
    const bool leaf_in_chain = chain != NULL && *leaf != NULL && sk_X509_num(chain) > 0 && X509_cmp(sk_X509_value(chain, 0), *leaf) == 0;
    if (leaf_in_chain || *leaf == NULL) {
        return chain != NULL && index < (size_t)sk_X509_num(chain) ? sk_X509_value(chain, (int)index) : NULL;
    }
    if (index == 0) {
        return *leaf;
    }
    return chain != NULL && index - 1 < (size_t)sk_X509_num(chain) ? sk_X509_value(chain, (int)(index - 1)) : NULL;
}

uint8_t ms_tls_verified(const MsTls *t) {
    X509 *leaf = SSL_get1_peer_certificate(t->ssl);
    const bool verified = leaf != NULL && SSL_get_verify_result(t->ssl) == X509_V_OK;
    X509_free(leaf);
    return verified ? 1 : 0;
}

size_t ms_tls_peer_count(const MsTls *t) {
    STACK_OF(X509) *chain = SSL_get_peer_cert_chain(t->ssl);
    X509 *leaf = SSL_get1_peer_certificate(t->ssl);
    size_t count = chain == NULL ? 0 : (size_t)sk_X509_num(chain);
    if (leaf != NULL) {
        const bool leaf_in_chain = count > 0 && X509_cmp(sk_X509_value(chain, 0), leaf) == 0;
        count += leaf_in_chain ? 0 : 1;
        X509_free(leaf);
    }
    return count;
}

uint8_t *ms_tls_peer_der(const MsTls *t, size_t index, size_t *length) {
    X509 *leaf = NULL;
    X509 *certificate = peer_at(t, index, &leaf);
    uint8_t *der = NULL;
    if (certificate != NULL) {
        const int needed = i2d_X509(certificate, NULL);
        der = needed > 0 ? malloc((size_t)needed) : NULL;
        uint8_t *cursor = der;
        if (der != NULL && i2d_X509(certificate, &cursor) == needed) {
            *length = (size_t)needed;
        } else {
            free(der);
            der = NULL;
        }
    }
    X509_free(leaf);
    return der;
}
