+++
title = "tls"
+++

# @std/tls.ms

Import each required symbol with `import Name from "@std/tls.ms"`.

## CertificateInfo {data-api-kind="Record"}

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

```manuscript
type TlsInfo:
    version: Int
    cipher_suite: Int
    alpn: String
    peer_certificates: List[Bytes]
    verified: Bool
```

## TlsOptions {data-api-kind="Record"}

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

```manuscript
fn parse_certificates(pem: String, max_certificates: Optional[Int] = none) -> Result[List[CertificateInfo], TlsError]:
```

## verify_certificates {data-api-kind="Function"}

```manuscript
fn verify_certificates(chain_pem: String, roots_pem: String, server_name: String, now: Timestamp) -> Result[Unit, TlsError]:
```

