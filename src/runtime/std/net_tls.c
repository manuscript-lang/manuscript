/* TLS contexts and sessions over OpenSSL memory buffers (see net_tls.h). */
#include "runtime/std/net_tls.h"

#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509_vfy.h>
#include <openssl/x509v3.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

#include "base/alloc.h"

enum { ALPN_BYTES = 64, NAME_BYTES = 256, ERROR_BYTES = 160, MAX_IO = 0x7fffffff };

struct MsNetTlsCtx {
  SSL_CTX *ssl;
  atomic_uint references;
  bool server;
  uint8_t alpn[ALPN_BYTES]; /* the protocols in wire format: a length byte before each name */
  size_t alpn_length;
};

struct MsNetTls {
  SSL *ssl;
  BIO *in;
  BIO *out;
  char error[ERROR_BYTES];
};

/* Reads every PEM certificate of `pem`: the first is returned and the rest go to `rest` (freed when NULL). */
static X509 *first_certificate(MsSpan pem, STACK_OF(X509) *rest) {
  BIO *bio = BIO_new_mem_buf(pem.ptr, (int)pem.len);
  X509 *first = NULL;
  X509 *next = NULL;
  if (bio == NULL) {
    return NULL;
  }
  while ((next = PEM_read_bio_X509(bio, NULL, NULL, NULL)) != NULL) {
    if (first == NULL) {
      first = next;
    } else if (rest != NULL) {
      (void)sk_X509_push(rest, next);
    } else {
      X509_free(next);
    }
  }
  BIO_free(bio);
  ERR_clear_error();
  return first;
}

/* Adds every certificate of `pem` to the store of `ssl` as a trust anchor. */
static bool add_roots(SSL_CTX *ssl, MsSpan pem) {
  X509_STORE *store = SSL_CTX_get_cert_store(ssl);
  STACK_OF(X509) *others = sk_X509_new_null();
  X509 *first = first_certificate(pem, others);
  bool ok = first != NULL && X509_STORE_add_cert(store, first) == 1;
  for (int i = 0; ok && i < sk_X509_num(others); i++) {
    ok = X509_STORE_add_cert(store, sk_X509_value(others, i)) == 1;
  }
  X509_free(first);
  sk_X509_pop_free(others, X509_free);
  return ok;
}

/* The system roots. Windows keeps them in its own store, which OpenSSL reads through its winstore provider. */
static bool add_system_roots(SSL_CTX *ssl) {
#ifdef _WIN32
  return SSL_CTX_load_verify_store(ssl, "org.openssl.winstore://") == 1;
#else
  return SSL_CTX_set_default_verify_paths(ssl) == 1;
#endif
}

/* The chain and private key this side presents; false when either is missing or they do not match. */
static bool use_identity(SSL_CTX *ssl, MsSpan certificate, MsSpan key) {
  STACK_OF(X509) *chain = sk_X509_new_null();
  X509 *leaf = certificate.len > 0 ? first_certificate(certificate, chain) : NULL;
  BIO *key_bio = key.len > 0 ? BIO_new_mem_buf(key.ptr, (int)key.len) : NULL;
  EVP_PKEY *private_key = key_bio != NULL ? PEM_read_bio_PrivateKey(key_bio, NULL, NULL, NULL) : NULL;
  bool ok = leaf != NULL && private_key != NULL && SSL_CTX_use_certificate(ssl, leaf) == 1 &&
            SSL_CTX_use_PrivateKey(ssl, private_key) == 1 && SSL_CTX_check_private_key(ssl) == 1;
  for (int i = 0; ok && i < sk_X509_num(chain); i++) {
    ok = SSL_CTX_add_extra_chain_cert(ssl, X509_dup(sk_X509_value(chain, i))) == 1;
  }
  sk_X509_pop_free(chain, X509_free);
  X509_free(leaf);
  EVP_PKEY_free(private_key);
  BIO_free(key_bio);
  return ok;
}

