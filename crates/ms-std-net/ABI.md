# ms-std-net ABI

Native implementations of `@std/net.ms`, `@std/net.ms`, `@std/http.ms` and
`@std/net.ms` for the Rust pipeline. The general rules are those of
[`crates/ms-rt/ABI.md`](../ms-rt/ABI.md); this file adds what is specific to these
modules. Behavior follows the standard-library contract in `stdlib/`. `@std/sse.ms` is written in Manuscript and
has no natives.

Linking: `libms_std_net.a` is linked into `libms_native.a` when a program imports one
of these modules. The crate calls `msrt_*` symbols (allocation, strings, retain and
release, cancellation) and never the other way around.

## Conventions

- **Status.** A fallible native returns `u8`: `0` is success; otherwise `1 + the
  declaration index` of the error case in the `.ms` error type. Tables below.
  `Failed(message)` stores its text through the trailing `err: *mut StrVal`
  (owned string; the pointer may be null when the caller does not need it).
- **Results.** An ok value is written through `out` (before `err`). An `Optional[T]` in a
  `Result` answers `STATUS_NONE` (16) for none; a bare `Optional[T]` answers whether it is
  present. Native handles are `*mut Obj`. Wire structs are passed by address and have the
  leaves of the language record (lists inline as `VecVal`).
- **Optional parameters** flatten to `has: u8, value: i64` (`Optional[Int]`,
  `Optional[Duration]`; a `Duration` is nanoseconds). A negative limit or timeout is
  `InvalidInput`, as in Go.
- **Handles.** `Network`, `Connection`, `Listener`, `DatagramSocket`, `IpAddress`,
  `Cidr` (and later `HttpHeaders`, clients, servers, sockets) are runtime objects: an
  `Obj` header (`rc`, `drop`) followed by the Rust value. The caller owns the count it
  received (`out` handles are +1) and releases it with `msrt_release`; the drop entry
  closes the resource. `Network.close()` and `close()` on a resource are explicit and
  idempotent; dropping a handle does not run the Go-visible close order.
- **Interfaces.** `Network`, `Connection`, `Listener`, `DatagramSocket` are interfaces
  in `.ms`: the compiler builds the vtable whose methods call the `msrt_net_*` symbols
  below with the handle as data pointer.
