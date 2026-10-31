//! TLS over rustls.
//!
//! Chain building, name matching and PEM parsing follow `crypto/x509` semantics
//! so that the same inputs are accepted and rejected. Roots always come from
//! the supplied PEM, or from the system store when none is supplied.

use crate::conn::{Io, OwnedSock, Step, TlsDetails};
use crate::error::{NetErr, TlsErr, describe_io_error};
use crate::sys::{AsSock, Borrowed};
use crate::wait::{Deadline, Interest, Wait, wait_fd};
use base64::Engine as _;
use base64::alphabet::STANDARD;
use base64::engine::DecodePaddingMode;
use base64::engine::general_purpose::{GeneralPurpose, GeneralPurposeConfig};
use ms_rt::fault::with_cleanup;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerifier};
use rustls::crypto::{CryptoProvider, WebPkiSupportedAlgorithms, ring};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime};
use rustls::server::danger::{ClientCertVerified, ClientCertVerifier};
use rustls::sign::CertifiedKey;
use rustls::{
    ClientConfig, DigitallySignedStruct, DistinguishedName, ServerConfig, SignatureScheme,
};
use std::cell::RefCell;
use std::io::{self, Read, Write};
use std::sync::{Arc, OnceLock};
use x509_parser::prelude::*;

// ------------------------------------------------------------------------ PEM

const LENIENT: GeneralPurpose = GeneralPurpose::new(
    &STANDARD,
    GeneralPurposeConfig::new()
        .with_decode_allow_trailing_bits(true)
        .with_decode_padding_mode(DecodePaddingMode::RequireCanonical),
);

/// Decodes one block at the start of `text` as PEM requires,
/// returning its label, bytes and the remaining text. Blocks with headers are
/// rejected by returning `None` for the whole decode.
fn decode_block(text: &str, skip_junk: bool) -> Option<(String, Vec<u8>, &str)> {
    let begin = "-----BEGIN ";
    let at = if skip_junk {
        text.match_indices(begin)
            .find(|(i, _)| *i == 0 || text.as_bytes()[i - 1] == b'\n')?
            .0
    } else if text.starts_with(begin) {
        0
    } else {
        return None;
    };
    let rest = &text[at + begin.len()..];
    let (label_line, mut rest) = rest.split_once('\n').map_or((rest, ""), |(a, b)| (a, b));
    let label = label_line.trim_end().strip_suffix("-----")?.to_string();
    let end = format!("-----END {label}-----");
    let mut body = String::new();
    loop {
        let (line, after) = match rest.split_once('\n') {
            Some((a, b)) => (a, b),
            None if rest.is_empty() => return None,
            None => (rest, ""),
        };
        let trimmed = line.trim();
        if trimmed == end {
            let bytes = LENIENT.decode(body.as_bytes()).ok()?;
            return Some((label, bytes, after));
        }
        if trimmed.contains(':') {
            // A header: not a plain certificate block.
            return None;
        }
        body.extend(trimmed.chars().filter(|c| !c.is_whitespace()));
        rest = after;
    }
}

/// Parses text made only of CERTIFICATE blocks separated by whitespace.
pub fn strict_certificates(text: &str) -> Result<Vec<Vec<u8>>, TlsErr> {
    let mut out = Vec::new();
    let mut rest = text;
    loop {
        rest = rest.trim();
        if rest.is_empty() {
            return Ok(out);
        }
        if !rest.starts_with("-----BEGIN CERTIFICATE-----") {
            return Err(TlsErr::InvalidData);
        }
        match decode_block(rest, false) {
            Some((label, der, after)) if label == "CERTIFICATE" => {
                out.push(der);
                rest = after;
            }
            _ => return Err(TlsErr::InvalidData),
        }
    }
}

/// Collects the blocks of `text` with the given label, skipping other text.
fn blocks_labeled(text: &str, wanted: impl Fn(&str) -> bool) -> Vec<Vec<u8>> {
    let mut out = Vec::new();
    let mut rest = text;
    while let Some((label, der, after)) = decode_block(rest, true) {
        if wanted(&label) {
            out.push(der);
        }
        rest = after;
    }
    out
}

// -------------------------------------------------------------------- Options

/// Explicit TLS settings (`TlsOptions` of `@std/net.ms`).
#[derive(Clone, Debug, Default)]
pub struct TlsOptions {
    pub server_name: String,
    pub roots_pem: String,
    pub certificate_pem: String,
    pub private_key_pem: String,
    pub alpn: Vec<String>,
    pub require_client_certificate: bool,
}

fn provider() -> Arc<CryptoProvider> {
    static P: OnceLock<Arc<CryptoProvider>> = OnceLock::new();
    P.get_or_init(|| Arc::new(ring::default_provider())).clone()
}

fn system_roots() -> &'static Vec<Vec<u8>> {
    static R: OnceLock<Vec<Vec<u8>>> = OnceLock::new();
    R.get_or_init(|| {
        rustls_native_certs::load_native_certs()
            .certs
            .into_iter()
            .map(|c| c.as_ref().to_vec())
            .collect()
    })
}

fn load_identity(o: &TlsOptions) -> Result<Option<Arc<CertifiedKey>>, ()> {
    if o.certificate_pem.is_empty() && o.private_key_pem.is_empty() {
        return Ok(None);
    }
    let certs: Vec<CertificateDer<'static>> =
        blocks_labeled(&o.certificate_pem, |l| l == "CERTIFICATE")
            .into_iter()
            .map(CertificateDer::from)
            .collect();
    if certs.is_empty() {
        return Err(());
    }
    let key = blocks_labeled_keys(&o.private_key_pem).ok_or(())?;
    let signing = provider()
        .key_provider
        .load_private_key(key)
        .map_err(|_| ())?;
    let certified = CertifiedKey::new(certs, signing);
    certified.keys_match().map_err(|_| ())?;
    Ok(Some(Arc::new(certified)))
}

