/* runtime/std/net_tls.h: TLS on OpenSSL over memory buffers. This layer never touches a socket: the connection code
 * (net_tls_conn.c) moves ciphertext between the network and ms_net_tls_incoming / ms_net_tls_outgoing, so an idle
 * connection holds only its SSL object. The certificate parse and verify natives are tls.h's. */
#ifndef MS_RUNTIME_STD_NET_TLS_H
#define MS_RUNTIME_STD_NET_TLS_H

#include "base/bytes.h"
#include "base/safe.h"
#include "base/string.h"

typedef struct MsNetTlsCtx MsNetTlsCtx;
typedef struct MsNetTls MsNetTls;

/* A counted context holds the certificates and policy shared by connections: TLS 1.2 and up, no session tickets or
 * caches. A server context needs `certificate` (a chain) and `key`. A client context verifies the peer against `roots`
 * when it is not empty, else against the system roots, and presents `certificate` and `key` when given. NULL on
 * failure. */
MsNetTlsCtx *ms_net_tls_ctx_new(bool server, MsSpan certificate, MsSpan key, MsSpan roots);
MsNetTlsCtx *ms_net_tls_ctx_retain(MsNetTlsCtx *ctx);
void ms_net_tls_ctx_release(MsNetTlsCtx *ctx);

/* Makes a server context ask clients for a certificate and verify it against `roots` (the system roots when empty).
 * With `require` a client without one fails the handshake. False on failure. */
MS_NODISCARD bool ms_net_tls_ctx_verify_clients(MsNetTlsCtx *ctx, MsSpan roots, bool require);

/* The application protocols a client offers or a server accepts, most preferred first. False for an empty name, one over
 * 255 bytes or a list over 64 bytes on the wire. */
MS_NODISCARD bool ms_net_tls_ctx_set_alpn(MsNetTlsCtx *ctx, const MsString *names, size_t count);

/* One connection. A client passes the host name to verify and send as the server name; a server passes an empty span. */
MsNetTls *ms_net_tls_new(MsNetTlsCtx *ctx, MsSpan host);
void ms_net_tls_free(MsNetTls *tls);

/* Ciphertext from the network; all of it is taken. Ciphertext to send: the bytes copied into `buffer`, 0 when none. */
void ms_net_tls_incoming(MsNetTls *tls, MsSpan data);
size_t ms_net_tls_outgoing(MsNetTls *tls, uint8_t *buffer, size_t capacity);

typedef enum MsNetTlsStep { MS_NET_TLS_DONE = 1, MS_NET_TLS_WANT_IO = 0, MS_NET_TLS_ERROR = -1, MS_NET_TLS_CLOSED = -2 } MsNetTlsStep;
/* Advances the handshake. WANT_IO: send the outgoing bytes, feed more incoming ones and call again. */
MsNetTlsStep ms_net_tls_handshake(MsNetTls *tls);
/* Plaintext out or in: bytes (> 0) in `*count`, or WANT_IO, ERROR, CLOSED (the peer sent close_notify). */
MsNetTlsStep ms_net_tls_read(MsNetTls *tls, uint8_t *buffer, size_t capacity, size_t *count);
MsNetTlsStep ms_net_tls_write(MsNetTls *tls, const uint8_t *data, size_t length, size_t *count);
/* Queues close_notify. */
void ms_net_tls_shutdown(MsNetTls *tls);
/* The last error as text, empty for none. */
const char *ms_net_tls_error(const MsNetTls *tls);

/* What the handshake chose and saw. */
MsSpan ms_net_tls_alpn(const MsNetTls *tls);
int ms_net_tls_version(const MsNetTls *tls); /* 0x0303 for TLS 1.2, 0x0304 for 1.3; 0 before the handshake ends */
uint32_t ms_net_tls_cipher(const MsNetTls *tls);
bool ms_net_tls_verified(const MsNetTls *tls);
/* The peer's chain, leaf first: how many, and the DER of one as bytes (empty past the end). */
size_t ms_net_tls_peer_count(const MsNetTls *tls);
MsBytes ms_net_tls_peer_der(const MsNetTls *tls, size_t index);

#endif
