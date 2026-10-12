+++
title = "tls"
+++

# @std/tls.ms

Import each required symbol with `import Name from "@std/tls.ms"`.

## CertificateInfo

Kind: record.

```text
CertificateInfo: CertificateInfo
field subject: String
field issuer: String
field dns_names: List[String]
field not_before: Timestamp
field not_after: Timestamp
field der: Bytes
```

## TlsError

Kind: alternative.

```text
TlsError: TlsError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
case AuthenticationFailed
operation message: fn()->String
```

## TlsInfo

Kind: record.

```text
TlsInfo: TlsInfo
field version: Int
field cipher_suite: Int
field alpn: String
field peer_certificates: List[Bytes]
field verified: Bool
```

## TlsOptions

Kind: record.

```text
TlsOptions: TlsOptions
field server_name: String
field roots_pem: String
field certificate_pem: String
field private_key_pem: String
field alpn: List[String]
field require_client_certificate: Bool
```

## parse_certificates

Kind: fn.

```text
parse_certificates: fn(pem: String, max_certificates: Int)->Result[List[CertificateInfo], TlsError]
```

## verify_certificates

Kind: fn.

```text
verify_certificates: fn(chain_pem: String, roots_pem: String, server_name: String, now: Timestamp)->Result[Unit, TlsError]
```

