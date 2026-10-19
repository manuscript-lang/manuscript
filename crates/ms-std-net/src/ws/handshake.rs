//! Opening handshake of RFC 6455, following gorilla/websocket (`server.go`, `client.go`,
//! `util.go`) and the origin policy of `pkg/runtime/websocket.go`.
//!
//! Everything here is a pure function over parsed heads and header lists; the HTTP server
//! exchange and the client call these and do the I/O themselves. Texts of the form
//! `websocket: ...` are gorilla's `HandshakeError` messages, which the Go runtime reports as
//! `WebSocketError.Failed(message)`.
//!
//! Facts recorded from the vendored gorilla by running it (a Go program outside the repo that
//! served raw requests): a rejected upgrade answers `Content-Type`, `Sec-Websocket-Version: 13`,
//! `X-Content-Type-Options: nosniff`, `Date`, `Content-Length` in that order with the body
//! `<status text>\n`; the server prefers its own subprotocol order (offered `a, b` against a
//! server list `[b, a]` selects `b`); and the 101 response is the exact byte string built by
//! [`accept`].

use crate::error::WsErr;
use crate::http::h1::{self, ResponseHead};
use crate::http::headers::canonical;
use crate::http::url;
use base64::Engine as _;
use base64::alphabet;
use base64::engine::{GeneralPurpose, GeneralPurposeConfig};
use ring::digest;
use ring::rand::{SecureRandom, SystemRandom};

/// A parsed header list as `h1` produces it: names as sent, values as bytes.
pub type Fields = [(String, Vec<u8>)];

/// The GUID RFC 6455 appends to the key.
pub const GUID: &str = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/// The only extension offered or accepted; both context takeovers are always off.
pub const DEFLATE_RESPONSE: &str =
    "permessage-deflate; server_no_context_takeover; client_no_context_takeover";

/// Go's `base64.StdEncoding` accepts non-zero trailing bits; the strict default does not.
const LENIENT: GeneralPurpose = GeneralPurpose::new(
    &alphabet::STANDARD,
    GeneralPurposeConfig::new().with_decode_allow_trailing_bits(true),
);

/// `Sec-WebSocket-Accept` for a challenge key.
pub fn accept_key(challenge: &str) -> String {
    let mut ctx = digest::Context::new(&digest::SHA1_FOR_LEGACY_USE_ONLY);
    ctx.update(challenge.as_bytes());
    ctx.update(GUID.as_bytes());
    base64::engine::general_purpose::STANDARD.encode(ctx.finish())
}

/// A fresh `Sec-WebSocket-Key`: 16 random bytes in base64.
pub fn generate_key() -> String {
    let mut bytes = [0u8; 16];
    if SystemRandom::new().fill(&mut bytes).is_err() {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos());
        bytes.copy_from_slice(&nanos.to_le_bytes());
    }
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// Whether `s` is the base64 text of exactly 16 bytes.
pub fn valid_challenge_key(s: &str) -> bool {
    !s.is_empty() && LENIENT.decode(s).is_ok_and(|b| b.len() == 16)
}

fn values<'a>(fields: &'a Fields, name: &'a str) -> impl Iterator<Item = &'a [u8]> {
    fields
        .iter()
        .filter(move |(n, _)| n.eq_ignore_ascii_case(name))
        .map(|(_, v)| v.as_slice())
}

/// `Header.Get`: the first value of `name`, or empty.
fn first_text(fields: &Fields, name: &str) -> String {
    values(fields, name)
        .next()
        .map(|v| String::from_utf8_lossy(v).into_owned())
        .unwrap_or_default()
}

fn is_token_octet(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&b)
}

fn skip_space(s: &str) -> &str {
    s.trim_start_matches([' ', '\t'])
}

fn next_token(s: &str) -> (&str, &str) {
    let end = s
        .bytes()
        .position(|b| !is_token_octet(b))
        .unwrap_or(s.len());
    s.split_at(end)
}