MsNetTlsCtx *ms_net_tls_ctx_new(bool server, MsSpan certificate, MsSpan key, MsSpan roots) {
  MsNetTlsCtx *ctx = ms_alloc_zeroed(sizeof *ctx);
  atomic_init(&ctx->references, 1);
  ctx->server = server;
  ctx->ssl = SSL_CTX_new(server ? TLS_server_method() : TLS_client_method());
  bool ok = ctx->ssl != NULL;
  if (ok) {
    SSL_CTX_set_min_proto_version(ctx->ssl, TLS1_2_VERSION);
    SSL_CTX_set_mode(ctx->ssl, SSL_MODE_RELEASE_BUFFERS | SSL_MODE_ENABLE_PARTIAL_WRITE |
                                   SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);
    SSL_CTX_set_session_cache_mode(ctx->ssl, SSL_SESS_CACHE_OFF);
    SSL_CTX_set_options(ctx->ssl, SSL_OP_NO_TICKET | SSL_OP_NO_COMPRESSION | SSL_OP_NO_RENEGOTIATION);
  }
  if (ok && server) {
    ok = use_identity(ctx->ssl, certificate, key);
  } else if (ok) {
    SSL_CTX_set_verify(ctx->ssl, SSL_VERIFY_PEER, NULL);
    ok = certificate.len == 0 || use_identity(ctx->ssl, certificate, key);
    ok = ok && (roots.len > 0 ? add_roots(ctx->ssl, roots) : add_system_roots(ctx->ssl));
  }
  if (!ok) {
    ERR_clear_error();
    ms_net_tls_ctx_release(ctx);
    return NULL;
  }
  return ctx;
}

MsNetTlsCtx *ms_net_tls_ctx_retain(MsNetTlsCtx *ctx) {
  atomic_fetch_add(&ctx->references, 1);
  return ctx;
}

void ms_net_tls_ctx_release(MsNetTlsCtx *ctx) {
  if (ctx != NULL && atomic_fetch_sub(&ctx->references, 1) == 1) {
    SSL_CTX_free(ctx->ssl);
    ms_free(ctx);
  }
}

bool ms_net_tls_ctx_verify_clients(MsNetTlsCtx *ctx, MsSpan roots, bool require) {
  if (!ctx->server) {
    return false;
  }
  if (!(roots.len > 0 ? add_roots(ctx->ssl, roots) : add_system_roots(ctx->ssl))) {
    ERR_clear_error();
    return false;
  }
  SSL_CTX_set_verify(ctx->ssl, SSL_VERIFY_PEER | (require ? SSL_VERIFY_FAIL_IF_NO_PEER_CERT : 0), NULL);
  return true;
}

/* The server's choice: the first of its own protocols that the client offered; none otherwise. */
static int select_alpn(SSL *ssl, const unsigned char **out, unsigned char *out_length, const unsigned char *offered,
                       unsigned int offered_length, void *argument) {
  const MsNetTlsCtx *ctx = argument;
  unsigned char *chosen = NULL;
  (void)ssl;
  if (SSL_select_next_proto(&chosen, out_length, ctx->alpn, (unsigned int)ctx->alpn_length, offered,
                            offered_length) != OPENSSL_NPN_NEGOTIATED) {
    return SSL_TLSEXT_ERR_NOACK;
  }
  *out = chosen;
  return SSL_TLSEXT_ERR_OK;
}

bool ms_net_tls_ctx_set_alpn(MsNetTlsCtx *ctx, const MsString *names, size_t count) {
  size_t used = 0;
  for (size_t i = 0; i < count; i++) {
    const MsSpan name = ms_string_span(&names[i]);
    if (name.len == 0 || name.len > UINT8_MAX || used + 1 + name.len > sizeof ctx->alpn) {
      return false;
    }
    ctx->alpn[used] = (uint8_t)name.len;
    memcpy(ctx->alpn + used + 1, name.ptr, name.len);
    used += 1 + name.len;
  }
  ctx->alpn_length = used;
  if (ctx->server) {
    SSL_CTX_set_alpn_select_cb(ctx->ssl, select_alpn, ctx);
    return true;
  }
  return SSL_CTX_set_alpn_protos(ctx->ssl, ctx->alpn, (unsigned int)used) == 0; /* 0 is success here */
}

