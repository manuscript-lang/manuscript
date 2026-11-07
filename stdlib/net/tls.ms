import Bytes from "@std/bytes.ms"
import Timestamp from "@std/time.ms"
import (
    msstd_tls_parse_certificates,
    msstd_tls_verify_certificates
) from "@std/internal/net.ms"

// Parsed certificate identity, validity range, and original DER bytes.
export type CertificateInfo:
    // The certificate subject as a distinguished-name string, such as `CN=example.com,O=Example`.
    subject: String
    // The issuing authority as a distinguished-name string, in the same format as `subject`.
    issuer: String
    // DNS subject alternative names in certificate order; empty when the certificate has none.
    dns_names: List[String]
    // Start of the validity period as a UTC Timestamp.
    not_before: Timestamp
    // End of the validity period as a UTC Timestamp.
    not_after: Timestamp
    // The certificate's binary DER encoding, as a copy independent of the PEM text.
    der: Bytes

// Negotiated TLS version, cipher, protocol, and peer certificate information.
export type TlsInfo:
    // Negotiated protocol version as its numeric wire code, such as 771 (0x0303) for TLS 1.2 or 772 (0x0304) for TLS 1.3.
    version: Int
    // Negotiated cipher suite as its numeric IANA identifier, such as 4865 (0x1301) for TLS_AES_128_GCM_SHA256.
    cipher_suite: Int
    // The application protocol both sides agreed on, or an empty string when none was negotiated.
    alpn: String
    // The peer's presented certificates as DER bytes, leaf first; empty when the peer sent none.
    peer_certificates: List[Bytes]
    // True when the peer's certificate chain was verified against the configured roots; False when no peer chain was verified.
    verified: Bool

// Client or server TLS settings, including roots, certificates, and ALPN protocols.
export type TlsOptions:
    // Host name a TLS client sends for server name indication and matches against the server certificate; it must be non-empty for `connect_tls_config`.
    // HTTP and WebSocket clients take the name from the URL host and ignore this field, and servers do not use it.
    server_name: String = ""
    // PEM certificates to trust. Clients use them instead of the system roots; servers use them to verify client certificates. An empty string selects the system roots; invalid PEM is rejected.
    roots_pem: String = ""
    // PEM certificate chain this side presents, paired with `private_key_pem`. Servers must supply it; clients supply it only for mutual TLS.
    certificate_pem: String = ""
    // PEM private key matching `certificate_pem`. Both must be set together and match, or setup fails.
    private_key_pem: String = ""
    // Application-layer protocols to offer or accept, in preference order, such as `h2` or `http/1.1`. Each must be 1 through 255 bytes; empty disables negotiation.
    alpn: List[String] = []
    // Servers only: when True, a client must present a certificate that verifies against `roots_pem`. Setting it on a client configuration is rejected.
    require_client_certificate: Bool = false

// Parses PEM certificates and optionally limits the number returned.
export fn parse_certificates(pem: String, max_certificates: Int?) List[CertificateInfo]!:
    return msstd_tls_parse_certificates(pem, max_certificates)

// Verifies a PEM certificate chain against roots, name constraints, and the supplied time. An empty `roots_pem` reads the system roots.
// ms: effect std.system.read
export fn verify_certificates(
    chain_pem: String,
    roots_pem: String,
    server_name: String,
    now: Timestamp
) Unit!:
    return msstd_tls_verify_certificates(chain_pem, roots_pem, server_name, now)
