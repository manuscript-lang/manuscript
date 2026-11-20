/* TLS on OpenSSL over memory buffers. This layer never touches a socket: the caller moves ciphertext between the
   network and `ms_tls_incoming` / `ms_tls_outgoing`, so the reactor (runtime/io) owns all I/O and an idle
   connection holds only the SSL object, with its buffers released between records. */
#ifndef MS_NET_TLS_H
#define MS_NET_TLS_H
#include <stddef.h>
#include <stdint.h>
#include "ms_rt/safe.h"

typedef struct MsTlsCtx MsTlsCtx;
typedef struct MsTls MsTls;

/* A context holds the certificates and policy shared by connections: TLS 1.2 and up, no session tickets or caches.
   A server context needs `cert_pem` (chain) and `key_pem`. A client context verifies the peer against `ca_pem`
   when given, else against the system store, and presents `cert_pem` and `key_pem` when both are given. Returns NULL on failure. */
MsTlsCtx *ms_tls_ctx_new(int server, const char *cert_pem, size_t cert_len, const char *key_pem, size_t key_len,
                           const char *ca_pem, size_t ca_len);
void ms_tls_ctx_free(MsTlsCtx *ctx);

/* Makes a server context ask clients for a certificate and verify it against `ca_pem` (the system store when NULL).
   With `require` a client without one fails the handshake; otherwise it may go without. Returns 0, or -1. */
int ms_tls_ctx_verify_clients(MsTlsCtx *ctx, const char *ca_pem, size_t ca_len, int require);

enum { MS_TLS_ALPN_MAX = 64 };
/* The application protocols a client offers or a server accepts, most preferred first, as names separated by commas
   ("h2,http/1.1"). Returns 0, or -1 for an empty name or a list over MS_TLS_ALPN_MAX bytes on the wire. */
int ms_tls_ctx_set_alpn(MsTlsCtx *ctx, const char *names);

/* One connection. A client passes the host name to verify and to send as the server name; a server passes NULL. */
MsTls *ms_tls_new(MsTlsCtx *ctx, const char *host);
void ms_tls_free(MsTls *t);

/* Ciphertext from the network. Returns the bytes accepted (all of them, the buffer grows), or -1. */
long ms_tls_incoming(MsTls *t, const void *buf, size_t n);
/* Ciphertext to send. Returns the bytes copied into buf, 0 when nothing is pending. */
long ms_tls_outgoing(MsTls *t, void *buf, size_t cap);

enum { MS_TLS_DONE = 1, MS_TLS_WANT_IO = 0, MS_TLS_ERROR = -1, MS_TLS_CLOSED = -2 };
/* Advances the handshake. WANT_IO: send outgoing bytes, then feed more incoming bytes and call again. */
int ms_tls_handshake(MsTls *t);
/* Plaintext in or out. Return bytes (> 0), WANT_IO (0), ERROR or CLOSED (the peer sent close_notify). */
long ms_tls_read(MsTls *t, void *buf, size_t n);
long ms_tls_write(MsTls *t, const void *buf, size_t n);
/* Whether input is already inside the session (plaintext decoded, or ciphertext fed and not yet read): a read
   would return without the socket being readable. */
int ms_tls_pending(const MsTls *t);
/* The protocol the handshake chose, empty when none; valid until the connection is freed. */
MsBytes ms_tls_alpn(const MsTls *t);
/* What the handshake agreed: the protocol version (0x0303 for TLS 1.2, 0x0304 for 1.3) and the cipher suite's IANA
   number, 0 before the handshake ends. */
int ms_tls_version(const MsTls *t);
uint32_t ms_tls_cipher(const MsTls *t);
/* The peer's certificate chain, leaf first: how many, then the DER bytes of one (malloc'ed, the caller frees them),
   or NULL for an index past the end. */
size_t ms_tls_peer_count(const MsTls *t);
uint8_t *ms_tls_peer_der(const MsTls *t, size_t index, size_t *length);
/* 1 when the peer presented a certificate chain that verified. */
uint8_t ms_tls_verified(const MsTls *t);
/* Queues close_notify. */
int ms_tls_shutdown(MsTls *t);
/* The last error as text, empty when none. Valid until the next call on `t`. */
const char *ms_tls_error(MsTls *t);

#endif