fn blocks_labeled_keys(text: &str) -> Option<PrivateKeyDer<'static>> {
    let mut rest = text;
    while let Some((label, der, after)) = decode_block(rest, true) {
        match label.as_str() {
            "PRIVATE KEY" => return Some(PrivateKeyDer::Pkcs8(der.into())),
            "RSA PRIVATE KEY" => return Some(PrivateKeyDer::Pkcs1(der.into())),
            "EC PRIVATE KEY" => return Some(PrivateKeyDer::Sec1(der.into())),
            _ => rest = after,
        }
    }
    None
}

fn roots_for(o: &TlsOptions) -> Result<Roots, ()> {
    if o.roots_pem.is_empty() {
        return Ok(Roots::System);
    }
    let certs = strict_certificates(&o.roots_pem).map_err(|_| ())?;
    if certs.is_empty() {
        return Err(());
    }
    Ok(Roots::Custom(Arc::new(certs)))
}

fn alpn_ok(alpn: &[String]) -> bool {
    alpn.iter().all(|p| !p.is_empty() && p.len() <= 255)
}

/// Client configuration for `o`; `named` requires a server name (a direct
/// connection) while HTTP and WebSocket validate per request.
pub fn client_config(o: &TlsOptions, named: bool) -> Result<Arc<ClientConfig>, NetErr> {
    if !alpn_ok(&o.alpn) || (named && o.server_name.is_empty()) || o.require_client_certificate {
        return Err(NetErr::InvalidInput);
    }
    let roots = roots_for(o).map_err(|_| NetErr::InvalidInput)?;
    let identity = load_identity(o).map_err(|_| NetErr::InvalidInput)?;
    let builder = ClientConfig::builder_with_provider(provider())
        .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
        .map_err(|_| NetErr::InvalidInput)?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(GoVerifier {
            roots,
            algs: provider().signature_verification_algorithms,
        }));
    let mut config = match identity {
        Some(id) => builder.with_client_cert_resolver(Arc::new(FixedIdentity(id))),
        None => builder.with_no_client_auth(),
    };
    config.alpn_protocols = o.alpn.iter().map(|p| p.as_bytes().to_vec()).collect();
    Ok(Arc::new(config))
}

/// Server configuration for `o`; a certificate and key are required.
pub fn server_config(o: &TlsOptions) -> Result<Arc<ServerConfig>, NetErr> {
    if !alpn_ok(&o.alpn) {
        return Err(NetErr::InvalidInput);
    }
    let identity = load_identity(o)
        .map_err(|_| NetErr::InvalidInput)?
        .ok_or(NetErr::InvalidInput)?;
    let versions = ServerConfig::builder_with_provider(provider())
        .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
        .map_err(|_| NetErr::InvalidInput)?;
    let builder = if o.roots_pem.is_empty() && !o.require_client_certificate {
        versions.with_no_client_auth()
    } else {
        let roots = roots_for(o).map_err(|_| NetErr::InvalidInput)?;
        versions.with_client_cert_verifier(Arc::new(GoClientVerifier {
            inner: GoVerifier {
                roots,
                algs: provider().signature_verification_algorithms,
            },
            mandatory: o.require_client_certificate,
        }))
    };
    let mut config = builder.with_cert_resolver(Arc::new(FixedServerIdentity(identity)));
    config.alpn_protocols = o.alpn.iter().map(|p| p.as_bytes().to_vec()).collect();
    Ok(Arc::new(config))
}

/// Server settings for raw TLS listeners. It sends no TLS 1.3 session tickets: the caller never
/// reads them, and a ticket reaching a peer that has already closed draws a reset that discards
/// bytes the peer wrote just before closing.
pub fn stream_server_config(o: &TlsOptions) -> Result<Arc<ServerConfig>, NetErr> {
    let mut config = server_config(o)?;
    if let Some(c) = Arc::get_mut(&mut config) {
        c.send_tls13_tickets = 0;
    }
    Ok(config)
}

#[derive(Debug)]
struct FixedIdentity(Arc<CertifiedKey>);

impl rustls::client::ResolvesClientCert for FixedIdentity {
    fn resolve(
        &self,
        _root_hint_subjects: &[&[u8]],
        _sigschemes: &[SignatureScheme],
    ) -> Option<Arc<CertifiedKey>> {
        Some(self.0.clone())
    }

    fn has_certs(&self) -> bool {
        true
    }
}

#[derive(Debug)]
struct FixedServerIdentity(Arc<CertifiedKey>);

impl rustls::server::ResolvesServerCert for FixedServerIdentity {
    fn resolve(&self, _hello: rustls::server::ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
        Some(self.0.clone())
    }
}

// ------------------------------------------------------------------- Verifying

#[derive(Clone, Debug)]
enum Roots {
    System,
    Custom(Arc<Vec<Vec<u8>>>),
}

impl Roots {
    fn certs(&self) -> &[Vec<u8>] {
        match self {
            Roots::System => system_roots(),
            Roots::Custom(c) => c,
        }
    }
}

/// Why a chain was rejected, for diagnostics.
#[derive(Debug)]
pub enum Reject {
    Parse,
    Expired,
    UnknownAuthority,
    Name(String),
    Usage,
}