/// A token or a quoted string with backslash escapes; malformed quoting yields empty text.
fn next_token_or_quoted(s: &str) -> (String, &str) {
    let Some(body) = s.strip_prefix('"') else {
        let (t, rest) = next_token(s);
        return (t.to_string(), rest);
    };
    let mut out = String::new();
    let mut escape = false;
    for (i, c) in body.char_indices() {
        if escape {
            escape = false;
            out.push(c);
        } else if c == '\\' {
            escape = true;
        } else if c == '"' {
            return (out, &body[i + 1..]);
        } else {
            out.push(c);
        }
    }
    (String::new(), "")
}

/// gorilla's `tokenListContainsValue`: whether a comma-separated header holds `value` as a
/// token, ignoring ASCII case. A malformed element skips the rest of that header line.
pub fn token_list_contains(fields: &Fields, name: &str, value: &str) -> bool {
    values(fields, name).any(|line| line_has_token(&String::from_utf8_lossy(line), value))
}

fn line_has_token(line: &str, value: &str) -> bool {
    let mut s = line;
    loop {
        let (t, rest) = next_token(skip_space(s));
        if t.is_empty() {
            return false;
        }
        s = skip_space(rest);
        if !s.is_empty() && !s.starts_with(',') {
            return false;
        }
        if t.eq_ignore_ascii_case(value) {
            return true;
        }
        if s.is_empty() {
            return false;
        }
        s = &s[1..];
    }
}

/// One element of `Sec-WebSocket-Extensions`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Extension {
    pub name: String,
    pub params: Vec<(String, String)>,
}

impl Extension {
    pub fn has(&self, param: &str) -> bool {
        self.params.iter().any(|(k, _)| k == param)
    }
}

/// gorilla's `parseExtensions`; a malformed element ends that header line.
pub fn parse_extensions(fields: &Fields) -> Vec<Extension> {
    let mut out = Vec::new();
    for line in values(fields, "Sec-WebSocket-Extensions") {
        parse_extension_line(&String::from_utf8_lossy(line), &mut out);
    }
    out
}

fn parse_extension_line(line: &str, out: &mut Vec<Extension>) {
    let mut s = line;
    loop {
        let (name, rest) = next_token(skip_space(s));
        s = rest;
        if name.is_empty() {
            return;
        }
        let mut ext = Extension {
            name: name.to_string(),
            params: Vec::new(),
        };
        loop {
            s = skip_space(s);
            let Some(after) = s.strip_prefix(';') else {
                break;
            };
            let (key, rest) = next_token(skip_space(after));
            s = skip_space(rest);
            if key.is_empty() {
                return;
            }
            let mut value = String::new();
            if let Some(after) = s.strip_prefix('=') {
                let (v, rest) = next_token_or_quoted(skip_space(after));
                value = v;
                s = skip_space(rest);
            }
            if !s.is_empty() && !s.starts_with(',') && !s.starts_with(';') {
                return;
            }
            ext.params.push((key.to_string(), value));
        }
        if !s.is_empty() && !s.starts_with(',') {
            return;
        }
        out.push(ext);
        if s.is_empty() {
            return;
        }
        s = &s[1..];
    }
}

/// `websocket.Subprotocols(r)`: the comma-separated, trimmed offers of the first
/// `Sec-WebSocket-Protocol` line.
pub fn offered_subprotocols(fields: &Fields) -> Vec<String> {
    let line = first_text(fields, "Sec-WebSocket-Protocol");
    let line = line.trim();
    if line.is_empty() {
        return Vec::new();
    }
    line.split(',').map(|p| p.trim().to_string()).collect()
}

/// The subprotocol gorilla selects: the first server protocol, in the server's order, that
/// the client offered; empty when none matches.
pub fn select_subprotocol(offered: &[String], server: &[String]) -> String {
    server
        .iter()
        .find(|s| offered.iter().any(|o| o == *s))
        .cloned()
        .unwrap_or_default()
}

