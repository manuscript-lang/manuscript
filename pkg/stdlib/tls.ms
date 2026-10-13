# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import Timestamp from "@std/time.ms"

# Errors returned when TLS configuration, certificates, or peer authentication fail.
export type TlsError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case AuthenticationFailed

# Parsed certificate identity, validity range, and original DER bytes.
export type CertificateInfo:
    subject: String
    issuer: String
    dns_names: List[String]
    not_before: Timestamp
    not_after: Timestamp
    der: Bytes

# Negotiated TLS version, cipher, protocol, and peer certificate information.
export type TlsInfo:
    version: Int
    cipher_suite: Int
    alpn: String
    peer_certificates: List[Bytes]
    verified: Bool

# Client or server TLS settings, including roots, certificates, and ALPN protocols.
export type TlsOptions:
    server_name: String
    roots_pem: String
    certificate_pem: String
    private_key_pem: String
    alpn: List[String]
    require_client_certificate: Bool

# Parses PEM certificates and optionally limits the number returned.
export fn parse_certificates(
    pem: String,
    max_certificates: Optional[Int] = none
) -> Result[List[CertificateInfo], TlsError]:

# Verifies a PEM certificate chain against roots, name constraints, and the supplied time.
export fn verify_certificates(
    chain_pem: String,
    roots_pem: String,
    server_name: String,
    now: Timestamp
) -> Result[Unit, TlsError]:

impl Error for TlsError:
    fn message() -> String:
