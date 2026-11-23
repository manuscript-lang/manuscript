/* runtime/std/net_calls.h: the waiting network natives without their entry's cancel exit. The `msstd_net_*` natives
 * the compiled code calls end a cancelled call (ms_native_return); C that serves, dials or resolves calls these, which
 * return a failed status for a cancel so the caller frees what it holds on its ordinary error path. */
#ifndef MS_RUNTIME_STD_NET_CALLS_H
#define MS_RUNTIME_STD_NET_CALLS_H

#include "runtime/std/net_conn.h"
#include "runtime/std/net_dgram.h"
#include "runtime/std/net_network.h"
#include "runtime/std/net_tls_conn.h"

uint8_t ms_net_connection_read(const MsObj *handle, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsBytes *out, MsString *err);
uint8_t ms_net_connection_write_bytes(const MsObj *handle, const MsBytes *data, uint8_t has_timeout, int64_t timeout, MsString *err);
uint8_t ms_net_connection_shutdown_write(const MsObj *handle, MsString *err);
uint8_t ms_net_listener_accept(const MsObj *handle, uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);
uint8_t ms_net_listener_accept_raw(const MsObj *handle, uint8_t has_timeout, int64_t timeout, int64_t *out, MsString *err);
uint8_t ms_net_datagram_receive(const MsObj *handle, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsDatagramWire *out, MsString *err);
uint8_t ms_net_datagram_send_bytes(const MsObj *handle, const MsBytes *data, const MsString *address, uint8_t has_timeout, int64_t timeout, MsString *err);
uint8_t ms_net_network_connect(const MsObj *net, const MsString *address, uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);
uint8_t ms_net_network_connect_unix(const MsObj *net, const MsString *path, uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);
uint8_t ms_net_network_listen(const MsObj *net, const MsString *address, MsObj **out, MsString *err);
uint8_t ms_net_network_listen_unix(const MsObj *net, const MsString *path, MsObj **out, MsString *err);
uint8_t ms_net_network_bind_datagram(const MsObj *net, const MsString *address, MsObj **out, MsString *err);
uint8_t ms_net_network_lookup(const MsObj *net, const MsString *name, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsList *out, MsString *err);
uint8_t ms_net_network_resolve(const MsObj *net, const MsString *name, int64_t kind, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsList *out, MsString *err);
uint8_t ms_net_connection_start_tls(const MsObj *handle, const MsTlsOptions *options, uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);
uint8_t ms_net_connection_accept_tls(const MsObj *handle, const MsTlsOptions *options, uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);
uint8_t ms_net_network_connect_tls_config(const MsObj *net, const MsString *address, const MsTlsOptions *options, uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);
uint8_t ms_net_network_listen_tls(const MsObj *net, const MsString *address, const MsTlsOptions *options, uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);

#endif