/// The origin policy of the Go runtime's `Upgrade`. `host` is the request's `Host` and `tls`
/// whether the connection is TLS.
///
/// A missing or empty `Origin` is accepted. Otherwise it must be a bare `http` or `https`
/// origin (no user info, path, query or fragment) that either equals an entry of `allowed`
/// exactly, or, when `allowed` is empty, has the request's scheme and host (host compared
/// ignoring ASCII case).
pub fn origin_allowed(fields: &Fields, host: &str, tls: bool, allowed: &[String]) -> bool {
    let origin = first_text(fields, "Origin");
    if origin.is_empty() {
        return true;
    }
    let Some(parsed) = url::parse(&origin) else {
        return false;
    };
    let bare = origin
        .split_once("://")
        .is_some_and(|(_, rest)| rest == parsed.authority);
    if !bare {
        return false;
    }
    if allowed.contains(&origin) {
        return true;
    }
    let scheme = if tls { "https" } else { "http" };
    allowed.is_empty() && parsed.scheme == scheme && parsed.authority.eq_ignore_ascii_case(host)
}

/// What the server side of an upgrade needs to know about the request.
#[derive(Clone, Copy, Debug)]
pub struct Request<'a> {
    pub method: &'a str,
    /// The `Host` of the request (`r.Host`).
    pub host: &'a str,
    /// Whether the connection is TLS.
    pub tls: bool,
    pub fields: &'a Fields,
}

/// Server-side settings of an upgrade.
#[derive(Clone, Copy, Debug, Default)]
pub struct ServerOptions<'a> {
    /// Allowed `Origin` values; empty means same origin only.
    pub allowed_origins: &'a [String],
    /// Subprotocols the server speaks, in order of preference.
    pub subprotocols: &'a [String],
    /// Negotiate permessage-deflate when the client offers it. The Go runtime never does.
    pub compression: bool,
}

/// An accepted upgrade.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Accepted {
    /// The selected subprotocol, empty when none.
    pub subprotocol: String,
    /// Whether permessage-deflate (no context takeover) was negotiated.
    pub compress: bool,
    /// The complete `101 Switching Protocols` response head.
    pub response: Vec<u8>,
}

/// A refused upgrade: the status gorilla answers and its handshake error text.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rejected {
    pub status: u16,
    /// gorilla's `HandshakeError` text, for example
    /// `websocket: request origin not allowed by Upgrader.CheckOrigin`.
    pub message: &'static str,
}

impl Rejected {
    const fn new(status: u16, message: &'static str) -> Rejected {
        Rejected { status, message }
    }

    /// The error the Go runtime returns: `Failed(<handshake error text>)`.
    pub fn error(&self) -> WsErr {
        WsErr::Failed(self.message.to_string())
    }

    /// The error response gorilla writes through `http.Error`; `date` is the Unix time for the
    /// `Date` header. `close` appends `Connection: close`.
    pub fn response(&self, date: i64, close: bool) -> Vec<u8> {
        let body = format!("{}\n", h1::status_text(self.status));
        let mut out = Vec::new();
        h1::status_line(&mut out, self.status);
        h1::header_line(&mut out, "Content-Type", b"text/plain; charset=utf-8");
        h1::header_line(&mut out, "Sec-Websocket-Version", b"13");
        h1::header_line(&mut out, "X-Content-Type-Options", b"nosniff");
        h1::header_line(&mut out, "Date", h1::http_date(date).as_bytes());
        h1::header_line(
            &mut out,
            "Content-Length",
            body.len().to_string().as_bytes(),
        );
        if close {
            h1::header_line(&mut out, "Connection", b"close");
        }
        out.extend_from_slice(b"\r\n");
        out.extend_from_slice(body.as_bytes());
        out
    }
}

