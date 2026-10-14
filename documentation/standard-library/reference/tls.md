+++
title = "tls"
+++

# @std/tls.ms

Import each required symbol with `import Name from "@std/tls.ms"`.

## CertificateInfo {data-api-kind="Record"}

Parsed certificate identity, validity range, and original DER bytes.

```manuscript
type CertificateInfo:
    subject: String
    issuer: String
    dns_names: List[String]
    not_before: Timestamp
    not_after: Timestamp
    der: Bytes
```

### CertificateInfo.der

The certificate's binary DER encoding, as a copy independent of the PEM text.

```manuscript
der: Bytes
```

### CertificateInfo.dns_names

DNS subject alternative names in certificate order; empty when the certificate has none.

```manuscript
dns_names: List[String]
```

### CertificateInfo.issuer

The issuing authority as a distinguished-name string, in the same format as `subject`.

```manuscript
issuer: String
```

### CertificateInfo.not_after

End of the validity period as a UTC Timestamp.

```manuscript
not_after: Timestamp
```

### CertificateInfo.not_before

Start of the validity period as a UTC Timestamp.

```manuscript
not_before: Timestamp
```

### CertificateInfo.subject

The certificate subject as a distinguished-name string, such as `CN=example.com,O=Example`.

```manuscript
subject: String
```

## TlsError {data-api-kind="Alternative"}

Errors returned when TLS configuration, certificates, or peer authentication fail.

```manuscript
type TlsError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case AuthenticationFailed
```

```manuscript
impl Error for TlsError:
    fn message() -> String:
```

### TlsError.AuthenticationFailed

Chain verification failed: the chain does not lead to a supplied root, a certificate is expired or not yet valid at the supplied time, or the name does not match.

```manuscript
case AuthenticationFailed
```

### TlsError.InvalidData

The PEM text is not a sequence of well-formed CERTIFICATE blocks, or a chain or roots argument holds no certificate.

```manuscript
case InvalidData
```

### TlsError.InvalidInput

A certificate limit is negative, a `server_name` is empty, or `tls_info` was requested on a connection that is not TLS.

```manuscript
case InvalidInput
```

### TlsError.LimitExceeded

The PEM text holds more certificates than `max_certificates`.

```manuscript
case LimitExceeded
```

### TlsError.Error.message

Returns the fixed diagnostic `TLS: <reason>`, such as `TLS: authentication failed`, without echoing certificate text.

```manuscript
fn message() -> String:
```

## TlsInfo {data-api-kind="Record"}

Negotiated TLS version, cipher, protocol, and peer certificate information.

```manuscript
type TlsInfo:
    version: Int
    cipher_suite: Int
    alpn: String
    peer_certificates: List[Bytes]
    verified: Bool
```

### TlsInfo.alpn

The application protocol both sides agreed on, or an empty string when none was negotiated.

```manuscript
alpn: String
```

### TlsInfo.cipher_suite

Negotiated cipher suite as its numeric IANA identifier, such as 4865 (0x1301) for TLS_AES_128_GCM_SHA256.

```manuscript
cipher_suite: Int
```

### TlsInfo.peer_certificates

The peer's presented certificates as DER bytes, leaf first; empty when the peer sent none.

```manuscript
peer_certificates: List[Bytes]
```

### TlsInfo.verified

True when the peer's certificate chain was verified against the configured roots; false when no peer chain was verified.

```manuscript
verified: Bool
```

### TlsInfo.version

Negotiated protocol version as its numeric wire code, such as 771 (0x0303) for TLS 1.2 or 772 (0x0304) for TLS 1.3.

```manuscript
version: Int
```

## TlsOptions {data-api-kind="Record"}

Client or server TLS settings, including roots, certificates, and ALPN protocols.

```manuscript
type TlsOptions:
    server_name: String
    roots_pem: String
    certificate_pem: String
    private_key_pem: String
    alpn: List[String]
    require_client_certificate: Bool
```

### TlsOptions.alpn

Application-layer protocols to offer or accept, in preference order, such as `h2` or `http/1.1`. Each must be 1 through 255 bytes; empty disables negotiation.

```manuscript
alpn: List[String]
```

### TlsOptions.certificate_pem

PEM certificate chain this side presents, paired with `private_key_pem`. Servers must supply it; clients supply it only for mutual TLS.

```manuscript
certificate_pem: String
```

### TlsOptions.private_key_pem

PEM private key matching `certificate_pem`. Both must be set together and match, or setup fails.

```manuscript
private_key_pem: String
```

### TlsOptions.require_client_certificate

Servers only: when true, a client must present a certificate that verifies against `roots_pem`. Setting it on a client configuration is rejected.

```manuscript
require_client_certificate: Bool
```

### TlsOptions.roots_pem

PEM certificates to trust. Clients use them instead of the system roots; servers use them to verify client certificates. An empty string selects the system roots; invalid PEM is rejected.

```manuscript
roots_pem: String
```

### TlsOptions.server_name

Host name a TLS client sends for server name indication and matches against the server certificate; it must be non-empty for `connect_tls_config`.
HTTP and WebSocket clients take the name from the URL host and ignore this field, and servers do not use it.

```manuscript
server_name: String
```

## parse_certificates {data-api-kind="Function"}

Parses PEM certificates and optionally limits the number returned.

```manuscript
fn parse_certificates(pem: String, max_certificates: Optional[Int] = none) -> Result[List[CertificateInfo], TlsError]:
```

## verify_certificates {data-api-kind="Function"}

Verifies a PEM certificate chain against roots, name constraints, and the supplied time.

```manuscript
fn verify_certificates(chain_pem: String, roots_pem: String, server_name: String, now: Timestamp) -> Result[Unit, TlsError]:
```

