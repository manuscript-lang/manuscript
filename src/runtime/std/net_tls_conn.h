/* runtime/std/net_tls_conn.h: the TLS natives of @std/net (net_tls_conn.c). The certificate parse and verify natives
 * are in tls.h. */
#ifndef MS_RUNTIME_STD_NET_TLS_CONN_H
#define MS_RUNTIME_STD_NET_TLS_CONN_H

#include "base/bytes.h"
#include "base/list.h"
#include "runtime/std/net_core.h"
#include "runtime/std/net_tls.h"

/* TlsOptions flattened: the PEM texts are empty for none; `alpn` is a list of strings, most preferred first. */
typedef struct MsTlsOptions {
  MsString server_name;
  MsString roots_pem;
  MsString certificate_pem;
  MsString private_key_pem;
  MsList alpn;
  uint8_t require_client_certificate;
} MsTlsOptions;

/* TlsInfo flattened: version (0x0303, 0x0304), the IANA cipher suite number, the negotiated protocol, the peer chain
 * as Bytes (leaf first), and whether the peer verified. */
typedef struct MsTlsInfo {
  int64_t version;
  int64_t cipher_suite;
  MsString alpn;
  MsList peer_certificates;
  uint8_t verified;
} MsTlsInfo;

/* The context a TlsOptions describes (certificate, key, roots for client verification or the client's trust,
 * ALPN); NULL for options that cannot be used. */
MsNetTlsCtx *ms_net_tls_ctx_from_options(bool server, const MsTlsOptions *options);

/* Runs the server handshake of a TLS listener's context on an accepted connection; closes it on failure. */
uint8_t ms_net_tls_serve(MsNetCore *core, int64_t timeout_ns, MsString *err);

/* Upgrades the connection behind `handle` and returns another handle on it (the caller drops the old one). A failed or
 * timed out handshake closes the connection. */
/* ms-sig: msstd_net_connection_start_tls(handle c: *const ObjCell<ConnH>, opts: *const TlsOptionsWire, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_connection_start_tls(const MsObj *handle, const MsTlsOptions *options, uint8_t has_timeout,
                                       int64_t timeout, MsObj **out, MsString *err);
/* ms-sig: msstd_net_connection_accept_tls(handle c: *const ObjCell<ConnH>, opts: *const TlsOptionsWire, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_connection_accept_tls(const MsObj *handle, const MsTlsOptions *options, uint8_t has_timeout,
                                        int64_t timeout, MsObj **out, MsString *err);
/* ms-sig: msstd_net_connection_tls_info(handle c: *const ObjCell<ConnH>, out: *mut TlsInfoWire) -> u8 @domain=network */
uint8_t msstd_net_connection_tls_info(const MsObj *handle, MsTlsInfo *out);
/* ms-sig: msstd_net_network_connect_tls_config(handle net: *const ObjCell<NetH>, address: *const StrVal, opts: *const TlsOptionsWire, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_connect_tls_config(const MsObj *net, const MsString *address, const MsTlsOptions *options,
                                             uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);
/* ms-sig: msstd_net_network_listen_tls(handle net: *const ObjCell<NetH>, address: *const StrVal, opts: *const TlsOptionsWire, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ListenerH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_listen_tls(const MsObj *net, const MsString *address, const MsTlsOptions *options,
                                     uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);

#endif
