/* Reaching a server: resolving a name and opening a connection row. Both calls park the running task (name
 * resolution on the reactor's completion, connect and the TLS handshake on the descriptor), so a stop request ends
 * them and other tasks run meanwhile. They are separate so that a caller can look at the resolved addresses (to
 * refuse a private one, say) before it connects to any. After a connection opens, bytes move through conn_io.h.
 *
 * `deadline_ns` is an absolute ms_sys_monotonic_ns time, or negative for none.
 */
#ifndef MS_NET_DIAL_H
#define MS_NET_DIAL_H

#include <stddef.h>
#include <stdint.h>

#include "conn_io.h"
#include "ms_rt/sys_net.h"
#include "tls.h"

enum { MS_NET_MAX_ADDRESSES = 16 };

typedef struct MsNetAddresses {
    MsAddr items[MS_NET_MAX_ADDRESSES]; /* in the resolver's order; more than MS_NET_MAX_ADDRESSES are dropped */
    size_t count;
    int resolver_code; /* the resolver's own status when the lookup failed (negative), else 0 */
} MsNetAddresses;

/* Resolves `host` for stream sockets on `port`. MS_NET_OK with `count` addresses (a name that resolves to none is
 * MS_NET_FAILED); MS_NET_TIMEOUT or MS_NET_CANCELLED when the wait ended first. */
MS_NODISCARD MsNetStatus ms_net_resolve(const char *host, uint16_t port, int64_t deadline_ns, MsNetAddresses *out);

/* Connects to `address` and opens a row for it in `table` with protocol `proto` (not MS_CONN_NONE, which marks a free
 * row; a caller that learns the protocol from the handshake, ALPN h2 say, sets row->proto afterwards). With `tls`
 * the handshake runs to the end, verifying `server_name` and sending it as the server name. On any failure nothing
 * is left open. MS_NET_RESET and MS_NET_FAILED leave the system code in *error_code when it is not NULL. */
MS_NODISCARD MsNetStatus ms_net_connect(MsConnTable *table, const MsAddr *address, uint8_t proto, MsTlsCtx *tls,
                                        const char *server_name, int64_t deadline_ns, MsConnId *out, int *error_code);

#endif
