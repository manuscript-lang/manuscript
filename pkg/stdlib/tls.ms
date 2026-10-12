# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import Timestamp from "@std/time.ms"

export type TlsError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case AuthenticationFailed

export type CertificateInfo:
    subject: String
    issuer: String
    dns_names: List[String]
    not_before: Timestamp
    not_after: Timestamp
    der: Bytes

export type TlsInfo:
    version: Int
    cipher_suite: Int
    alpn: String
    peer_certificates: List[Bytes]
    verified: Bool

export type TlsOptions:
    server_name: String
    roots_pem: String
    certificate_pem: String
    private_key_pem: String
    alpn: List[String]
    require_client_certificate: Bool

export fn parse_certificates(pem: String, max_certificates: Optional[Int] = none) -> Result[List[CertificateInfo], TlsError]

export fn verify_certificates(chain_pem: String, roots_pem: String, server_name: String, now: Timestamp) -> Result[Unit, TlsError]

impl Error for TlsError:
    fn message() -> String