- **Blocking.** Calls block the ms thread. While waiting they poll the cancel flag
  (the isolate's cancel flag, 50 ms granularity) and call `msrt_cancelled()` when it is set,
  and they run queued HTTP server handlers on the same thread (see HTTP). Nothing else in
  this crate calls `msrt_*` from a helper thread.
- **Names.** `msrt_net_<type>_<method>` (`msrt_net_connection_read`); free functions are
  `msrt_net_<name>`.

## Status tables

| Type | Cases (status 1, 2, ...) |
| --- | --- |
| `NetworkError` | InvalidInput, InvalidData, LimitExceeded, PermissionDenied, Unsupported, Closed, Timeout, Failed |
| `IoError` | Closed, InvalidInput, Unavailable, InvalidData, LimitExceeded, Failed |
| `HttpError` | InvalidInput, InvalidData, LimitExceeded, PermissionDenied, Closed, Timeout, Failed |
| `WebSocketError` | InvalidInput, InvalidData, LimitExceeded, PermissionDenied, Closed, Timeout, Failed |
| `TlsError` | InvalidInput, InvalidData, LimitExceeded, AuthenticationFailed |

`Error.message()` is `msrt_net_error_message(status, failed_or_null)` for `NetworkError`
(and `msrt_http_`, `msrt_websocket_`, `msrt_tls_` forms for the other types). Messages
carry no input values except `Failed` text, which is verbatim.

## net

`DnsKind` case indices: `A`=0, `AAAA`=1, `CNAME`=2, `MX`=3, `NS`=4, `TXT`=5, `PTR`=6, `SRV`=7.
`IpFamily`: `IPv4`=0, `IPv6`=1.

```text
msrt_net_parse_ip(text, out: *mut *mut Obj, err) -> u8
msrt_net_parse_cidr(text, out, err) -> u8
msrt_net_contains_ip(cidr, ip, out: *mut u8) -> u8
msrt_net_ip_address_text(ip, out: *mut StrVal)          msrt_net_ip_address_family(ip) -> u8
msrt_net_cidr_text(cidr, out: *mut StrVal)              msrt_net_ip_family_text(u8) / msrt_net_dns_kind_text(u8, out: *mut StrVal)
msrt_net_error_message(status, has_failed, failed: *const StrVal, out: *mut StrVal)
msrt_net_network() -> *mut Obj                       the host's root network (+1)
msrt_net_network_close(net)
msrt_net_network_connect(net, address, has_timeout, timeout, out, err) -> u8
msrt_net_network_connect_unix(net, path, has_timeout, timeout, out, err) -> u8
msrt_net_network_listen(net, address, out, err) -> u8
msrt_net_network_listen_unix(net, path, out, err) -> u8
msrt_net_network_bind_datagram(net, address, out, err) -> u8
msrt_net_network_restrict(net, hosts: *const VecVal, cidrs: *const VecVal, allow_listen: u8, out, err) -> u8
msrt_net_network_with_resolver(net, address, out, err) -> u8
msrt_net_network_lookup(net, name, has_max, max, has_timeout, timeout, out: *mut VecVal /* List[String] */, err) -> u8
msrt_net_network_resolve(net, name, kind: u8, has_max, max, has_timeout, timeout,
                         records: *mut *mut DnsRecordWire, count: *mut usize, err) -> u8
msrt_net_connection_{close, local_address, peer_address, shutdown_write(err) -> u8}
msrt_net_connection_read(c, has_max, max, has_timeout, timeout, out: *mut VecVal, err) -> u8   # STATUS_NONE (16) at end of stream
msrt_net_connection_write(c, data: String, has_timeout, timeout, err) -> u8
msrt_net_connection_write_bytes(c, data: *const VecVal, has_timeout, timeout, err) -> u8
msrt_net_listener_{accept(l, has_timeout, timeout, out, err) -> u8, address, close}
msrt_net_datagram_{address, close}  # receiver `sock`
msrt_net_datagram_receive(sock, has_max, max, has_timeout, timeout, out: *mut DatagramWire { data: VecVal, sender: StrVal }, err) -> u8
msrt_net_datagram_send(sock, data: String, address, has_timeout, timeout, err) -> u8
msrt_net_datagram_send_bytes(sock, data: *const VecVal, address, has_timeout, timeout, err) -> u8
```

`DnsRecordWire { kind: u8, value: StrVal, priority: i64, weight: i64, port: i64 }`
(40 bytes): `msrt_net_network_resolve` allocates `count` of them with `msrt_alloc`; the
compiler moves each string into a `DnsRecord` and frees the array with `msrt_free`.

Behavior notes (same as Go unless stated):

- Addresses are `host:port` with IPv6 hosts in brackets; Unix sockets use their path.
  A Unix listener removes its socket file on close.
- `Connection.read` caps a chunk at 65536 bytes, answers `STATUS_NONE` at EOF, and a
  local timeout is `IoError.Failed("operation timed out")`.
- `lookup`/`resolve` of A and AAAA on the default network use the system resolver
  (`getaddrinfo`) on a helper thread so a timeout or stop request is honored; other
  record kinds and networks made with `with_resolver` speak DNS (UDP, TCP fallback)
  using `/etc/resolv.conf` for the server, search list and `ndots`.
- A restricted network checks the host name and every resolved address; Unix sockets
  and listening need an unrestricted network or `allow_listen`.
- Closing a network closes the resources it opened, newest first, then its derived
  networks' resources.

## tls

```text
msrt_net_network_connect_tls(net, address, server_name, has_timeout, timeout, out, err) -> u8
msrt_net_network_connect_tls_config(net, address, opts: *const TlsOptionsWire, has_timeout, timeout, out, err) -> u8
msrt_net_network_listen_tls(net, address, opts: *const TlsOptionsWire, has_handshake_timeout, handshake_timeout, out, err) -> u8
msrt_net_connection_tls_info(c, out: *mut TlsInfoWire) -> u8          // TlsError status
msrt_tls_parse_certificates(pem, has_max, max, certs: *mut *mut CertificateInfoWire, count: *mut usize) -> u8
msrt_tls_verify_certificates(chain_pem, roots_pem, server_name, now_seconds: i64, now_nanos: i32) -> u8
msrt_tls_error_message(status) -> String
```

`TlsOptionsWire { server_name, roots_pem, certificate_pem, private_key_pem: *const StrVal,
alpn: *const VecVal (List[String]), require_client_certificate: u8 }`. `TlsInfoWire` and
`CertificateInfoWire` are filled by the native; the caller takes the strings, lists and
`Bytes` and frees the arrays with `msrt_free` (see `ffi/tls.rs` for the field order).

Behavior notes:

- Trust decisions follow Go's `crypto/x509`, not webpki: the chain is built from the
  presented intermediates to the supplied roots (system roots when `roots_pem` is
  empty); a CA certificate may be a leaf and a leaf that equals a root is trusted;
  names match DNS SANs (one-label wildcards) or IP SANs; a leaf with an extended key usage
  needs server-auth (client-auth for client certificates). Minimum TLS 1.2.
- PEM input for roots and chains is strict (CERTIFICATE blocks only, no headers); keys
  accept PKCS#8, PKCS#1 and SEC1.
- Subject and issuer text is `pkix.Name.String()` of Go (reverse RDN order, escaped).
- Option errors surface after dialing, as in Go (`InvalidInput`); handshake and
  verification failures are `Failed(<Go-style text>)`.

## http

`HttpHeaders` is a handle. `append(name, values)` validates tokens and values and
returns `HttpError` status; `values(name)` returns an **owned copy** of the list (lists
are values in the ownership model; Go shares them) and `present`; `text(name)` joins with
`, `. Methods arrive as token strings; an invalid method is `InvalidInput`.

Wire structs (`#[repr(C)]`, `ffi/http.rs`): `OptWire { present: u8, value: i64 }`;
`HttpClientOptionsWire { max_redirects, max_idle_connections, max_header_bytes,
idle_timeout: OptWire, decompress: u8, cookies: u8, tls: TlsOptionsWire }`;
`HttpServerOptionsWire { max_requests, max_body_bytes, max_response_bytes,
max_header_bytes, timeout, grace: OptWire, tls_present: u8, tls }`; `RequestWire
{ method, path, query, protocol, headers, body }` and `ResponseWire { status, headers,
body }` (all fields owned, +1); `ClientResponseWire { status, headers, protocol, body }`;
`MetadataWire { status, headers, protocol }`; `request_stream` takes a `src`
closure (compiler generated, borrowed for the call) wrapping the `ReadStream`; its code word
follows the `Connection.read` convention: `read(env, has_max, max, out, present, err) -> status`.

```text
msrt_net_network_http_client(net, opts, out, err) -> u8
msrt_http_client_request[_bytes|_stream](c, method, address, headers, body, has_max, max, has_timeout, timeout, out, err) -> u8
msrt_net_network_request[_bytes](net, method, address, headers, body, has_max, max, has_timeout, timeout, out: *mut ClientResponseWire, err) -> u8
msrt_http_body_{read,metadata,close}
msrt_net_network_serve(net, address, env, limits..., out, err) -> u8
msrt_net_network_serve_stream(net, address, env, opts, out, err) -> u8
msrt_http_server_{address,close,wait}
msrt_http_exchange_{headers,method,path,protocol,query,read,send_headers,send,write,write_bytes,close,upgrade}
```

Handlers are compiler generated closures that run on the ms thread, each request in its
own `ms-rt` task (see Concurrency). The server calls the closure's code word:
`BufferedThunk(env, req, resp)` fills `resp`; `StreamThunk(env, exchange, err) -> u8`
returns an `HttpError` status (the exchange handle is borrowed). `env` is the retained
closure; the server releases it on drop. Behavior: one handler runs at a
time; closing
a server (or its network) from its own handler faults.

Client behavior follows Go's `net/http` (redirect policy, header order, cookie jar,
gzip, idle pool, error texts); see `src/http/client.rs` tests for recorded cases.

