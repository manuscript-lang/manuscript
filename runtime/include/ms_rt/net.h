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

/* Header tables (HeadersH): an ordered multimap with ASCII case-insensitive names; values are bytes, those of one name
 * are kept together in the order added, and a name keeps the spelling of its first use. `append` refuses a name that
 * is not an HTTP token (STATUS_INVALID_INPUT) and a table past 1024 fields or 1 MiB (STATUS_LIMIT_EXCEEDED). `values`
 * returns 1 with a list of Bytes, or 0 for a name that is not there; `remove` returns 1 when it removed something. */
/* ms-sig: msstd_headers_new() -> *mut ObjCell<HeadersH> @handle @domain=HTTP */
void *msstd_headers_new(void);
/* ms-sig: msstd_headers_clone(handle h: *const ObjCell<HeadersH>) -> *mut ObjCell<HeadersH> @handle @domain=HTTP */
void *msstd_headers_clone(const void *handle);
/* ms-sig: msstd_headers_append(handle h: *const ObjCell<HeadersH>, name: *const StrVal, value: *const VecVal) -> u8 @domain=HTTP */
uint8_t msstd_headers_append(const void *handle, const MsStr *name, const MsVec *value);
/* ms-sig: msstd_headers_values(handle h: *const ObjCell<HeadersH>, name: *const StrVal, out: *mut VecVal) -> u8 @domain=HTTP */
uint8_t msstd_headers_values(const void *handle, const MsStr *name, MsVec *out);
/* ms-sig: msstd_headers_names(handle h: *const ObjCell<HeadersH>, out: *mut VecVal) @domain=HTTP */
void msstd_headers_names(const void *handle, MsVec *out);
/* ms-sig: msstd_headers_remove(handle h: *const ObjCell<HeadersH>, name: *const StrVal) -> u8 @domain=HTTP */
uint8_t msstd_headers_remove(const void *handle, const MsStr *name);

/* One HTTP exchange on a dialed connection: the request out, the response head in, and a body object to read the rest
 * from. HTTP/2 when the connection's TLS handshake negotiated "h2", HTTP/1.1 otherwise. It follows no redirects, keeps
 * no cookies and decodes no content-encoding; that is policy of the standard library. `target` is the path and query,
 * `authority` is host[:port], sent as Host or :authority. Host, Content-Length and Transfer-Encoding (and, for
 * HTTP/2, the connection-specific fields) are written by the exchange, and a request that names one is
 * STATUS_INVALID_INPUT, as is a value holding CR, LF or NUL. A non-empty `body` is sent with its Content-Length.
 *
 * The timeout covers the whole exchange, including the reads of the body. One exchange is open on a connection at a
 * time: a second fetch before the body is closed or dropped is STATUS_BUSY. Closing a body that was read to its end
 * on a keep-alive response (or any HTTP/2 stream) leaves the connection open for the next fetch; anything else closes
 * it, and a later call on it is STATUS_CLOSED. */
/* ms-sig: msstd_http_fetch(handle c: *const ObjCell<ConnH>, method: *const StrVal, authority: *const StrVal, target: *const StrVal, handle headers: *const ObjCell<HeadersH>, body: *const VecVal, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<BodyH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_http_fetch(const void *handle, const MsStr *method, const MsStr *authority, const MsStr *target, const void *headers, const MsVec *body, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err);

/* BodyMetadata flattened: the status, a copy of the response headers and the protocol ("HTTP/1.1" or "HTTP/2.0").
 * Valid after the body is closed. */
typedef struct MsNetBodyMetadata {
    int64_t status;
    void *headers;
    MsStr protocol;
} MsNetBodyMetadata;

/* The response body. `read` returns up to `max` bytes (at most 64 KiB, default 64 KiB) and STATUS_NONE at the end;
 * `read_all` returns the rest, STATUS_LIMIT_EXCEEDED when it passes `max`. The bytes are the message body with the
 * transfer framing removed and the content-encoding untouched. A failed read leaves the connection closed. */
/* ms-sig: msstd_body_read(handle b: *const ObjCell<BodyH>, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_body_read(const void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err);
/* ms-sig: msstd_body_read_all(handle b: *const ObjCell<BodyH>, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_body_read_all(const void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err);
/* ms-sig: msstd_body_metadata(handle b: *const ObjCell<BodyH>, out: *mut MetadataWire) @domain=network */
void msstd_body_metadata(const void *handle, MsNetBodyMetadata *out);
/* ms-sig: msstd_body_close(handle b: *const ObjCell<BodyH>) @domain=network */
void msstd_body_close(const void *handle);

#endif