/* Sets the SNI name and the name the certificate must match, against subject alternative names only. An IP address is
 * matched as one and sent no SNI. */
static bool set_server_name(SSL *ssl, MsSpan host) {
  char name[NAME_BYTES];
  if (host.len == 0 || host.len >= sizeof name) {
    return false;
  }
  memcpy(name, host.ptr, host.len);
  name[host.len] = 0;
  SSL_set_hostflags(ssl, X509_CHECK_FLAG_NEVER_CHECK_SUBJECT);
  ASN1_OCTET_STRING *address = a2i_IPADDRESS(name);
  const bool is_ip = address != NULL;
  ASN1_OCTET_STRING_free(address);
  if (is_ip) {
    return X509_VERIFY_PARAM_set1_ip_asc(SSL_get0_param(ssl), name) == 1;
  }
  return SSL_set_tlsext_host_name(ssl, name) == 1 && SSL_set1_host(ssl, name) == 1;
}

MsNetTls *ms_net_tls_new(MsNetTlsCtx *ctx, MsSpan host) {
  MsNetTls *tls = ms_alloc_zeroed(sizeof *tls);
  tls->ssl = SSL_new(ctx->ssl);
  tls->in = BIO_new(BIO_s_mem());
  tls->out = BIO_new(BIO_s_mem());
  if (tls->ssl == NULL || tls->in == NULL || tls->out == NULL) {
    BIO_free(tls->in);
    BIO_free(tls->out);
    SSL_free(tls->ssl);
    ms_free(tls);
    return NULL;
  }
  BIO_set_mem_eof_return(tls->in, -1); /* an empty input means "retry", not end of file */
  SSL_set_bio(tls->ssl, tls->in, tls->out); /* the SSL owns both BIOs from here */
  if (ctx->server) {
    SSL_set_accept_state(tls->ssl);
    return tls;
  }
  SSL_set_connect_state(tls->ssl);
  if (!set_server_name(tls->ssl, host)) {
    ms_net_tls_free(tls);
    return NULL;
  }
  return tls;
}

void ms_net_tls_free(MsNetTls *tls) {
  if (tls != NULL) {
    SSL_free(tls->ssl);
    ms_free(tls);
  }
}

void ms_net_tls_incoming(MsNetTls *tls, MsSpan data) {
  size_t offset = 0;
  while (offset < data.len) {
    const size_t chunk = data.len - offset > MAX_IO ? MAX_IO : data.len - offset;
    const int taken = BIO_write(tls->in, data.ptr + offset, (int)chunk);
    if (taken <= 0) {
      return;
    }
    offset += (size_t)taken;
  }
}

size_t ms_net_tls_outgoing(MsNetTls *tls, uint8_t *buffer, size_t capacity) {
  if (BIO_ctrl_pending(tls->out) == 0) {
    return 0;
  }
  const int taken = BIO_read(tls->out, buffer, (int)(capacity > MAX_IO ? MAX_IO : capacity));
  return taken < 0 ? 0 : (size_t)taken;
}

static void note_error(MsNetTls *tls) {
  const unsigned long code = ERR_get_error();
  if (code != 0) {
    ERR_error_string_n(code, tls->error, sizeof tls->error);
  }
  ERR_clear_error();
}

static MsNetTlsStep classify(MsNetTls *tls, int result) {
  const int error = SSL_get_error(tls->ssl, result);
  if (error == SSL_ERROR_WANT_READ || error == SSL_ERROR_WANT_WRITE) {
    return MS_NET_TLS_WANT_IO;
  }
  if (error == SSL_ERROR_ZERO_RETURN) {
    return MS_NET_TLS_CLOSED;
  }
  note_error(tls);
  if (tls->error[0] == 0) {
    (void)snprintf(tls->error, sizeof tls->error, "%s", "TLS I/O error");
  }
  return MS_NET_TLS_ERROR;
}

MsNetTlsStep ms_net_tls_handshake(MsNetTls *tls) {
  const int result = SSL_do_handshake(tls->ssl);
  return result == 1 ? MS_NET_TLS_DONE : classify(tls, result);
}