impl Reject {
    fn text(&self) -> String {
        match self {
            Reject::Parse => "x509: malformed certificate".into(),
            Reject::Expired => "x509: certificate has expired or is not yet valid".into(),
            Reject::UnknownAuthority => "x509: certificate signed by unknown authority".into(),
            Reject::Name(m) => m.clone(),
            Reject::Usage => "x509: certificate specifies an incompatible key usage".into(),
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Usage {
    Server,
    Client,
}

/// Checks name against the SANs of `leaf` the way `VerifyHostname` does.
fn match_name(leaf: &X509Certificate<'_>, name: &str) -> Result<(), Reject> {
    let mut dns: Vec<String> = Vec::new();
    let mut ips: Vec<Vec<u8>> = Vec::new();
    if let Ok(Some(san)) = leaf.subject_alternative_name() {
        for g in &san.value.general_names {
            match g {
                GeneralName::DNSName(d) => dns.push((*d).to_string()),
                GeneralName::IPAddress(ip) => ips.push(ip.to_vec()),
                _ => {}
            }
        }
    }
    let host = name
        .strip_prefix('[')
        .and_then(|h| h.strip_suffix(']'))
        .unwrap_or(name);
    if let Ok(ip) = crate::ip::parse_ip(host) {
        let want: Vec<u8> = match crate::ip::normalize(ip) {
            std::net::IpAddr::V4(v) => v.octets().to_vec(),
            std::net::IpAddr::V6(v) => v.octets().to_vec(),
        };
        if ips.contains(&want) {
            return Ok(());
        }
        let shown = ips
            .iter()
            .map(|b| ip_from_bytes(b))
            .collect::<Vec<_>>()
            .join(", ");
        return Err(Reject::Name(if ips.is_empty() {
            "x509: cannot validate certificate for ".to_string()
                + host
                + " because it doesn't contain any IP SANs"
        } else {
            format!("x509: certificate is valid for {shown}, not {host}")
        }));
    }
    let candidate = host.trim_end_matches('.').to_ascii_lowercase();
    if dns.iter().any(|pattern| dns_matches(pattern, &candidate)) {
        return Ok(());
    }
    Err(Reject::Name(if dns.is_empty() {
        format!("x509: certificate is not valid for any names, but wanted to match {host}")
    } else {
        format!(
            "x509: certificate is valid for {}, not {host}",
            dns.join(", ")
        )
    }))
}

fn ip_from_bytes(b: &[u8]) -> String {
    match b.len() {
        4 => std::net::Ipv4Addr::new(b[0], b[1], b[2], b[3]).to_string(),
        16 => {
            let mut a = [0u8; 16];
            a.copy_from_slice(b);
            crate::ip::ip_text(&std::net::IpAddr::V6(std::net::Ipv6Addr::from(a)))
        }
        _ => String::new(),
    }
}

fn dns_matches(pattern: &str, host: &str) -> bool {
    let pattern = pattern.trim_end_matches('.').to_ascii_lowercase();
    if pattern.is_empty() {
        return false;
    }
    if let Some(suffix) = pattern.strip_prefix("*.") {
        // The wildcard stands for exactly one non-empty leftmost label.
        let Some((first, rest)) = host.split_once('.') else {
            return false;
        };
        return !first.is_empty() && !suffix.is_empty() && !suffix.contains('*') && rest == suffix;
    }
    pattern == host
}

fn usage_ok(cert: &X509Certificate<'_>, usage: Usage) -> bool {
    match cert.extended_key_usage() {
        Ok(Some(eku)) => {
            let v = eku.value;
            v.any
                || match usage {
                    Usage::Server => v.server_auth,
                    Usage::Client => v.client_auth,
                }
        }
        _ => true,
    }
}

fn valid_at(cert: &X509Certificate<'_>, now: i64) -> bool {
    let v = cert.validity();
    v.not_before.timestamp() <= now && now <= v.not_after.timestamp()
}

fn is_ca(cert: &X509Certificate<'_>) -> bool {
    matches!(cert.basic_constraints(), Ok(Some(bc)) if bc.value.ca)
}

/// Verifies `chain` (leaf first) against `roots` at `now` (Unix seconds).
pub fn verify_chain(
    chain: &[Vec<u8>],
    roots: &[Vec<u8>],
    name: Option<&str>,
    now: i64,
    usage: Usage,
) -> Result<(), Reject> {
    let parsed: Vec<X509Certificate<'_>> = chain
        .iter()
        .map(|d| {
            X509Certificate::from_der(d)
                .map(|(_, c)| c)
                .map_err(|_| Reject::Parse)
        })
        .collect::<Result<_, _>>()?;
    let leaf = parsed.first().ok_or(Reject::Parse)?;
    if let Some(name) = name {
        // Validity and trust are checked before the name.
        let _ = name;
    }
    let root_certs: Vec<X509Certificate<'_>> = roots
        .iter()
        .filter_map(|d| X509Certificate::from_der(d).ok().map(|(_, c)| c))
        .collect();
    let mut expired = false;
    let trusted = build(
        leaf,
        &parsed[1..],
        &root_certs,
        roots,
        chain[0].as_slice(),
        now,
        &mut expired,
        0,
        &mut Vec::new(),
    );
    if !trusted {
        return Err(if expired {
            Reject::Expired
        } else {
            Reject::UnknownAuthority
        });
    }
    if !usage_ok(leaf, usage) {
        return Err(Reject::Usage);
    }
    match name {
        Some(n) => match_name(leaf, n),
        None => Ok(()),
    }
}

#[allow(clippy::too_many_arguments)]
fn build(
    cert: &X509Certificate<'_>,
    pool: &[X509Certificate<'_>],
    roots: &[X509Certificate<'_>],
    root_ders: &[Vec<u8>],
    der: &[u8],
    now: i64,
    expired: &mut bool,
    depth: usize,
    seen: &mut Vec<Vec<u8>>,
) -> bool {
    if depth > 8 || seen.iter().any(|s| s == der) {
        return false;
    }
    if !valid_at(cert, now) {
        *expired = true;
        return false;
    }
    if root_ders.iter().any(|r| r == der) {
        return true;
    }
    seen.push(der.to_vec());
    let issuer = cert.issuer().as_raw();
    for root in roots {
        if root.subject().as_raw() == issuer
            && is_ca(root)
            && valid_at(root, now)
            && cert.verify_signature(Some(root.public_key())).is_ok()
        {
            seen.pop();
            return true;
        }
    }
    for next in pool {
        if next.subject().as_raw() == issuer
            && is_ca(next)
            && cert.verify_signature(Some(next.public_key())).is_ok()
            && build(
                next,
                pool,
                roots,
                root_ders,
                next.as_raw(),
                now,
                expired,
                depth + 1,
                seen,
            )
        {
            seen.pop();
            return true;
        }
    }
    seen.pop();
    false
}

#[derive(Debug)]
struct GoVerifier {
    roots: Roots,
    algs: WebPkiSupportedAlgorithms,
}

fn unix_secs(now: UnixTime) -> i64 {
    now.as_secs() as i64
}

fn reject(r: Reject) -> rustls::Error {
    rustls::Error::General(format!("tls: failed to verify certificate: {}", r.text()))
}

fn server_name_text(n: &ServerName<'_>) -> String {
    match n {
        ServerName::DnsName(d) => d.as_ref().to_string(),
        ServerName::IpAddress(ip) => std::net::IpAddr::from(*ip).to_string(),
        _ => String::new(),
    }
}

impl ServerCertVerifier for GoVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &ServerName<'_>,
        _ocsp: &[u8],
        now: UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        let chain: Vec<Vec<u8>> = std::iter::once(end_entity)
            .chain(intermediates)
            .map(|c| c.as_ref().to_vec())
            .collect();
        let name = server_name_text(server_name);
        verify_chain(
            &chain,
            self.roots.certs(),
            Some(&name),
            unix_secs(now),
            Usage::Server,
        )
        .map_err(reject)?;
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(message, cert, dss, &self.algs)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(message, cert, dss, &self.algs)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algs.supported_schemes()
    }
}

#[derive(Debug)]
struct GoClientVerifier {
    inner: GoVerifier,
    mandatory: bool,
}

impl ClientCertVerifier for GoClientVerifier {
    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        &[]
    }

    fn verify_client_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        now: UnixTime,
    ) -> Result<ClientCertVerified, rustls::Error> {
        let chain: Vec<Vec<u8>> = std::iter::once(end_entity)
            .chain(intermediates)
            .map(|c| c.as_ref().to_vec())
            .collect();
        verify_chain(
            &chain,
            self.inner.roots.certs(),
            None,
            unix_secs(now),
            Usage::Client,
        )
        .map_err(reject)?;
        Ok(ClientCertVerified::assertion())
    }

    fn client_auth_mandatory(&self) -> bool {
        self.mandatory
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(message, cert, dss, &self.inner.algs)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(message, cert, dss, &self.inner.algs)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.inner.algs.supported_schemes()
    }
}

// ---------------------------------------------------------------- Certificates

/// Metadata of one parsed certificate (`CertificateInfo`).
#[derive(Clone, Debug)]
pub struct CertInfo {
    pub subject: String,
    pub issuer: String,
    pub dns_names: Vec<String>,
    pub not_before: (i64, i32),
    pub not_after: (i64, i32),
    pub der: Vec<u8>,
}

/// `parse_certificates(pem, max)`.
pub fn parse_certificates(text: &str, max: Option<i64>) -> Result<Vec<CertInfo>, TlsErr> {
    let max = match max {
        None => usize::MAX,
        Some(m) if m < 0 => return Err(TlsErr::InvalidInput),
        Some(m) => m as usize,
    };
    let mut out = Vec::new();
    let mut rest = text;
    loop {
        rest = rest.trim();
        if rest.is_empty() {
            return Ok(out);
        }
        if !rest.starts_with("-----BEGIN CERTIFICATE-----") {
            return Err(TlsErr::InvalidData);
        }
        let Some((label, der, after)) = decode_block(rest, false) else {
            return Err(TlsErr::InvalidData);
        };
        if label != "CERTIFICATE" {
            return Err(TlsErr::InvalidData);
        }
        if out.len() >= max {
            return Err(TlsErr::LimitExceeded);
        }
        let (_, cert) = X509Certificate::from_der(&der).map_err(|_| TlsErr::InvalidData)?;
        let mut dns_names = Vec::new();
        if let Ok(Some(san)) = cert.subject_alternative_name() {
            for g in &san.value.general_names {
                if let GeneralName::DNSName(d) = g {
                    dns_names.push((*d).to_string());
                }
            }
        }
        out.push(CertInfo {
            subject: crate::dn::format(cert.subject()),
            issuer: crate::dn::format(cert.issuer()),
            dns_names,
            not_before: (cert.validity().not_before.timestamp(), 0),
            not_after: (cert.validity().not_after.timestamp(), 0),
            der: der.clone(),
        });
        rest = after;
    }
}

/// `verify_certificates(chain, roots, server_name, now)`.
pub fn verify_certificates(
    chain_pem: &str,
    roots_pem: &str,
    server_name: &str,
    now_seconds: i64,
) -> Result<(), TlsErr> {
    if server_name.is_empty() {
        return Err(TlsErr::InvalidInput);
    }
    let chain = strict_certificates(chain_pem)?;
    if chain.is_empty() {
        return Err(TlsErr::InvalidData);
    }
    let roots = strict_certificates(roots_pem)?;
    if roots.is_empty() {
        return Err(TlsErr::InvalidData);
    }
    verify_chain(
        &chain,
        &roots,
        Some(server_name),
        now_seconds,
        Usage::Server,
    )
    .map_err(|_| TlsErr::AuthenticationFailed)
}

// ------------------------------------------------------------------ Connection

/// A TLS stream over a nonblocking socket.
pub struct TlsIo {
    sock: OwnedSock,
    state: RefCell<rustls::Connection>,
    verified: bool,
}

fn handshake_error_text(e: &rustls::Error) -> String {
    match e {
        rustls::Error::General(m) => m.clone(),
        rustls::Error::AlertReceived(a) => {
            format!("TLS handshake: peer sent alert: {}", alert_text(a))
        }
        other => format!("TLS handshake: {other}"),
    }
}

fn alert_text(a: &rustls::AlertDescription) -> String {
    use rustls::AlertDescription as A;
    match a {
        A::BadCertificate => "bad certificate".into(),
        A::UnknownCA => "unknown certificate authority".into(),
        A::HandshakeFailure => "handshake failure".into(),
        A::CertificateRequired => "certificate required".into(),
        A::NoApplicationProtocol => "no application protocol".into(),
        A::ProtocolVersion => "protocol version not supported".into(),
        other => format!("{other:?}").to_lowercase(),
    }
}

/// Progress of a handshake step.
pub enum Handshake {
    Done,
    WantRead,
    WantWrite,
    Failed(NetErr),
}

impl TlsIo {
    /// Wraps a connected nonblocking socket; call `drive_handshake` until done.
    pub fn new(sock: socket2::Socket, conn: rustls::Connection, verified: bool) -> TlsIo {
        TlsIo {
            sock: OwnedSock::new(sock),
            state: RefCell::new(conn),
            verified,
        }
    }