/// Validates an upgrade request in gorilla's order (`Connection`, `Upgrade`, method, version,
/// origin, key) and builds the `101` response. The HTTP version is not checked, as in gorilla.
pub fn accept(req: &Request<'_>, options: &ServerOptions<'_>) -> Result<Accepted, Rejected> {
    let fields = req.fields;
    if !token_list_contains(fields, "Connection", "upgrade") {
        return Err(Rejected::new(
            400,
            "websocket: the client is not using the websocket protocol: 'upgrade' token not found in 'Connection' header",
        ));
    }
    if !token_list_contains(fields, "Upgrade", "websocket") {
        return Err(Rejected::new(
            400,
            "websocket: the client is not using the websocket protocol: 'websocket' token not found in 'Upgrade' header",
        ));
    }
    if req.method != "GET" {
        return Err(Rejected::new(
            405,
            "websocket: the client is not using the websocket protocol: request method is not GET",
        ));
    }
    if !token_list_contains(fields, "Sec-WebSocket-Version", "13") {
        return Err(Rejected::new(
            400,
            "websocket: unsupported version: 13 not found in 'Sec-Websocket-Version' header",
        ));
    }
    if !origin_allowed(fields, req.host, req.tls, options.allowed_origins) {
        return Err(Rejected::new(
            403,
            "websocket: request origin not allowed by Upgrader.CheckOrigin",
        ));
    }
    let key = first_text(fields, "Sec-WebSocket-Key");
    if !valid_challenge_key(&key) {
        return Err(Rejected::new(
            400,
            "websocket: not a websocket handshake: 'Sec-WebSocket-Key' header must be Base64 encoded value of 16-byte in length",
        ));
    }
    let subprotocol = select_subprotocol(&offered_subprotocols(fields), options.subprotocols);
    let compress = options.compression
        && parse_extensions(fields)
            .iter()
            .any(|e| e.name == "permessage-deflate");

    let mut out =
        b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            .to_vec();
    h1::header_line(
        &mut out,
        "Sec-WebSocket-Accept",
        accept_key(&key).as_bytes(),
    );
    if !subprotocol.is_empty() {
        h1::header_line(&mut out, "Sec-WebSocket-Protocol", subprotocol.as_bytes());
    }
    if compress {
        h1::header_line(
            &mut out,
            "Sec-WebSocket-Extensions",
            DEFLATE_RESPONSE.as_bytes(),
        );
    }
    out.extend_from_slice(b"\r\n");
    Ok(Accepted {
        subprotocol,
        compress,
        response: out,
    })
}

/// Settings of the client side of the opening handshake.
#[derive(Clone, Copy, Debug)]
pub struct ClientRequest<'a> {
    /// Request target: path and query, as `Url::request_uri` gives it.
    pub target: &'a str,
    /// Value of the `Host` header (the URL's authority).
    pub host: &'a str,
    /// The `Sec-WebSocket-Key` to send, from [`generate_key`].
    pub key: &'a str,
    /// Subprotocols to offer, in order.
    pub subprotocols: &'a [String],
    /// Caller headers, already validated; `Host`, `Upgrade`, `Connection` and `Sec-WebSocket-*`
    /// are the caller's to refuse before getting here.
    pub headers: &'a [(String, Vec<u8>)],
    /// Offer permessage-deflate.
    pub compression: bool,
}

/// The upgrade request as `http.Request.Write` emits it for gorilla's dialer: request line,
/// `Host`, `User-Agent`, then the remaining headers sorted by name.
pub fn client_request(req: &ClientRequest<'_>) -> Vec<u8> {
    let mut headers: Vec<(String, Vec<u8>)> = vec![
        ("Connection".into(), b"Upgrade".to_vec()),
        ("Sec-WebSocket-Key".into(), req.key.as_bytes().to_vec()),
        ("Sec-WebSocket-Version".into(), b"13".to_vec()),
        ("Upgrade".into(), b"websocket".to_vec()),
    ];
    if !req.subprotocols.is_empty() {
        headers.push((
            "Sec-WebSocket-Protocol".into(),
            req.subprotocols.join(", ").into_bytes(),
        ));
    }
    if req.compression {
        headers.push((
            "Sec-WebSocket-Extensions".into(),
            DEFLATE_RESPONSE.as_bytes().to_vec(),
        ));
    }
    let mut agent = b"Go-http-client/1.1".to_vec();
    for (name, value) in req.headers {
        if name.eq_ignore_ascii_case("User-Agent") {
            agent = clean_value(value);
        } else {
            headers.push((canonical(name), clean_value(value)));
        }
    }
    // Stable, so repeated values keep their order.
    headers.sort_by(|a, b| a.0.cmp(&b.0));

    let mut out = Vec::new();
    out.extend_from_slice(format!("GET {} HTTP/1.1\r\n", req.target).as_bytes());
    h1::header_line(&mut out, "Host", req.host.as_bytes());
    h1::header_line(&mut out, "User-Agent", &agent);
    for (name, value) in &headers {
        h1::header_line(&mut out, name, value);
    }
    out.extend_from_slice(b"\r\n");
    out
}

