+++
title = "Sockets and TLS"
weight = 15
+++

# Sockets and TLS

API reference: [net](reference/net.md), [tls](reference/tls.md).

Use an explicit Network service to resolve names and open sockets. Connections, listeners, and datagram sockets must close when their work ends. The sections below explain destination restrictions, cancellation, and verified TLS.

## Authority and restrictions

Import `network() -> Network` from `@std/net.ms` to obtain the current execution's network service. Acquired Connection, Listener and DatagramSocket views are individually imported from `@std/net.ms`, closed with `with`, and also owned by Network. Network.close stops admission, cancels and joins in-flight DNS/dials/HTTP acquisition, closes owned services and handles, and waits for admitted I/O. Concurrent close callers join the same shutdown. Repeated accessor calls return the same host root.

### Narrowing destination access

Use `restrict` to create a child Network with narrower access. The child cannot grant access its parent denied. Host entries are exact DNS names, compared without case and ignoring a trailing dot. CIDR entries authorize numeric address ranges. DNS-name dialing requires the name to be allowed. If CIDRs are supplied, every chosen resolved destination must also belong to those CIDRs; raw IP dialing never bypasses a host-only restriction. Empty hosts/CIDRs deny all outbound destinations.

`allow_listen` permits binding explicitly allowed numeric addresses; inbound listener peers are not an additional outbound grant. Restricted roots reject Unix socket acquisitions. Redirect hops retain the same policy. Restrictions are enforced on actual resolved addresses at dial time, not by URL string prefixes.

### Choosing a resolver

`with_resolver` provisions a child with an explicit numeric DNS server address. The parent policy must authorize that server. Resolver configuration is scoped to the child; it does not mutate process-wide DNS. Lookup/resolve and UDP destination resolution use cancellable native resolver calls. Parent shutdown closes child capabilities. An unrestricted CLI root retains ordinary OS network authority; restrictions are explicit opt-in narrowing.

## DNS results

`resolve(kind:)` accepts `A`, `AAAA`, `CNAME`, `MX`, `NS`, `TXT`, `PTR` and `SRV` case-insensitively; other strings return `NetworkError.InvalidInput`. Returned DnsRecord.kind uses the uppercase spelling. PTR takes a numeric address; SRV takes the full service name. CNAME returns the native canonical-name result. MX fills priority; SRV fills priority/weight/port; other numeric fields are zero. TXT joins the native record's fragments. If results exceed `max_records`, the call returns an error rather than a truncated successful list. TXT/domain text that is not valid UTF-8 returns InvalidData rather than constructing an invalid String. The native resolver does not expose TTL; the API does not invent TTL values. Parse_ip/parse_cidr normalize numeric addresses/prefixes, and contains_ip checks prefix membership without DNS or authority.

## Socket lifecycle and deadlines

Connect/listen addresses use native host:port notation, with IPv6 hosts in brackets (for example `[::1]:8080`) and port zero selecting an ephemeral local port on bind/listen. Datagram.sender and connection address accessors return native address text in the same notation. `parse_ip` returns canonical numeric IPv4/IPv6 text without a port; this differs from a URL's parsed Optional[Int] port. Unix methods use native Unix-domain paths. Read and write use separate synchronization gates, allowing one of each to progress together. Calls in the same direction are serialized. Closing a handle interrupts blocking I/O and waits for admitted operations. Metadata remains readable after close. A half-close ends writing while leaving reads available. It is supported for TCP, Unix, and TLS connections. Read follows the existing IoError/Optional Bytes contract: positive bounded chunks, none for EOF, and Closed for stale aliases. Writes accept all bytes or return an error after a possible external prefix.

### Accept and handshake cancellation

Listener accept cancellation uses an interruptible deadline and restores it before releasing the accept gate. Cancellation and accept do not destroy the listener: it can admit another accept afterwards. A TLS listener applies its optional handshake deadline; shutdown cancels admitted handshakes. Accepted handles retain Network ownership. Unix socket availability follows the target OS, not a separate deferred API.

### Datagrams and operation timeouts

UDP preserves message boundaries, including empty messages. Receive accepts max_bytes 1–65535 and returns LimitExceeded on an oversized consumed packet, never a truncated success. UDP name resolution responds to caller cancellation and Network/socket closure. The ordinary operations accept optional nonnegative timeouts: zero is an immediate deadline, and omission adds no deadline. Expected local timeouts return NetworkError.Timeout; Connection operations retain IoError and use Failed with a timeout diagnostic. Parent cancellation always unwinds. Operation deadlines are cleared under the direction gate before the next operation starts.

## TLS and certificates

TLS supports 1.2 and newer with native authenticated ciphers. connect_tls uses system trust plus a required server_name; connect_tls_config accepts explicit trust PEM, client certificate/key, and ALPN. listen_tls uses a server certificate/key and can require verified client certificates. Empty roots select system trust for clients; supplied roots replace that client trust store. There is no insecure-skip-verification switch or retry. Configured names are checked against certificates; chain validation and expiration remain enabled. ALPN values must be nonempty protocol tokens of at most 255 bytes.

### Hostnames and certificate helpers

HTTP/WebSocket clients validate each URL hostname; the generic client TLS server_name field does not override subsequent origins. Private-key PEM is explicit input, not an imported ambient secret. Parse_certificates validates PEM/DER syntax with a certificate count bound and exposes metadata. Verify_certificates takes an explicit PEM chain, trust roots, a nonempty name and Timestamp for pure deterministic chain/hostname/expiry validation. Tls_info exposes negotiated version/cipher/ALPN and peer DER certificates, without exposing private keys.

See [HTTP](http.md) for HTTP/1.1 and HTTP/2, and [WebSockets](websocket.md) for message sessions.