    pub fn socket(&self) -> &socket2::Socket {
        &self.sock
    }

    /// Whether a server session received a client certificate.
    pub fn has_peer_certificates(&self) -> bool {
        self.state.borrow().peer_certificates().is_some()
    }

    pub fn set_verified(&mut self, verified: bool) {
        self.verified = verified;
    }

    /// Advances the handshake as far as the socket allows.
    pub fn drive_handshake(&self) -> Handshake {
        loop {
            let (handshaking, wants_write) = {
                let c = self.state.borrow();
                (c.is_handshaking(), c.wants_write())
            };
            if wants_write {
                match self.write_pending() {
                    Ok(true) => continue,
                    Ok(false) => return Handshake::WantWrite,
                    Err(e) => return Handshake::Failed(NetErr::Failed(describe_io_error(&e))),
                }
            }
            if !handshaking {
                return Handshake::Done;
            }
            match self.read_records() {
                Ok(true) => {}
                Ok(false) => return Handshake::WantRead,
                Err(HandshakeFail::Tls(e)) => {
                    let _ = self.write_pending();
                    return Handshake::Failed(NetErr::Failed(handshake_error_text(&e)));
                }
                Err(HandshakeFail::Io(e)) => {
                    return Handshake::Failed(NetErr::Failed(describe_io_error(&e)));
                }
            }
        }
    }

