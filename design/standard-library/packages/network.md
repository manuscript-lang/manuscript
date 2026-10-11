+++
title = "Networking, DNS, and TLS"
weight = 55
+++

# Networking, DNS, and TLS

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/net.ms`

```text
fn contains_ip(cidr: String, address: String) -> Result[Bool, LibraryError]
fn parse_cidr(text: String) -> Result[String, LibraryError]
fn parse_ip(text: String) -> Result[String, LibraryError]
```

## `@std/tls.ms`

```text
fn parse_certificates(pem: String, max_certificates: Int) -> Result[List[CertificateInfo], LibraryError]
fn verify_certificates(chain_pem: String, roots_pem: String, server_name: String, now: Timestamp) -> Result[Unit, LibraryError]
```

## Connection operations

```text
fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
fn write(data: Bytes) -> Result[Unit, IoError]
fn shutdown_write() -> Result[Unit, LibraryError]
fn local_address() -> String
fn peer_address() -> String
fn close() -> Unit
fn read_timeout(max_bytes: Int, timeout: Duration) -> Result[Optional[Bytes], IoError]
fn write_timeout(data: Bytes, timeout: Duration) -> Result[Unit, IoError]
fn tls_info() -> Result[TlsInfo, LibraryError]
```

## Listener operations

```text
fn accept() -> Result[Connection&Shareable, LibraryError]
fn address() -> String
fn close() -> Unit
fn accept_timeout(timeout: Duration) -> Result[Connection&Shareable, LibraryError]
```

## DatagramSocket operations

```text
fn send(data: Bytes, address: String) -> Result[Unit, LibraryError]
fn receive(max_bytes: Int) -> Result[Datagram, LibraryError]
fn address() -> String
fn close() -> Unit
fn receive_timeout(max_bytes: Int, timeout: Duration) -> Result[Datagram, LibraryError]
fn send_timeout(data: Bytes, address: String, timeout: Duration) -> Result[Unit, LibraryError]
```

## Authority and restrictions

`process.network: Network & Shareable` remains the authority root, imported from `@std/http.ms`. Acquired Connection, Listener and DatagramSocket views are individually imported from `@std/net.ms`, closed with `with`, and also owned by Network. Network.close stops admission, cancels and joins in-flight DNS/dials/HTTP acquisition, closes owned services and handles, and waits for admitted I/O. Concurrent close callers join the same shutdown. Imports never manufacture native network authority.

`restrict` returns a child Network that cannot widen its parent's policy. Hosts are exact case-insensitive DNS names (with trailing dot ignored); CIDRs authorize numeric addresses. DNS-name dialing requires the name to be allowed. If CIDRs are supplied, every chosen resolved destination must also belong to those CIDRs; raw IP dialing never bypasses a host-only restriction. Empty hosts/CIDRs deny all outbound destinations. `allow_listen` permits binding explicitly allowed numeric addresses; inbound listener peers are not an additional outbound grant. Restricted roots reject Unix socket acquisitions. Redirect hops retain the same policy. Restrictions are enforced on actual resolved addresses at dial time, not by URL string prefixes.

`with_resolver` provisions a child with an explicit numeric DNS server address. The parent policy must authorize that server. Resolver configuration is scoped to the child; it does not mutate process-wide DNS. Lookup/resolve and UDP destination resolution use cancellable native resolver calls. Parent shutdown closes child capabilities. An unrestricted CLI root retains ordinary OS network authority; restrictions are explicit opt-in narrowing.

## Records

```text
type Datagram:
    data: Bytes
    sender: String

type DnsRecord:
    kind: String
    value: String
    priority: Int
    weight: Int
    port: Int

type TlsOptions:
    server_name: String
    roots_pem: String
    certificate_pem: String
    private_key_pem: String
    alpn: List[String]
    require_client_certificate: Bool

type CertificateInfo:
    subject: String
    issuer: String
    dns_names: List[String]
    not_before: Timestamp
    not_after: Timestamp
    der: Bytes

type TlsInfo:
    version: Int
    cipher_suite: Int
    alpn: String
    peer_certificates: List[Bytes]
    verified: Bool