/// `textproto` trims header values and turns line breaks into spaces.
fn clean_value(value: &[u8]) -> Vec<u8> {
    let text: Vec<u8> = value
        .iter()
        .map(|&b| if b == b'\r' || b == b'\n' { b' ' } else { b })
        .collect();
    let start = text
        .iter()
        .position(|b| !matches!(b, b' ' | b'\t'))
        .unwrap_or(text.len());
    let end = text
        .iter()
        .rposition(|b| !matches!(b, b' ' | b'\t'))
        .map_or(start, |i| i + 1);
    text[start..end].to_vec()
}

/// A refused server response.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClientFailure {
    /// Not a valid `101` for this key (`ErrBadHandshake`).
    BadHandshake,
    /// permessage-deflate without both no-context-takeover parameters.
    InvalidCompression,
}

impl ClientFailure {
    /// gorilla's error text.
    pub fn message(&self) -> &'static str {
        match self {
            ClientFailure::BadHandshake => "websocket: bad handshake",
            ClientFailure::InvalidCompression => "websocket: invalid compression negotiation",
        }
    }

    pub fn error(&self) -> WsErr {
        WsErr::Failed(self.message().to_string())
    }
}

/// The outcome of a valid server response.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClientAccepted {
    /// `Sec-WebSocket-Protocol` of the response, taken as sent (gorilla does not check it
    /// against the offers); empty when absent.
    pub subprotocol: String,
    pub compress: bool,
}

/// gorilla's client checks on the response: status 101, `Upgrade` and `Connection` tokens,
/// the accept key, then the extension (applied whenever the server sends it, as gorilla does
/// even when the client did not offer it).
pub fn check_response(
    status: u16,
    fields: &Fields,
    key: &str,
) -> Result<ClientAccepted, ClientFailure> {
    let accept = first_text(fields, "Sec-WebSocket-Accept");
    if status != 101
        || !token_list_contains(fields, "Upgrade", "websocket")
        || !token_list_contains(fields, "Connection", "upgrade")
        || accept != accept_key(key)
    {
        return Err(ClientFailure::BadHandshake);
    }
    let mut compress = false;
    if let Some(ext) = parse_extensions(fields)
        .iter()
        .find(|e| e.name == "permessage-deflate")
    {
        if !ext.has("server_no_context_takeover") || !ext.has("client_no_context_takeover") {
            return Err(ClientFailure::InvalidCompression);
        }
        compress = true;
    }
    Ok(ClientAccepted {
        subprotocol: first_text(fields, "Sec-WebSocket-Protocol"),
        compress,
    })
}