    /// Completes the handshake within `deadline`, blocking.
    pub fn handshake(
        sock: socket2::Socket,
        conn: rustls::Connection,
        deadline: Deadline,
        verified_hint: bool,
    ) -> Result<TlsIo, NetErr> {
        let io = TlsIo::new(sock, conn, verified_hint);
        loop {
            match io.drive_handshake() {
                Handshake::Done => return Ok(io),
                Handshake::Failed(e) => return Err(e),
                Handshake::WantWrite => {
                    if with_cleanup(&mut || io.sock.release(), || {
                        wait_fd(io.sock.as_sock(), Interest::Write, deadline)
                    }) == Wait::TimedOut
                    {
                        return Err(NetErr::Timeout);
                    }
                }
                Handshake::WantRead => {
                    if with_cleanup(&mut || io.sock.release(), || {
                        wait_fd(io.sock.as_sock(), Interest::Read, deadline)
                    }) == Wait::TimedOut
                    {
                        return Err(NetErr::Timeout);
                    }
                }
            }
        }
    }

    /// Writes buffered records; `Ok(false)` when the socket is full.
    fn write_pending(&self) -> io::Result<bool> {
        let mut c = self.state.borrow_mut();
        while c.wants_write() {
            match c.write_tls(&mut &*self.sock) {
                Ok(_) => {}
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(false),
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
                Err(e) => return Err(e),
            }
        }
        Ok(true)
    }

    /// Reads and processes records; `Ok(false)` when nothing is available.
    fn read_records(&self) -> Result<bool, HandshakeFail> {
        let mut c = self.state.borrow_mut();
        match c.read_tls(&mut &*self.sock) {
            Ok(0) => {
                return Err(HandshakeFail::Io(io::Error::from(
                    io::ErrorKind::UnexpectedEof,
                )));
            }
            Ok(_) => {}
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(false),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => return Ok(true),
            Err(e) => return Err(HandshakeFail::Io(e)),
        }
        c.process_new_packets().map_err(HandshakeFail::Tls)?;
        Ok(true)
    }
}

enum HandshakeFail {
    Tls(rustls::Error),
    Io(io::Error),
}

impl Io for TlsIo {
    fn fd(&self) -> Borrowed<'_> {
        self.sock.as_sock()
    }

