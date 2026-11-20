/* ms_rt/net.h: the client natives of @std/net (runtime/net/natives.c over the connection rows). Fallible functions
 * return a status (0 ok, STATUS_NONE at the end of a stream, otherwise the runtime's STATUS_* code; STATUS_FAILED
 * carries its text through `err`) and write their result through an out parameter only on success. Times are
 * nanoseconds. Symbols are listed in runtime/symbols/net.txt.
 *
 * Policy (which hosts a Network may reach, the resolver choice, redirects, cookies) is standard-library code that
 * calls these between lookup and dial. Addresses travel as text, "1.2.3.4:80" or "[::1]:80". */
#ifndef MS_RT_NET_H
#define MS_RT_NET_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms: domain network */

/* TlsOptions flattened (crates/ms-std-net ffi TlsOptionsWire): PEM texts are empty for none; `alpn` is a list of
 * strings, most preferred first. */
typedef struct MsNetTlsOptions {
    MsStr server_name;
    MsStr roots_pem;
    MsStr certificate_pem;
    MsStr private_key_pem;
    MsVec alpn;
    uint8_t require_client_certificate;
} MsNetTlsOptions;

/* TlsInfo flattened: version (0x0303, 0x0304), IANA cipher suite number, the negotiated protocol, the peer chain as a
 * list of Bytes (leaf first), and whether the peer was verified. */
typedef struct MsNetTlsInfo {
    int64_t version;
    int64_t cipher_suite;
    MsStr alpn;
    MsVec peer_certificates;
    uint8_t verified;
} MsNetTlsInfo;

/* Resolves `host` for TCP on `port` through the reactor: the addresses as text, at most 16, in resolver order. No
 * name is filtered here. */
/* ms-sig: msstd_net_lookup(host: *const StrVal, port: i64, has_timeout: HasRaw, timeout: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_lookup(const MsStr *host, int64_t port, uint8_t has_timeout, int64_t timeout, MsVec *out, MsStr *err);

/* Connects to one address and, with `has_tls`, runs the TLS handshake as a client: `server_name` (else the options')
 * is sent and verified. Nothing stays open on failure. */
/* ms-sig: msstd_net_dial(address: *const StrVal, server_name: *const StrVal, has_tls: u8, tls: *const TlsOptionsWire, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_dial(const MsStr *address, const MsStr *server_name, uint8_t has_tls, const MsNetTlsOptions *tls, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err);

/* Connection handles. `share` is another end of the same connection and `alias` another handle that is not an end;
 * `close_if_last` closes when no other end is open; `close` closes at once. */
/* ms-sig: msstd_conn_read(handle c: *const ObjCell<ConnH>, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_conn_read(const void *handle, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsVec *out, MsStr *err);
/* ms-sig: msstd_conn_write_bytes(handle c: *const ObjCell<ConnH>, data: *const VecVal, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_conn_write_bytes(const void *handle, const MsVec *data, uint8_t has_timeout, int64_t timeout, MsStr *err);
/* ms-sig: msstd_conn_shutdown_write(handle c: *const ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_conn_shutdown_write(const void *handle, MsStr *err);
/* ms-sig: msstd_conn_close(handle c: *const ObjCell<ConnH>) @domain=network */
void msstd_conn_close(const void *handle);
/* ms-sig: msstd_conn_share(handle c: *const ObjCell<ConnH>) -> *mut ObjCell<ConnH> @handle @domain=network */
void *msstd_conn_share(const void *handle);
/* ms-sig: msstd_conn_alias(handle c: *const ObjCell<ConnH>) -> *mut ObjCell<ConnH> @handle @domain=network */
void *msstd_conn_alias(const void *handle);
/* ms-sig: msstd_conn_close_if_last(handle c: *const ObjCell<ConnH>) @domain=network */
void msstd_conn_close_if_last(const void *handle);
/* ms-sig: msstd_conn_local_address(handle c: *const ObjCell<ConnH>, out: *mut StrVal) @domain=network */
void msstd_conn_local_address(const void *handle, MsStr *out);
/* ms-sig: msstd_conn_peer_address(handle c: *const ObjCell<ConnH>, out: *mut StrVal) @domain=network */
void msstd_conn_peer_address(const void *handle, MsStr *out);
/* The TLS facts of a connection; 0 (and *out untouched) for a plain one. */
/* ms-sig: msstd_conn_tls_info(handle c: *const ObjCell<ConnH>, out: *mut TlsInfoWire) -> u8 @domain=network */
uint8_t msstd_conn_tls_info(const void *handle, MsNetTlsInfo *out);

#endif