```

Resolve accepts A, AAAA, CNAME, MX, NS, TXT, PTR and SRV. PTR takes a numeric address; SRV takes the full service name. CNAME returns the native canonical-name result. MX fills priority; SRV fills priority/weight/port; other numeric fields are zero. TXT joins the native record's fragments. Results exceed neither max_records nor a successful truncated subset. TXT/domain text that is not valid UTF-8 returns InvalidData rather than constructing an invalid String. The native resolver does not expose TTL; the API does not invent TTL values. Parse_ip/parse_cidr normalize numeric addresses/prefixes, and contains_ip checks prefix membership without DNS or authority.

## Socket lifecycle and deadlines

Connect/listen addresses use native host:port notation, with port zero selecting an ephemeral local port on bind/listen. Unix methods use native Unix-domain paths. Independent read/write gates preserve duplex progress; calls in each direction serialize. Closing a handle interrupts blocking I/O and waits for admitted operations. Metadata remains readable after close. Half-close leaves reads available and supports TCP, Unix and TLS connections. Read follows the existing IoError/Optional Bytes contract: positive bounded chunks, none for EOF, and Closed for stale aliases. Writes accept all bytes or return an error after a possible external prefix.

Listener accept cancellation uses an interruptible deadline and restores it before releasing the accept gate. Cancellation and accept_timeout do not destroy the listener: it can admit another accept afterwards. A TLS listener additionally bounds each handshake; shutdown cancels admitted handshakes. Accepted handles retain Network ownership. Unix socket availability follows the target OS, not a separate deferred API.

UDP preserves message boundaries, including empty messages. Receive accepts max_bytes 1–65535 and returns LimitExceeded on an oversized consumed packet, never a truncated success. UDP name resolution responds to caller cancellation and Network/socket closure. Timeout variants take nonnegative durations: zero is an immediate deadline. Expected local timeouts return LibraryError.Timeout; Connection timeout variants retain IoError and use Failed with a timeout diagnostic. Parent cancellation always unwinds. Operation deadlines are cleared under the direction gate before the next operation starts.

## TLS and certificates

TLS supports 1.2 and newer with native authenticated ciphers. connect_tls uses system trust plus a required server_name; connect_tls_config accepts explicit trust PEM, client certificate/key, and ALPN. listen_tls uses a server certificate/key and can require verified client certificates. Empty roots select system trust for clients; supplied roots replace that client trust store. There is no insecure-skip-verification switch or retry. Configured names are checked against certificates; chain validation and expiration remain enabled. ALPN values must be nonempty protocol tokens of at most 255 bytes.

HTTP/WebSocket clients validate each URL hostname; the generic client TLS server_name field does not override subsequent origins. Private-key PEM is explicit input, not an imported ambient secret. Parse_certificates validates PEM/DER syntax with a certificate count bound and exposes metadata. Verify_certificates takes an explicit PEM chain, trust roots, a nonempty name and Timestamp for pure deterministic chain/hostname/expiry validation. Tls_info exposes negotiated version/cipher/ALPN and peer DER certificates, without exposing private keys.

HTTP/3 is intentionally excluded at the user's request. The HTTP/1.1, HTTP/2 and WebSocket contracts are in their own pages.

## Network operations

```text
fn lookup(name: String, max_records: Int, timeout: Duration) -> Result[List[String], LibraryError]
fn connect(address: String, timeout: Duration) -> Result[Connection&Shareable, LibraryError]
fn connect_tls(address: String, server_name: String, timeout: Duration) -> Result[Connection&Shareable, LibraryError]
fn listen(address: String) -> Result[Listener&Shareable, LibraryError]
fn bind_datagram(address: String) -> Result[DatagramSocket&Shareable, LibraryError]
fn restrict(hosts: List[String], cidrs: List[String], allow_listen: Bool) -> Result[Network&Shareable, LibraryError]
fn with_resolver(address: String) -> Result[Network&Shareable, LibraryError]
fn resolve(name: String, kind: String, max_records: Int, timeout: Duration) -> Result[List[DnsRecord], LibraryError]
fn connect_unix(path: String, timeout: Duration) -> Result[Connection&Shareable, LibraryError]
fn listen_unix(path: String) -> Result[Listener&Shareable, LibraryError]
fn connect_tls_config(address: String, options: TlsOptions, timeout: Duration) -> Result[Connection&Shareable, LibraryError]
fn listen_tls(address: String, options: TlsOptions, handshake_timeout: Duration) -> Result[Listener&Shareable, LibraryError]
```