    fn read(&self, buf: &mut [u8]) -> Step {
        loop {
            let got = self.state.borrow_mut().reader().read(buf);
            match got {
                Ok(0) if !buf.is_empty() => return Step::Eof,
                Ok(n) => return Step::Done(n),
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => {}
                Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Step::Eof,
                Err(e) => return Step::Err(e),
            }
            // Acknowledgements and key updates may be queued.
            match self.write_pending() {
                Ok(_) => {}
                Err(e) => return Step::Err(e),
            }
            match self.read_records() {
                Ok(true) => {}
                Ok(false) => return Step::WantRead,
                Err(HandshakeFail::Io(e)) if e.kind() == io::ErrorKind::UnexpectedEof => {
                    return Step::Eof;
                }
                Err(HandshakeFail::Io(e)) => return Step::Err(e),
                Err(HandshakeFail::Tls(e)) => {
                    let _ = self.write_pending();
                    return Step::Err(io::Error::other(handshake_error_text(&e)));
                }
            }
        }
    }

    fn write(&self, data: &[u8]) -> Step {
        loop {
            let n = match self.state.borrow_mut().writer().write(data) {
                Ok(n) => n,
                Err(e) => return Step::Err(e),
            };
            let flushed = match self.write_pending() {
                Ok(flushed) => flushed,
                Err(e) => return Step::Err(e),
            };
            // A full plaintext buffer accepts nothing; once the records drain it has room again,
            // so retry rather than report a zero-byte write, which callers treat as a short write.
            if n > 0 || data.is_empty() {
                return Step::Done(n);
            }
            if !flushed {
                return Step::WantWrite;
            }
        }
    }

    fn flush(&self) -> Step {
        match self.write_pending() {
            Ok(true) => Step::Done(0),
            Ok(false) => Step::WantWrite,
            Err(e) => Step::Err(e),
        }
    }

    fn shutdown_write(&self) -> Result<(), NetErr> {
        self.state.borrow_mut().send_close_notify();
        let _ = self.write_pending();
        self.sock
            .shutdown(std::net::Shutdown::Write)
            .map_err(|e| NetErr::Failed(describe_io_error(&e)))
    }

    fn shutdown_both(&self) {
        self.state.borrow_mut().send_close_notify();
        let _ = self.write_pending();
        let _ = self.sock.shutdown(std::net::Shutdown::Both);
    }

    fn release(&self) {
        self.sock.release();
    }

    fn tls_details(&self) -> Option<TlsDetails> {
        let c = self.state.borrow();
        let version = c.protocol_version().map(u16::from).unwrap_or(0);
        let suite = c
            .negotiated_cipher_suite()
            .map(|s| u16::from(s.suite()))
            .unwrap_or(0);
        let alpn = c
            .alpn_protocol()
            .map(|p| String::from_utf8_lossy(p).into_owned())
            .unwrap_or_default();
        let peers = c
            .peer_certificates()
            .map(|certs| certs.iter().map(|c| c.as_ref().to_vec()).collect())
            .unwrap_or_default();
        Some(TlsDetails {
            version: i64::from(version),
            cipher_suite: i64::from(suite),
            alpn,
            peer_certificates: peers,
            verified: self.verified,
        })
    }
}

/// Starts a client handshake on a connected socket.
pub fn connect(
    sock: socket2::Socket,
    config: Arc<ClientConfig>,
    server_name: &str,
    deadline: Deadline,
) -> Result<Box<dyn Io>, NetErr> {
    let name = server_name_for(server_name)?;
    let conn = rustls::ClientConnection::new(config, name)
        .map_err(|e| NetErr::Failed(handshake_error_text(&e)))?;
    let io = TlsIo::handshake(sock, rustls::Connection::Client(conn), deadline, true)?;
    Ok(Box::new(io))
}

/// Converts a host or IP literal to a TLS server name.
pub fn server_name_for(name: &str) -> Result<ServerName<'static>, NetErr> {
    ServerName::try_from(name.to_string()).map_err(|_| NetErr::InvalidInput)
}

