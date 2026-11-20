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

/* The HTTP client (ClientH), over libcurl: one client holds a connection pool (HTTP/2 requests to a host share one
 * connection), cookies, TLS roots and a network filter. `share` is another handle on the same client. `narrow` adds a
 * level to the filter (stdlib/net/policy.ms): the host names and CIDR ranges a request may reach, including every
 * redirect target; STATUS_INVALID_INPUT for a CIDR that is not valid. Narrow before the first request. */
typedef struct MsNetHttpOptions {
    MsStr roots_pem;          /* extra trusted roots; empty for the system's */
    MsStr certificate_pem;    /* a client certificate and its key, or empty */
    MsStr private_key_pem;
    MsStr unix_socket;        /* a Unix domain socket path used for every connection instead of TCP, or empty; the URL still
                                 gives the Host header and scheme. Refused for a narrowed client. */
    int64_t max_redirects;    /* 0 follows none; negative takes 20 */
    uint8_t cookies;          /* keep cookies across this client's requests */
    uint8_t decompress;       /* ask for gzip and deflate and decode them */
} MsNetHttpOptions;
/* ms-sig: msstd_client_new(options: *const HttpClientOptionsWire, out: *mut *mut ObjCell<ClientH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_client_new(const MsNetHttpOptions *options, void **out, MsStr *err);
/* ms-sig: msstd_client_share(handle c: *const ObjCell<ClientH>) -> *mut ObjCell<ClientH> @handle @domain=network */
void *msstd_client_share(const void *handle);
/* Ends the client's transfers (a body read or a request in progress returns STATUS_CLOSED) and refuses later requests
 * with STATUS_CLOSED. Safe to repeat. */
/* ms-sig: msstd_client_close(handle c: *const ObjCell<ClientH>) @domain=network */
void msstd_client_close(const void *handle);
/* ms-sig: msstd_client_narrow(handle c: *const ObjCell<ClientH>, hosts: *const VecVal, cidrs: *const VecVal) -> u8 @domain=network */
uint8_t msstd_client_narrow(const void *handle, const MsVec *hosts, const MsVec *cidrs);

/* One request: the response head in the body object, the body streamed by `msstd_body_read`. `url` is absolute
 * (http or https); the method, the URL and the fields are checked (STATUS_INVALID_INPUT), and a request whose host,
 * redirect target or resolved address the filter refuses is STATUS_PERMISSION_DENIED. Host, Content-Length and
 * Transfer-Encoding are written by the client and refused as caller fields. The timeout covers the whole exchange,
 * body reads included. Redirects, cookies and decompression follow the client's options; the version is chosen by
 * ALPN. */
/* ms-sig: msstd_client_fetch(handle c: *const ObjCell<ClientH>, method: *const StrVal, url: *const StrVal, handle headers: *const ObjCell<HeadersH>, body: *const VecVal, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<BodyH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_client_fetch(const void *handle, const MsStr *method, const MsStr *url, const void *headers, const MsVec *body, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err);

/* BodyMetadata flattened: the status, a copy of the response headers and the protocol ("HTTP/1.1" or "HTTP/2.0").
 * Valid after the body is closed. */
typedef struct MsNetBodyMetadata {
    int64_t status;
    void *headers;
    MsStr protocol;
} MsNetBodyMetadata;

/* The response body. `read` returns up to `max` bytes (at most 64 KiB, default 64 KiB) and STATUS_NONE at the end;
 * `read_all` returns the rest, STATUS_LIMIT_EXCEEDED when it passes `max`. The bytes are the message body with the
 * transfer framing removed (and the content-encoding decoded when the client decompresses). Closing a body that was
 * read to its end returns the connection to the client's pool; any other close drops it. */
/* ms-sig: msstd_body_read(handle b: *const ObjCell<BodyH>, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_body_read(const void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err);
/* ms-sig: msstd_body_read_all(handle b: *const ObjCell<BodyH>, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_body_read_all(const void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err);
/* ms-sig: msstd_body_metadata(handle b: *const ObjCell<BodyH>, out: *mut MetadataWire) @domain=network */
void msstd_body_metadata(const void *handle, MsNetBodyMetadata *out);
/* ms-sig: msstd_body_close(handle b: *const ObjCell<BodyH>) @domain=network */
void msstd_body_close(const void *handle);

