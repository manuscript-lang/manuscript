+++
title = "tls"
+++

# @std/tls.ms

Import each required symbol with `import Name from "@std/tls.ms"`.

## CertificateInfo {data-api-kind="Record"}

```manuscript
CertificateInfo: CertificateInfo
field subject: String
field issuer: String
field dns_names: List[String]
field not_before: Timestamp
field not_after: Timestamp
field der: Bytes
```

## TlsInfo {data-api-kind="Record"}

```manuscript
TlsInfo: TlsInfo
field version: Int
field cipher_suite: Int
field alpn: String
field peer_certificates: List[Bytes]
field verified: Bool
```

## TlsOptions {data-api-kind="Record"}

```manuscript
TlsOptions: TlsOptions
field server_name: String
field roots_pem: String
field certificate_pem: String
field private_key_pem: String
field alpn: List[String]
field require_client_certificate: Bool
```

## parse_certificates {data-api-kind="Function"}

```manuscript
parse_certificates: fn(pem: String, max_certificates: Int)->Result[List[CertificateInfo], LibraryError]
```

## verify_certificates {data-api-kind="Function"}

```manuscript
verify_certificates: fn(chain_pem: String, roots_pem: String, server_name: String, now: Timestamp)->Result[Unit, LibraryError]
```