MsNetTlsStep ms_net_tls_read(MsNetTls *tls, uint8_t *buffer, size_t capacity, size_t *count) {
  const int result = SSL_read(tls->ssl, buffer, (int)(capacity > MAX_IO ? MAX_IO : capacity));
  if (result > 0) {
    *count = (size_t)result;
    return MS_NET_TLS_DONE;
  }
  return classify(tls, result);
}

MsNetTlsStep ms_net_tls_write(MsNetTls *tls, const uint8_t *data, size_t length, size_t *count) {
  const int result = SSL_write(tls->ssl, data, (int)(length > MAX_IO ? MAX_IO : length));
  if (result > 0) {
    *count = (size_t)result;
    return MS_NET_TLS_DONE;
  }
  return classify(tls, result);
}

void ms_net_tls_shutdown(MsNetTls *tls) { (void)SSL_shutdown(tls->ssl); }

const char *ms_net_tls_error(const MsNetTls *tls) { return tls->error; }

MsSpan ms_net_tls_alpn(const MsNetTls *tls) {
  const unsigned char *name = NULL;
  unsigned int length = 0;
  SSL_get0_alpn_selected(tls->ssl, &name, &length);
  return ms_span_of(name, length);
}

int ms_net_tls_version(const MsNetTls *tls) { return SSL_version(tls->ssl); }

uint32_t ms_net_tls_cipher(const MsNetTls *tls) {
  const SSL_CIPHER *cipher = SSL_get_current_cipher(tls->ssl);
  return cipher == NULL ? 0 : SSL_CIPHER_get_protocol_id(cipher);
}

bool ms_net_tls_verified(const MsNetTls *tls) {
  X509 *leaf = SSL_get1_peer_certificate(tls->ssl);
  const bool verified = leaf != NULL && SSL_get_verify_result(tls->ssl) == X509_V_OK;
  X509_free(leaf);
  return verified;
}

/* A client sees the whole chain the server sent; a server sees the chain without the client's leaf, kept apart. */
static X509 *peer_at(const MsNetTls *tls, size_t index, X509 **leaf) {
  STACK_OF(X509) *chain = SSL_get_peer_cert_chain(tls->ssl);
  const int chain_length = chain == NULL ? 0 : sk_X509_num(chain);
  *leaf = SSL_get1_peer_certificate(tls->ssl);
  const bool in_chain = *leaf != NULL && chain_length > 0 && X509_cmp(sk_X509_value(chain, 0), *leaf) == 0;
  if (in_chain || *leaf == NULL) {
    return index < (size_t)chain_length ? sk_X509_value(chain, (int)index) : NULL;
  }
  if (index == 0) {
    return *leaf;
  }
  return index - 1 < (size_t)chain_length ? sk_X509_value(chain, (int)(index - 1)) : NULL;
}

size_t ms_net_tls_peer_count(const MsNetTls *tls) {
  STACK_OF(X509) *chain = SSL_get_peer_cert_chain(tls->ssl);
  X509 *leaf = SSL_get1_peer_certificate(tls->ssl);
  size_t count = chain == NULL ? 0 : (size_t)sk_X509_num(chain);
  if (leaf != NULL) {
    const bool in_chain = count > 0 && X509_cmp(sk_X509_value(chain, 0), leaf) == 0;
    count += in_chain ? 0 : 1;
    X509_free(leaf);
  }
  return count;
}

MsBytes ms_net_tls_peer_der(const MsNetTls *tls, size_t index) {
  X509 *leaf = NULL;
  X509 *certificate = peer_at(tls, index, &leaf);
  MsBytes der = {0};
  const int needed = certificate != NULL ? i2d_X509(certificate, NULL) : 0;
  if (needed > 0) {
    uint8_t *buffer = ms_alloc((size_t)needed);
    uint8_t *cursor = buffer;
    if (i2d_X509(certificate, &cursor) == needed) {
      der = ms_bytes_from_span(ms_span_of(buffer, (size_t)needed));
    }
    ms_free(buffer);
  }
  X509_free(leaf);
  return der;
}