## websocket

```text
msrt_net_network_web_socket(net, address, headers, subprotocols, opts: *const WebSocketOptionsWire, out, err) -> u8
msrt_http_exchange_upgrade(x, origins, subprotocols, has_max, max, out, err) -> u8
msrt_websocket_{send,send_bytes,ping,ping_bytes,close,subprotocol}
msrt_websocket_receive(s, data: *mut VecVal, text: *mut u8, present: *mut u8, err) -> u8
```

A server socket lives until its handler returns, at which point it is closed with
code 1000. `receive` returns `present = 0` after a clean close.

## Concurrency and fault isolation

Servers use the `ms-rt` cooperative tasks (ABI §7). The first server on the thread
spawns a reactor task (epoll over listeners and connections, timeouts). Ready requests
run inline on it; a handler that is about to park (`wait_fd`, `sleep`, a client call, a
slow `read`) first hands the reactor role to a fresh task, so blocked handlers overlap
and a handler that never blocks costs no task switch. Switches happen only when a task
parks. Every blocking wait in the crate parks the running task (`wait::use_tasks` only
makes unit tests on a thread without a server poll instead). Each handler thunk runs under
`msrt_guard_call` (`code` is `extern "C-unwind"`): a fault inside becomes a 500
(`Outcome::Fault`), a stop request a 504 (`Outcome::Cancelled`), and the server keeps
running. Values owned by the abandoned frames leak, per the guard contract.

Every park can interleave other tasks calling into the same objects, so a native never
holds a `RefCell` borrow (or any guard on shared state) across a wait. Shared scratch
buffers are taken out of a `Cell` for the read and put back after; an object whose read
parks on its own state (`ResponseBody.read`) takes the state out of its cell and hands it
back on ordinary exit, and a second reader gets `IoErr::Failed("... another task")`.
A runtime cleanup action closes a response body and abandons its connection or stream when
cancellation or a fault skips the read's Rust destructor; subsequent reads return `Closed`.
Tasks sharing one descriptor hit the runtime's single-waiter fault (ms-rt ABI §7), so a shared
HTTP/2 session has one driver at a time: the task parked in the socket read or write.
The others park on a token until it has filed events, and a task with only new output
writes it without waiting and leaves any rest to the driver.

`Network.close()` or `HttpServer.close()` from a handler of the same network/server faults
(it would wait for itself); from any other task it waits for in-flight requests within the
grace period.
