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