/* Datagram sockets (DgramH): a UDP socket bound to a literal address. Addresses are text, "1.2.3.4:80"; a name is
 * resolved by the caller. `receive` waits for one datagram of at most `max` bytes (1 to 65535, default 65535): a longer
 * one is dropped and gives STATUS_LIMIT_EXCEEDED. `send` gives STATUS_LIMIT_EXCEEDED for more than 65535 bytes.
 * `close` ends all use at once; a call blocked in a wait ends by its deadline or cancellation. Handles follow the
 * connection handles: `share` is another end, `close_if_last` closes when no other end is open. */
typedef struct MsNetDatagram {
    MsVec data;
    MsStr sender;
} MsNetDatagram;

/* ms-sig: msstd_dgram_bind(address: *const StrVal, out: *mut *mut ObjCell<DgramH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_dgram_bind(const MsStr *address, void **out, MsStr *err);
/* ms-sig: msstd_dgram_address(handle s: *const ObjCell<DgramH>, out: *mut StrVal) @domain=network */
void msstd_dgram_address(const void *handle, MsStr *out);
/* ms-sig: msstd_dgram_close(handle s: *const ObjCell<DgramH>) @domain=network */
void msstd_dgram_close(const void *handle);
/* ms-sig: msstd_dgram_share(handle s: *const ObjCell<DgramH>) -> *mut ObjCell<DgramH> @handle @domain=network */
void *msstd_dgram_share(const void *handle);
/* Another handle on the socket that is not an end: it keeps the socket's memory, not its descriptor. */
/* ms-sig: msstd_dgram_alias(handle s: *const ObjCell<DgramH>) -> *mut ObjCell<DgramH> @handle @domain=network */
void *msstd_dgram_alias(const void *handle);
/* ms-sig: msstd_dgram_close_if_last(handle s: *const ObjCell<DgramH>) @domain=network */
void msstd_dgram_close_if_last(const void *handle);
/* ms-sig: msstd_dgram_receive(handle s: *const ObjCell<DgramH>, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout: i64, out: *mut DatagramWire, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_dgram_receive(const void *handle, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsNetDatagram *out, MsStr *err);
/* ms-sig: msstd_dgram_send(handle s: *const ObjCell<DgramH>, data: *const VecVal, address: *const StrVal, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_dgram_send(const void *handle, const MsVec *data, const MsStr *address, uint8_t has_timeout, int64_t timeout, MsStr *err);

/* Network scopes (ScopeH): what `Network.close` closes. A scope remembers the sockets, connections and listeners opened through it and
 * the scopes derived from it; `close` closes them all (once) and later `track` calls close the socket they are given
 * and return 0. `child` is a scope that closes with this one. `open` is 1 until the scope is closed. */
/* ms-sig: msstd_scope_new() -> *mut ObjCell<ScopeH> @handle @domain=network */
void *msstd_scope_new(void);
/* ms-sig: msstd_scope_share(handle s: *const ObjCell<ScopeH>) -> *mut ObjCell<ScopeH> @handle @domain=network */
void *msstd_scope_share(const void *handle);
/* ms-sig: msstd_scope_child(handle s: *const ObjCell<ScopeH>) -> *mut ObjCell<ScopeH> @handle @domain=network */
void *msstd_scope_child(const void *handle);
/* ms-sig: msstd_scope_open(handle s: *const ObjCell<ScopeH>) -> u8 @domain=network */
uint8_t msstd_scope_open(const void *handle);
/* ms-sig: msstd_scope_close(handle s: *const ObjCell<ScopeH>) @domain=network */
void msstd_scope_close(const void *handle);
/* ms-sig: msstd_scope_track_conn(handle s: *const ObjCell<ScopeH>, handle conn: *const ObjCell<ConnH>) -> u8 @domain=network */
uint8_t msstd_scope_track_conn(const void *handle, const void *connection);
/* ms-sig: msstd_scope_track_listener(handle s: *const ObjCell<ScopeH>, handle listener: *const ObjCell<ListenerH>) -> u8 @domain=network */
uint8_t msstd_scope_track_listener(const void *handle, const void *listener);
/* ms-sig: msstd_scope_track_dgram(handle s: *const ObjCell<ScopeH>, handle socket: *const ObjCell<DgramH>) -> u8 @domain=network */
uint8_t msstd_scope_track_dgram(const void *handle, const void *socket);

