/* runtime/std/net_network.h: the Network handle of @std/net: the permissions and the sockets opened through it, and
 * the natives that open them. TLS, HTTP and WebSocket natives are separate (tls, http, ws). */
#ifndef MS_RUNTIME_STD_NET_NETWORK_H
#define MS_RUNTIME_STD_NET_NETWORK_H

#include "abi/status.h"
#include "base/desc.h"
#include "base/list.h"
#include "base/string.h"

/* ms-sig: msstd_net_network() -> *mut ObjCell<NetH> @domain=network @end */
MsObj *msstd_net_network(void);
/* ms-sig: msstd_net_network_close(handle net: *const ObjCell<NetH>) @domain=network */
void msstd_net_network_close(const MsObj *net);
/* ms-sig: msstd_net_network_connect(handle net: *const ObjCell<NetH>, address: *const StrVal, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_connect(const MsObj *net, const MsString *address, uint8_t has_timeout, int64_t timeout,
                                  MsObj **out, MsString *err);
/* ms-sig: msstd_net_network_connect_unix(handle net: *const ObjCell<NetH>, path: *const StrVal, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_connect_unix(const MsObj *net, const MsString *path, uint8_t has_timeout, int64_t timeout,
                                       MsObj **out, MsString *err);
/* ms-sig: msstd_net_network_listen(handle net: *const ObjCell<NetH>, address: *const StrVal, out: *mut *mut ObjCell<ListenerH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_listen(const MsObj *net, const MsString *address, MsObj **out, MsString *err);
/* ms-sig: msstd_net_network_listen_unix(handle net: *const ObjCell<NetH>, path: *const StrVal, out: *mut *mut ObjCell<ListenerH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_listen_unix(const MsObj *net, const MsString *path, MsObj **out, MsString *err);
/* ms-sig: msstd_net_network_bind_datagram(handle net: *const ObjCell<NetH>, address: *const StrVal, out: *mut *mut ObjCell<DgramH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_bind_datagram(const MsObj *net, const MsString *address, MsObj **out, MsString *err);
/* ms-sig: msstd_net_network_lookup(handle net: *const ObjCell<NetH>, name: *const StrVal, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_lookup(const MsObj *net, const MsString *name, uint8_t has_max, int64_t max,
                                 uint8_t has_timeout, int64_t timeout, MsList *out, MsString *err);
/* Returns DnsRecord values (net_dns.h). Addresses come from the system resolver unless the network has one of its own;
 * the other kinds ask the DNS servers of resolv.conf, or the network's, and are unsupported where the host lists none. */
/* ms-sig: msstd_net_network_resolve(handle net: *const ObjCell<NetH>, name: *const StrVal, kind: i64, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_resolve(const MsObj *net, const MsString *name, int64_t kind, uint8_t has_max, int64_t max,
                                  uint8_t has_timeout, int64_t timeout, MsList *out, MsString *err);
/* ms-sig: msstd_net_network_restrict(handle net: *const ObjCell<NetH>, hosts: *const VecVal, cidrs: *const VecVal, allow_listen: u8, out: *mut *mut ObjCell<NetH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_restrict(const MsObj *net, const MsList *hosts, const MsList *cidrs, uint8_t allow_listen,
                                   MsObj **out, MsString *err);
/* ms-sig: msstd_net_network_with_resolver(handle net: *const ObjCell<NetH>, address: *const StrVal, out: *mut *mut ObjCell<NetH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_with_resolver(const MsObj *net, const MsString *address, MsObj **out, MsString *err);

#include "runtime/std/net_filter.h"

/* The network's filter (a new reference; NULL when unrestricted). */
MsNetFilter *ms_net_network_filter(const MsObj *net);
/* Records `client`, an HTTP client handle the network now owns and closes with it; false (the caller closes it)
 * when the network is closed. */
bool ms_net_network_adopt_client(const MsObj *net, MsObj *client);

#endif
