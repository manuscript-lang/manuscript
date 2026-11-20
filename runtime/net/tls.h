/* TLS on OpenSSL over memory buffers. This layer never touches a socket: the caller moves ciphertext between the
   network and `ms_tls_incoming` / `ms_tls_outgoing`, so the reactor (runtime/io) owns all I/O and an idle
   connection holds only the SSL object, with its buffers released between records. */
#ifndef MS_NET_TLS_H
#define MS_NET_TLS_H
#include <stddef.h>

typedef struct ms_tls_ctx ms_tls_ctx;
typedef struct ms_tls ms_tls;

/* A context holds the certificates and policy shared by connections: TLS 1.2 and up, no session tickets or caches.
   A server context needs `cert_pem` (chain) and `key_pem`. A client context verifies the peer against `ca_pem`
   when given, else against the system store. Returns NULL on failure. */
ms_tls_ctx *ms_tls_ctx_new(int server, const char *cert_pem, size_t cert_len, const char *key_pem, size_t key_len,
                           const char *ca_pem, size_t ca_len);
void ms_tls_ctx_free(ms_tls_ctx *ctx);

/* One connection. A client passes the host name to verify and to send as the server name; a server passes NULL. */
ms_tls *ms_tls_new(ms_tls_ctx *ctx, const char *host);
void ms_tls_free(ms_tls *t);

/* Ciphertext from the network. Returns the bytes accepted (all of them, the buffer grows), or -1. */
long ms_tls_incoming(ms_tls *t, const void *buf, size_t n);
/* Ciphertext to send. Returns the bytes copied into buf, 0 when nothing is pending. */
long ms_tls_outgoing(ms_tls *t, void *buf, size_t cap);

enum { MS_TLS_DONE = 1, MS_TLS_WANT_IO = 0, MS_TLS_ERROR = -1, MS_TLS_CLOSED = -2 };
/* Advances the handshake. WANT_IO: send outgoing bytes, then feed more incoming bytes and call again. */
int ms_tls_handshake(ms_tls *t);
/* Plaintext in or out. Return bytes (> 0), WANT_IO (0), ERROR or CLOSED (the peer sent close_notify). */
long ms_tls_read(ms_tls *t, void *buf, size_t n);
long ms_tls_write(ms_tls *t, const void *buf, size_t n);
/* Queues close_notify. */
int ms_tls_shutdown(ms_tls *t);
/* The last error as text, empty when none. Valid until the next call on `t`. */
const char *ms_tls_error(ms_tls *t);

#endif
