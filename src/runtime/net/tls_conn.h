/* TLS on connection rows: the context a TlsOptions record describes, and the natives that upgrade a plain row in
 * place (start_tls, accept_tls) and report the negotiated protocol. */
#ifndef MS_NET_TLS_CONN_H
#define MS_NET_TLS_CONN_H

#include <stdint.h>

#include "ms_rt/net.h"
#include "tls.h"

/* Builds the context for `options` (a client or a server one) into `*out`: STATUS_OK, or STATUS_INVALID_INPUT for a
 * server without a certificate and key, a client that requires client certificates, unusable PEM, or a bad ALPN
 * list. */
uint8_t ms_net_tls_context(int server, const MsNetTlsOptions *options, MsTlsCtx **out);

#endif