/// [`check_response`] over a parsed response head.
pub fn check_response_head(
    head: &ResponseHead,
    key: &str,
) -> Result<ClientAccepted, ClientFailure> {
    check_response(head.status, &head.fields, key)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http::h1::{Parsed, parse_request, parse_response};

    const SAMPLE_KEY: &str = "dGhlIHNhbXBsZSBub25jZQ==";
    const SAMPLE_ACCEPT: &str = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=";

    fn fields(list: &[(&str, &str)]) -> Vec<(String, Vec<u8>)> {
        list.iter()
            .map(|(n, v)| (n.to_string(), v.as_bytes().to_vec()))
            .collect()
    }

    fn upgrade_fields(extra: &[(&str, &str)]) -> Vec<(String, Vec<u8>)> {
        let mut f = fields(&[
            ("Host", "x"),
            ("Connection", "keep-alive, Upgrade"),
            ("Upgrade", "WebSocket"),
            ("Sec-WebSocket-Version", "13"),
            ("Sec-WebSocket-Key", SAMPLE_KEY),
        ]);
        f.extend(fields(extra));
        f
    }

    fn request<'a>(f: &'a Fields) -> Request<'a> {
        Request {
            method: "GET",
            host: "x",
            tls: false,
            fields: f,
        }
    }

    fn reject(f: &Fields, method: &str) -> Rejected {
        let req = Request {
            method,
            ..request(f)
        };
        accept(&req, &ServerOptions::default()).unwrap_err()
    }

    #[test]
    fn rfc6455_sample_key() {
        assert_eq!(accept_key(SAMPLE_KEY), SAMPLE_ACCEPT);
        assert!(valid_challenge_key(SAMPLE_KEY));
        assert!(!valid_challenge_key(""));
        assert!(!valid_challenge_key("abc"));
        assert!(!valid_challenge_key("dGhlIHNhbXBsZSBub25jZQ"));
        // 15 bytes.
        assert!(!valid_challenge_key("dGhlIHNhbXBsZSBub24="));
        // Non-zero trailing bits are accepted like Go's StdEncoding.
        assert!(valid_challenge_key("dGhlIHNhbXBsZSBub25jZR=="));
    }

    #[test]
    fn generated_keys_are_valid_and_distinct() {
        let a = generate_key();
        let b = generate_key();
        assert!(valid_challenge_key(&a));
        assert_ne!(a, b);
    }

    #[test]
    fn token_lists_follow_gorilla() {
        let f = fields(&[
            ("Connection", "keep-alive , UPGRADE"),
            ("X", "a b, upgrade"),
        ]);
        assert!(token_list_contains(&f, "connection", "upgrade"));
        // "a b" is not a token list element, so the rest of the line is skipped.
        assert!(!token_list_contains(&f, "X", "upgrade"));
        let f = fields(&[("Connection", "close"), ("Connection", "upgrade")]);
        assert!(token_list_contains(&f, "Connection", "upgrade"));
        assert!(!token_list_contains(
            &fields(&[("Connection", "")]),
            "Connection",
            "upgrade"
        ));
    }

    #[test]
    fn extensions_parse_like_gorilla() {
        let f = fields(&[(
            "Sec-WebSocket-Extensions",
            "permessage-deflate; client_max_window_bits=\"15\", x-other;a=b",
        )]);
        let exts = parse_extensions(&f);
        assert_eq!(exts.len(), 2);
        assert_eq!(exts[0].name, "permessage-deflate");
        assert_eq!(
            exts[0].params,
            vec![("client_max_window_bits".into(), "15".into())]
        );
        assert!(exts[1].has("a"));
        // A malformed element is dropped with the rest of its line.
        let f = fields(&[("Sec-WebSocket-Extensions", "ok, bad;;x")]);
        assert_eq!(parse_extensions(&f).len(), 1);
    }

    #[test]
    fn subprotocols_use_server_order() {
        let f = fields(&[("Sec-WebSocket-Protocol", " a , b")]);
        let offered = offered_subprotocols(&f);
        assert_eq!(offered, vec!["a", "b"]);
        let server = vec!["b".to_string(), "a".to_string()];
        // Recorded from gorilla: offers a, b against [b, a] select b.
        assert_eq!(select_subprotocol(&offered, &server), "b");
        assert_eq!(select_subprotocol(&offered, &["z".to_string()]), "");
        assert_eq!(select_subprotocol(&[], &server), "");
    }

    #[test]
    fn origin_policy() {
        let none = fields(&[]);
        assert!(origin_allowed(&none, "x", false, &[]));
        let o = |v: &str| fields(&[("Origin", v)]);
        assert!(origin_allowed(&o(""), "x", false, &[]));
        assert!(origin_allowed(&o("http://Host:80"), "host:80", false, &[]));
        assert!(!origin_allowed(
            &o("https://host:80"),
            "host:80",
            false,
            &[]
        ));
        assert!(origin_allowed(&o("https://host"), "HOST", true, &[]));
        assert!(!origin_allowed(
            &o("http://evil.example"),
            "host",
            false,
            &[]
        ));
        let list = vec!["https://app.example".to_string()];
        assert!(origin_allowed(
            &o("https://app.example"),
            "host",
            false,
            &list
        ));
        // With a list, same origin no longer passes.
        assert!(!origin_allowed(&o("http://host"), "host", false, &list));
        for bad in [
            "null",
            "http://host/",
            "http://host/p",
            "http://host?q",
            "http://host#f",
            "http://u@host",
            "ftp://host",
            "http://",
        ] {
            assert!(!origin_allowed(&o(bad), "host", false, &[]), "{bad}");
        }
    }

    #[test]
    fn server_accepts_and_builds_the_101() {
        let f = upgrade_fields(&[("Sec-WebSocket-Protocol", "a, b")]);
        let protocols = vec!["b".to_string()];
        let options = ServerOptions {
            subprotocols: &protocols,
            ..ServerOptions::default()
        };
        let a = accept(&request(&f), &options).unwrap();
        assert_eq!(a.subprotocol, "b");
        assert!(!a.compress);
        // Byte for byte what the vendored gorilla wrote (recorded by running it).
        let want = format!(
            "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {SAMPLE_ACCEPT}\r\nSec-WebSocket-Protocol: b\r\n\r\n"
        );
        assert_eq!(String::from_utf8(a.response).unwrap(), want);
    }

    #[test]
    fn server_negotiates_deflate_only_when_enabled() {
        let f = upgrade_fields(&[(
            "Sec-WebSocket-Extensions",
            "permessage-deflate; client_max_window_bits",
        )]);
        let off = accept(&request(&f), &ServerOptions::default()).unwrap();
        assert!(!off.compress);
        assert!(!String::from_utf8_lossy(&off.response).contains("Extensions"));
        let on = accept(
            &request(&f),
            &ServerOptions {
                compression: true,
                ..ServerOptions::default()
            },
        )
        .unwrap();
        assert!(on.compress);
        let text = String::from_utf8(on.response).unwrap();
        assert!(text.contains(&format!("Sec-WebSocket-Extensions: {DEFLATE_RESPONSE}\r\n")));
    }

    #[test]
    fn server_rejections_use_gorilla_texts() {
        let f = fields(&[("Host", "x")]);
        let r = reject(&f, "GET");
        assert_eq!(r.status, 400);
        assert!(
            r.message
                .ends_with("'upgrade' token not found in 'Connection' header")
        );
        let f = fields(&[("Connection", "Upgrade")]);
        assert!(
            reject(&f, "GET")
                .message
                .ends_with("'websocket' token not found in 'Upgrade' header")
        );
        let f = upgrade_fields(&[]);
        let r = reject(&f, "POST");
        assert_eq!(r.status, 405);
        assert!(r.message.ends_with("request method is not GET"));
        let mut f = upgrade_fields(&[]);
        f.retain(|(n, _)| n != "Sec-WebSocket-Version");
        let r = reject(&f, "GET");
        assert_eq!(
            r.message,
            "websocket: unsupported version: 13 not found in 'Sec-Websocket-Version' header"
        );
        let f = upgrade_fields(&[("Origin", "http://evil")]);
        let r = reject(&f, "GET");
        assert_eq!(r.status, 403);
        assert_eq!(r.error(), WsErr::Failed(r.message.to_string()));
        let mut f = upgrade_fields(&[]);
        f.retain(|(n, _)| n != "Sec-WebSocket-Key");
        let r = reject(&f, "GET");
        assert_eq!(r.status, 400);
        assert!(
            r.message
                .contains("must be Base64 encoded value of 16-byte in length")
        );
        // The checks run in gorilla's order: a bad key hides behind a bad method.
        assert_eq!(reject(&f, "PUT").status, 405);
    }

    #[test]
    fn rejection_response_matches_http_error() {
        let r = Rejected::new(403, "x");
        let text = String::from_utf8(r.response(0, false)).unwrap();
        assert_eq!(
            text,
            "HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain; charset=utf-8\r\nSec-Websocket-Version: 13\r\nX-Content-Type-Options: nosniff\r\nDate: Thu, 01 Jan 1970 00:00:00 GMT\r\nContent-Length: 10\r\n\r\nForbidden\n"
        );
        let closing = String::from_utf8(r.response(0, true)).unwrap();
        assert!(closing.contains("Content-Length: 10\r\nConnection: close\r\n\r\n"));
    }

    fn sample_request(compression: bool, protocols: &[String]) -> Vec<u8> {
        let headers = vec![
            ("x-token".to_string(), b"  t \r\n".to_vec()),
            ("User-Agent".to_string(), b"me".to_vec()),
        ];
        client_request(&ClientRequest {
            target: "/chat?x=1",
            host: "h:80",
            key: SAMPLE_KEY,
            subprotocols: protocols,
            headers: &headers,
            compression,
        })
    }

    #[test]
    fn client_request_bytes() {
        let protocols = vec!["a".to_string(), "b".to_string()];
        let text = String::from_utf8(sample_request(true, &protocols)).unwrap();
        let want = format!(
            "GET /chat?x=1 HTTP/1.1\r\nHost: h:80\r\nUser-Agent: me\r\nConnection: Upgrade\r\nSec-WebSocket-Extensions: {DEFLATE_RESPONSE}\r\nSec-WebSocket-Key: {SAMPLE_KEY}\r\nSec-WebSocket-Protocol: a, b\r\nSec-WebSocket-Version: 13\r\nUpgrade: websocket\r\nX-Token: t\r\n\r\n"
        );
        assert_eq!(text, want);
        let plain = String::from_utf8(sample_request(false, &[])).unwrap();
        assert!(!plain.contains("Extensions") && !plain.contains("Protocol"));
    }

    #[test]
    fn client_request_parses_and_the_server_accepts_it() {
        let bytes = sample_request(true, &["echo".to_string()]);
        let Parsed::Complete(head) = parse_request(&bytes, 1 << 16) else {
            panic!("not a request");
        };
        assert_eq!(head.length, bytes.len());
        let req = Request {
            method: &head.method,
            host: "h:80",
            tls: false,
            fields: &head.fields,
        };
        let protocols = vec!["echo".to_string()];
        let options = ServerOptions {
            subprotocols: &protocols,
            compression: true,
            ..ServerOptions::default()
        };
        let accepted = accept(&req, &options).unwrap();
        assert!(accepted.compress);
        let Parsed::Complete(resp) = parse_response(&accepted.response, 1 << 16) else {
            panic!("not a response");
        };
        let done = check_response_head(&resp, SAMPLE_KEY).unwrap();
        assert_eq!(
            done,
            ClientAccepted {
                subprotocol: "echo".into(),
                compress: true
            }
        );
    }

    #[test]
    fn client_validates_the_response() {
        let ok = fields(&[
            ("Upgrade", "websocket"),
            ("Connection", "Upgrade"),
            ("Sec-WebSocket-Accept", SAMPLE_ACCEPT),
        ]);
        assert_eq!(
            check_response(101, &ok, SAMPLE_KEY).unwrap(),
            ClientAccepted {
                subprotocol: String::new(),
                compress: false
            }
        );
        let bad = ClientFailure::BadHandshake;
        assert_eq!(check_response(200, &ok, SAMPLE_KEY), Err(bad));
        assert_eq!(
            check_response(101, &ok, "AAAAAAAAAAAAAAAAAAAAAA=="),
            Err(bad)
        );
        let mut no_upgrade = ok.clone();
        no_upgrade.retain(|(n, _)| n != "Upgrade");
        assert_eq!(check_response(101, &no_upgrade, SAMPLE_KEY), Err(bad));
        assert_eq!(bad.message(), "websocket: bad handshake");
        assert_eq!(
            bad.error(),
            WsErr::Failed("websocket: bad handshake".into())
        );

        let mut partial = ok.clone();
        partial.extend(fields(&[(
            "Sec-WebSocket-Extensions",
            "permessage-deflate; server_no_context_takeover",
        )]));
        let invalid = check_response(101, &partial, SAMPLE_KEY).unwrap_err();
        assert_eq!(
            invalid.message(),
            "websocket: invalid compression negotiation"
        );
        let mut full = ok;
        full.extend(fields(&[("Sec-WebSocket-Extensions", DEFLATE_RESPONSE)]));
        assert!(check_response(101, &full, SAMPLE_KEY).unwrap().compress);
    }
}
