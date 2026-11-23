/* runtime/std/net_conn.h: the connection natives of @std/net and the calls the network scope and the listener make on
 * connections (net_conn.c). Failures are MS_STATUS_* codes, with the text in `err` for MS_STATUS_FAILED. */
#ifndef MS_RUNTIME_STD_NET_CONN_H
#define MS_RUNTIME_STD_NET_CONN_H

#include "base/bytes.h"
#include "runtime/std/net_core.h"
#include "runtime/std/net_filter.h"

/* Dials "host:port" (a name is resolved) or the Unix socket at `path`, waiting at most `timeout_ns` (negative: no limit). */
uint8_t ms_net_dial(MsSpan address, MsNetFilter *filter, int64_t timeout_ns, MsObj **out, MsString *err);
uint8_t ms_net_dial_unix(MsSpan path, int64_t timeout_ns, MsObj **out, MsString *err);

/* Listens on the IP literal "ip:port" or the Unix socket at `path`; binds a UDP socket (net_listen.c). */
uint8_t ms_net_listen(MsSpan address, MsObj **out, MsString *err);
uint8_t ms_net_listen_unix(MsSpan path, MsObj **out, MsString *err);
uint8_t ms_net_bind_datagram(MsSpan address, MsObj **out, MsString *err);
bool ms_net_parse_literal(MsSpan address, struct sockaddr_storage *out);

/* ms-sig: msstd_net_listener_accept(handle l: *const ObjCell<ListenerH>, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_listener_accept(const MsObj *handle, uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err);
/* ms-sig: msstd_net_listener_accept_raw(handle l: *const ObjCell<ListenerH>, has_timeout: HasRaw, timeout: i64, out: *mut i64, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_listener_accept_raw(const MsObj *handle, uint8_t has_timeout, int64_t timeout, int64_t *out,
                                      MsString *err);
/* ms-sig: msstd_net_listener_address(handle l: *const ObjCell<ListenerH>, out: *mut StrVal) @domain=network */
void msstd_net_listener_address(const MsObj *handle, MsString *out);
/* ms-sig: msstd_net_listener_close(handle l: *const ObjCell<ListenerH>) @domain=network */
void msstd_net_listener_close(const MsObj *handle);
/* ms-sig: msstd_net_listener_share(handle l: *const ObjCell<ListenerH>) -> *mut ObjCell<ListenerH> @domain=network @end */
MsObj *msstd_net_listener_share(const MsObj *handle);

/* Up to `capacity` bytes: MS_STATUS_NONE at the end of the stream. */
uint8_t ms_net_read(MsNetCore *core, size_t capacity, int64_t timeout_ns, MsBytes *out, MsString *err);
uint8_t ms_net_write(MsNetCore *core, MsSpan data, int64_t timeout_ns, MsString *err);
uint8_t ms_net_shutdown(MsNetCore *core, MsString *err);

/* ms-sig: msstd_net_connection_read(handle c: *const ObjCell<ConnH>, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_connection_read(const MsObj *handle, uint8_t has_max, int64_t max, uint8_t has_timeout,
                                  int64_t timeout, MsBytes *out, MsString *err);
/* ms-sig: msstd_net_connection_write_bytes(handle c: *const ObjCell<ConnH>, data: *const VecVal, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_connection_write_bytes(const MsObj *handle, const MsBytes *data, uint8_t has_timeout, int64_t timeout,
                                         MsString *err);
/* ms-sig: msstd_net_connection_shutdown_write(handle c: *const ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_connection_shutdown_write(const MsObj *handle, MsString *err);
/* ms-sig: msstd_net_connection_close(handle c: *const ObjCell<ConnH>) @domain=network */
void msstd_net_connection_close(const MsObj *handle);
/* ms-sig: msstd_net_connection_share(handle c: *const ObjCell<ConnH>) -> *mut ObjCell<ConnH> @domain=network @end */
MsObj *msstd_net_connection_share(const MsObj *handle);
/* ms-sig: msstd_net_connection_alias(handle c: *const ObjCell<ConnH>) -> *mut ObjCell<ConnH> @domain=network @end */
MsObj *msstd_net_connection_alias(const MsObj *handle);
/* ms-sig: msstd_net_connection_close_if_last(handle c: *const ObjCell<ConnH>) @domain=network */
void msstd_net_connection_close_if_last(const MsObj *handle);
/* ms-sig: msstd_net_connection_local_address(handle c: *const ObjCell<ConnH>, out: *mut StrVal) @domain=network */
void msstd_net_connection_local_address(const MsObj *handle, MsString *out);
/* ms-sig: msstd_net_connection_peer_address(handle c: *const ObjCell<ConnH>, out: *mut StrVal) @domain=network */
void msstd_net_connection_peer_address(const MsObj *handle, MsString *out);
/* ms-sig: msstd_net_connection_adopt(raw: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_connection_adopt(int64_t raw, MsObj **out, MsString *err);
/* ms-sig: msstd_net_pending_release(raw: i64) @domain=network */
void msstd_net_pending_release(int64_t raw);

#endif