/// Starts a server handshake on an accepted socket.
pub fn accept(
    sock: socket2::Socket,
    config: Arc<ServerConfig>,
    deadline: Deadline,
    verified_clients: bool,
) -> Result<Box<dyn Io>, NetErr> {
    let conn = rustls::ServerConnection::new(config)
        .map_err(|e| NetErr::Failed(handshake_error_text(&e)))?;
    let io = TlsIo::handshake(sock, rustls::Connection::Server(conn), deadline, false)?;
    // A server verified the client when one presented a certificate.
    let verified = verified_clients && io.state.borrow().peer_certificates().is_some();
    let io = TlsIo { verified, ..io };
    Ok(Box::new(io))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::net::Network;

    const CERT: &str = include_str!("../testdata/stdlib.test.crt.pem");
    const KEY: &str = include_str!("../testdata/stdlib.test.key.pem");
    const MUTUAL: &str = include_str!("../testdata/mutual.test.crt.pem");
    const MUTUAL_KEY: &str = include_str!("../testdata/mutual.test.key.pem");
    const NAMES: &str = include_str!("../testdata/dn-names.pem");
    const Y2020: i64 = 1_577_836_800;
    const Y2100: i64 = 4_102_444_800;

    #[test]
    fn parses_certificate_metadata() {
        let infos = parse_certificates(CERT, None).unwrap();
        assert_eq!(infos.len(), 1);
        let c = &infos[0];
        assert_eq!(c.subject, "CN=stdlib.test");
        assert_eq!(c.issuer, "CN=stdlib.test");
        assert_eq!(c.dns_names, vec!["stdlib.test"]);
        assert_eq!(c.not_before, (Y2020, 0));
        assert_eq!(c.not_after, (Y2100, 0));
        assert_eq!(
            parse_certificates(CERT, Some(0)).unwrap_err(),
            TlsErr::LimitExceeded
        );
        assert_eq!(
            parse_certificates(CERT, Some(-1)).unwrap_err(),
            TlsErr::InvalidInput
        );
        assert_eq!(
            parse_certificates("junk", None).unwrap_err(),
            TlsErr::InvalidData
        );
        assert_eq!(
            parse_certificates(KEY, None).unwrap_err(),
            TlsErr::InvalidData
        );
        assert!(parse_certificates("  \n", None).unwrap().is_empty());
        let two = format!("{CERT}\n\n{CERT}");
        assert_eq!(parse_certificates(&two, None).unwrap().len(), 2);
        assert_eq!(
            parse_certificates(&two, Some(1)).unwrap_err(),
            TlsErr::LimitExceeded
        );
    }

    #[test]
    fn names_follow_go_formatting() {
        let infos = parse_certificates(NAMES, None).unwrap();
        // Recorded vectors.
        assert_eq!(
            infos[0].subject,
            r"SERIALNUMBER=77,CN=a\,b,OU=OU,O=O1+O=O2,POSTALCODE=9,STREET=S,L=\ L#,ST=CA,C=US,1.2.3.4=#130178,0.9.2342.19200300.100.1.25=#13076578616d706c65"
        );
        assert_eq!(infos[1].subject, "CN=ünï");
    }

    #[test]
    fn verifies_chain_name_and_time() {
        let ok = |name: &str, now: i64| verify_certificates(CERT, CERT, name, now);
        assert_eq!(ok("stdlib.test", Y2020 + 10), Ok(()));
        assert_eq!(ok("127.0.0.1", Y2020 + 10), Ok(()));
        assert_eq!(
            ok("other.test", Y2020 + 10),
            Err(TlsErr::AuthenticationFailed)
        );
        assert_eq!(
            ok("stdlib.test", Y2020 - 1),
            Err(TlsErr::AuthenticationFailed)
        );
        assert_eq!(
            ok("stdlib.test", Y2100 + 1),
            Err(TlsErr::AuthenticationFailed)
        );
        assert_eq!(ok("", Y2020), Err(TlsErr::InvalidInput));
        assert_eq!(
            verify_certificates("", CERT, "a", Y2020),
            Err(TlsErr::InvalidData)
        );
        assert_eq!(
            verify_certificates(CERT, " ", "a", Y2020),
            Err(TlsErr::InvalidData)
        );
        // A different root does not vouch for the chain.
        let other = NAMES
            .split_inclusive("-----END CERTIFICATE-----\n")
            .next()
            .unwrap();
        assert_eq!(
            verify_certificates(CERT, other, "stdlib.test", Y2020 + 10),
            Err(TlsErr::AuthenticationFailed)
        );
    }

    #[test]
    fn wildcard_names() {
        assert!(dns_matches("*.example.com", "a.example.com"));
        assert!(!dns_matches("*.example.com", "example.com"));
        assert!(!dns_matches("*.example.com", "a.b.example.com"));
        assert!(dns_matches("EXAMPLE.com.", "example.com"));
    }

    fn options() -> TlsOptions {
        TlsOptions {
            server_name: "stdlib.test".into(),
            roots_pem: CERT.into(),
            certificate_pem: CERT.into(),
            private_key_pem: KEY.into(),
            alpn: vec!["h2".into(), "http/1.1".into()],
            require_client_certificate: false,
        }
    }

    /// Accepts one connection on a helper thread, echoes what it reads and reports
    /// the handshake outcome.
    fn serve_once(
        opts: TlsOptions,
    ) -> (
        String,
        std::thread::JoinHandle<Result<Option<TlsDetails>, NetErr>>,
    ) {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap().to_string();
        let config = server_config(&opts).unwrap();
        let clients = !opts.roots_pem.is_empty() || opts.require_client_certificate;
        let handle = std::thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            stream.set_nonblocking(true).unwrap();
            let sock = socket2::Socket::from(stream);
            let io = accept(
                sock,
                config,
                Deadline::after(std::time::Duration::from_secs(5)),
                clients,
            )?;
            let deadline = Deadline::after(std::time::Duration::from_secs(5));
            let mut buf = [0u8; 64];
            let n = loop {
                match io.read(&mut buf) {
                    Step::Done(n) => break n,
                    Step::Eof => break 0,
                    Step::WantRead => {
                        wait_fd(io.fd(), Interest::Read, deadline);
                    }
                    Step::WantWrite => {
                        wait_fd(io.fd(), Interest::Write, deadline);
                    }
                    Step::Err(e) => return Err(NetErr::Failed(e.to_string())),
                }
            };
            let mut sent = 0;
            while sent < n {
                match io.write(&buf[sent..n]) {
                    Step::Done(k) => sent += k,
                    _ => {
                        wait_fd(io.fd(), Interest::Write, deadline);
                    }
                }
            }
            while !matches!(io.flush(), Step::Done(_)) {
                wait_fd(io.fd(), Interest::Write, deadline);
            }
            let details = io.tls_details();
            io.shutdown_both();
            Ok(details)
        });
        (address, handle)
    }

    const SEC: Option<i64> = Some(5_000_000_000);

    #[test]
    fn handshake_and_exchange() {
        let net = Network::new_root();
        let (address, server) = serve_once(options());
        let client_opts = TlsOptions {
            certificate_pem: String::new(),
            private_key_pem: String::new(),
            ..options()
        };
        let conn = net.connect_tls_config(&address, &client_opts, SEC).unwrap();
        conn.write(b"ping", SEC).unwrap();
        assert_eq!(conn.read(Some(4), SEC).unwrap().unwrap(), b"ping");
        let info = conn.tls_info().unwrap();
        assert!(info.version == 0x0304 || info.version == 0x0303);
        assert_eq!(info.alpn, "h2");
        assert!(info.verified);
        assert_eq!(info.peer_certificates.len(), 1);
        let server_view = server.join().unwrap().unwrap().unwrap();
        assert_eq!(server_view.alpn, "h2");
        assert!(!server_view.verified);
    }

    #[test]
    fn rejects_wrong_name_and_untrusted_server() {
        let net = Network::new_root();
        let (address, server) = serve_once(options());
        let wrong = TlsOptions {
            server_name: "other.test".into(),
            ..options()
        };
        let err = net.connect_tls_config(&address, &wrong, SEC).err().unwrap();
        let NetErr::Failed(m) = err else {
            panic!("{err:?}")
        };
        assert!(
            m.contains("x509: certificate is valid for stdlib.test, not other.test"),
            "{m}"
        );
        let _ = server.join();

        let (address, server) = serve_once(options());
        let other = NAMES
            .split_inclusive("-----END CERTIFICATE-----\n")
            .next()
            .unwrap();
        let untrusted = TlsOptions {
            roots_pem: other.into(),
            ..options()
        };
        let err = net
            .connect_tls_config(&address, &untrusted, SEC)
            .err()
            .unwrap();
        let NetErr::Failed(m) = err else {
            panic!("{err:?}")
        };
        assert!(m.contains("signed by unknown authority"), "{m}");
        let _ = server.join();
    }

    #[test]
    fn mutual_tls_requires_a_client_certificate() {
        let net = Network::new_root();
        // Both sides present the same identity, which also vouches for itself.
        let mutual = TlsOptions {
            server_name: "mutual.test".into(),
            roots_pem: MUTUAL.into(),
            certificate_pem: MUTUAL.into(),
            private_key_pem: MUTUAL_KEY.into(),
            alpn: vec![],
            require_client_certificate: false,
        };
        let server_opts = TlsOptions {
            require_client_certificate: true,
            ..mutual.clone()
        };
        let (address, server) = serve_once(server_opts.clone());
        let conn = net.connect_tls_config(&address, &mutual, SEC).unwrap();
        conn.write(b"hi", SEC).unwrap();
        assert_eq!(conn.read(Some(2), SEC).unwrap().unwrap(), b"hi");
        assert!(server.join().unwrap().unwrap().unwrap().verified);

        let (address, server) = serve_once(server_opts.clone());
        let anonymous = TlsOptions {
            certificate_pem: String::new(),
            private_key_pem: String::new(),
            ..mutual.clone()
        };
        // TLS 1.3 reports the missing client certificate on the first read.
        let outcome = net
            .connect_tls_config(&address, &anonymous, SEC)
            .and_then(|c| {
                c.write(b"hi", SEC).map_err(|_| NetErr::Closed)?;
                c.read(Some(2), SEC).map_err(|_| NetErr::Closed)
            });
        assert!(outcome.is_err() || outcome == Ok(None), "{outcome:?}");
        assert!(server.join().unwrap().is_err());

        // A client certificate outside the server's roots is rejected.
        let (address, server) = serve_once(TlsOptions {
            roots_pem: CERT.into(),
            ..server_opts
        });
        let wrong_usage = TlsOptions {
            roots_pem: format!("{MUTUAL}{CERT}"),
            ..mutual
        };
        let outcome = net
            .connect_tls_config(&address, &wrong_usage, SEC)
            .and_then(|c| {
                c.write(b"hi", SEC).map_err(|_| NetErr::Closed)?;
                c.read(Some(2), SEC).map_err(|_| NetErr::Closed)
            });
        assert!(outcome.is_err() || outcome == Ok(None), "{outcome:?}");
        assert!(server.join().unwrap().is_err());
    }

    #[test]
    fn invalid_options_are_rejected() {
        let net = Network::new_root();
        let l = net.listen("127.0.0.1:0").unwrap();
        let mut o = options();
        o.private_key_pem = "nope".into();
        assert_eq!(
            net.connect_tls_config(l.address(), &o, SEC).err(),
            Some(NetErr::InvalidInput)
        );
        assert_eq!(
            net.listen_tls("127.0.0.1:0", &o, None).err(),
            Some(NetErr::InvalidInput)
        );
        let mut o = options();
        o.alpn = vec![String::new()];
        assert_eq!(
            net.connect_tls_config(l.address(), &o, SEC).err(),
            Some(NetErr::InvalidInput)
        );
        let mut o = options();
        o.server_name.clear();
        assert_eq!(
            net.connect_tls_config(l.address(), &o, SEC).err(),
            Some(NetErr::InvalidInput)
        );
        assert_eq!(
            net.connect_tls(l.address(), "", SEC).err(),
            Some(NetErr::InvalidInput)
        );
        let no_identity = TlsOptions {
            certificate_pem: String::new(),
            private_key_pem: String::new(),
            ..options()
        };
        assert_eq!(
            net.listen_tls("127.0.0.1:0", &no_identity, None).err(),
            Some(NetErr::InvalidInput)
        );
        assert_eq!(
            net.listen_tls("127.0.0.1:0", &options(), Some(-1)).err(),
            Some(NetErr::InvalidInput)
        );
    }
}