/* TLS on a plain connection, in place (runtime/net/tls_conn.c): the handshake runs on the row, then the result is
 * another handle on the same connection and the caller drops the old one. `start_tls` is the client side (the
 * options' server_name is sent and verified against roots_pem, the system roots when empty); `accept_tls` is the
 * server side (certificate_pem and private_key_pem required; with roots_pem or require_client_certificate the client
 * is asked for a certificate). STATUS_INVALID_INPUT for unusable options or a connection that is already TLS; a failed
 * or timed out handshake closes the connection. */
/* ms-sig: msstd_conn_start_tls(handle c: *const ObjCell<ConnH>, options: *const TlsOptionsWire, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_conn_start_tls(const void *handle, const MsNetTlsOptions *options, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err);
/* ms-sig: msstd_conn_accept_tls(handle c: *const ObjCell<ConnH>, options: *const TlsOptionsWire, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_conn_accept_tls(const void *handle, const MsNetTlsOptions *options, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err);
/* The application protocol the handshake chose ("h2", "http/1.1"), empty for none or a plain connection. */
/* ms-sig: msstd_conn_alpn(handle c: *const ObjCell<ConnH>, out: *mut StrVal) @domain=network */
void msstd_conn_alpn(const void *handle, MsStr *out);

/* The certificate natives of @std/net/tls (runtime/net/tls_natives.c). A Timestamp is two words. */
typedef struct MsTlsTimestamp {
    int64_t seconds;
    int64_t nanos;
} MsTlsTimestamp;

/* The certificates of a PEM text as a `List[CertificateInfo]`; `max` applies when `has_max`. */
/* ms-sig: msstd_tls_parse_certificates(pem: *const StrVal, has_max: HasRaw, max: i64, out: *mut VecVal) -> u8 @domain=TLS */
uint8_t msstd_tls_parse_certificates(const MsStr *pem, uint8_t has_max, int64_t max, MsVec *out);
/* Verifies a chain (leaf first) against the roots for a name at `now`. */
/* ms-sig: msstd_tls_verify_certificates(chain: *const StrVal, roots: *const StrVal, server_name: *const StrVal, now: *const Timestamp) -> u8 @domain=TLS */
uint8_t msstd_tls_verify_certificates(const MsStr *chain, const MsStr *roots, const MsStr *server_name, const MsTlsTimestamp *now);

/* Listeners (ListenerH, runtime/net/server_natives.c). `listen` binds one address (an IP literal with a port; port 0
 * picks one) and `accept` parks the task until a connection arrives: the connection is a ConnH like a dialed one.
 * `close` stops later accepts; an accept already parked ends when its task is cancelled. */
/* ms-sig: msstd_net_listen(address: *const StrVal, out: *mut *mut ObjCell<ListenerH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_listen(const MsStr *address, void **out, MsStr *err);
/* ms-sig: msstd_listener_accept(handle l: *const ObjCell<ListenerH>, has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_listener_accept(const void *handle, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err);
/* ms-sig: msstd_listener_address(handle l: *const ObjCell<ListenerH>, out: *mut StrVal) @domain=network */
void msstd_listener_address(const void *handle, MsStr *out);
/* Connects to the Unix domain socket at `path` and gives a plain connection. The connect itself blocks only while the
 * listener's queue is full. An empty path or one with a NUL byte is STATUS_INVALID_INPUT; one longer than the system's
 * limit is STATUS_FAILED. The connection's own addresses are empty text. */
/* ms-sig: msstd_net_dial_unix(path: *const StrVal, out: *mut *mut ObjCell<ConnH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_dial_unix(const MsStr *path, void **out, MsStr *err);

/* Listens on a new Unix domain socket at `path`; accept and close are the listener natives of ms_rt/net.h, its address
 * is `path`, and the file is removed when the listener is dropped. An existing file at `path` fails the bind. */
/* ms-sig: msstd_net_listen_unix(path: *const StrVal, out: *mut *mut ObjCell<ListenerH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_listen_unix(const MsStr *path, void **out, MsStr *err);

/* Another handle on the same listener; the descriptor closes when the last one is dropped. */
/* ms-sig: msstd_listener_share(handle l: *const ObjCell<ListenerH>) -> *mut ObjCell<ListenerH> @handle @domain=network */
void *msstd_listener_share(const void *handle);
/* ms-sig: msstd_listener_close(handle l: *const ObjCell<ListenerH>) @domain=network */
void msstd_listener_close(const void *handle);

#endif
