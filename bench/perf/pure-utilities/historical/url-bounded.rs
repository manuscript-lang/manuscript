//! `@std/net/net.ms` natives, built on the byte-oriented parser in [`gourl`].
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod ffi;
pub mod gourl;

use alloc::string::String;
use alloc::vec::Vec;
use gourl::{S, Url};
use ms_rt::ffi::Fail;

/// The `Url` record of `@std/net/net.ms`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Components {
    pub scheme: String,
    pub host: String,
    pub port: Option<i64>,
    pub path: String,
    pub query: String,
    pub fragment: String,
}

fn string(b: S) -> Result<String, Fail> {
    String::from_utf8(b).map_err(|_| Fail::InvalidData)
}

fn valid_utf8(b: &[u8]) -> bool {
    core::str::from_utf8(b).is_ok()
}

/// Go's `strings.ToLower` for text that may hold invalid UTF-8 (each bad byte becomes U+FFFD).
fn go_lower(b: &[u8]) -> String {
    if b.is_ascii() {
        return String::from_utf8_lossy(b).to_ascii_lowercase();
    }
    let mut out = String::new();
    let mut rest = b;
    while !rest.is_empty() {
        match core::str::from_utf8(rest) {
            Ok(s) => {
                push_lower(&mut out, s);
                break;
            }
            Err(e) => {
                let (good, bad) = rest.split_at(e.valid_up_to());
                push_lower(&mut out, core::str::from_utf8(good).unwrap_or(""));
                out.push('\u{fffd}');
                rest = &bad[1..];
            }
        }
    }
    out
}

fn push_lower(out: &mut String, s: &str) {
    for c in s.chars() {
        out.push(c.to_lowercase().next().unwrap_or(c));
    }
}

/// Percent-encodes every byte except `A-Za-z0-9-._~`.
pub fn encode_component(text: &str) -> String {
    const DIGITS: &[u8; 16] = b"0123456789ABCDEF";
    let mut out = String::with_capacity(text.len());
    for &v in text.as_bytes() {
        if v.is_ascii_alphanumeric() || matches!(v, b'-' | b'.' | b'_' | b'~') {
            out.push(v as char);
        } else {
            out.push('%');
            out.push(DIGITS[(v >> 4) as usize] as char);
            out.push(DIGITS[(v & 15) as usize] as char);
        }
    }
    out
}

/// Decodes `%XX` escapes; `+` stays a plus; the result must be valid UTF-8.
pub fn decode_component(text: &str) -> Result<String, Fail> {
    // Keep the existing decoder for small or percent-leading components. Searching
    // each escape adds setup cost there; long literal prefixes benefit from bulk search.
    if text.len() < 256 || text.as_bytes()[0] == b'%' {
        let b = gourl::path_unescape(text.as_bytes()).map_err(|_| Fail::InvalidData)?;
        return string(b);
    }
    let bytes = text.as_bytes();
    let mut escapes = text.match_indices('%');
    let Some((first, _)) = escapes.next() else {
        return Ok(String::from(text));
    };
    // Validate every escape before allocating, including errors after a valid prefix.
    for at in core::iter::once(first).chain(escapes.map(|(at, _)| at)) {
        let pair = bytes.get(at + 1..at + 3).ok_or(Fail::InvalidData)?;
        if !pair[0].is_ascii_hexdigit() || !pair[1].is_ascii_hexdigit() {
            return Err(Fail::InvalidData);
        }
    }
    let mut out = Vec::with_capacity(bytes.len());
    out.extend_from_slice(&bytes[..first]);
    let mut i = first;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            out.push(component_unhex(bytes[i + 1]) << 4 | component_unhex(bytes[i + 2]));
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    string(out)
}

// Called only after every percent escape's two ASCII hex digits were checked.
fn component_unhex(byte: u8) -> u8 {
    match byte {
        b'0'..=b'9' => byte - b'0',
        b'a'..=b'f' => byte - b'a' + 10,
        b'A'..=b'F' => byte - b'A' + 10,
        _ => unreachable!("validated component escape"),
    }
}

fn valid_query(query: &[u8]) -> bool {
    let mut i = 0;
    while i < query.len() {
        let c = query[i];
        if c == b'#' || c == b' ' || c < 0x20 || c == 0x7f {
            return false;
        }
        if c == b'%'
            && (i + 2 >= query.len()
                || !query[i + 1].is_ascii_hexdigit()
                || !query[i + 2].is_ascii_hexdigit())
        {
            return false;
        }
        i += 1;
    }
    true
}

fn components(u: &Url) -> Result<Components, Fail> {
    if u.has_user() || !u.opaque.is_empty() || u.scheme.is_empty() {
        return Err(Fail::InvalidData);
    }
    let (hostname, port_text) = u.host_port();
    let port = if port_text.is_empty() {
        None
    } else {
        // Digits only (validated by the parser); overflow or a value above 65535 is rejected.
        let mut n: i64 = 0;
        for &d in port_text {
            n = n
                .checked_mul(10)
                .and_then(|n| n.checked_add(i64::from(d - b'0')))
                .ok_or(Fail::InvalidData)?;
            if n > 65535 {
                return Err(Fail::InvalidData);
            }
        }
        Some(n)
    };
    if !valid_utf8(&u.path) || !valid_utf8(&u.fragment) || !valid_query(&u.raw_query) {
        return Err(Fail::InvalidData);
    }
    // Only a bracketed IP literal may contain a colon; "host:80:80" is malformed.
    if hostname.contains(&b':') && !u.host.starts_with(b"[") {
        return Err(Fail::InvalidData);
    }
    Ok(Components {
        scheme: go_lower(&u.scheme),
        host: go_lower(hostname),
        port,
        path: string(u.escaped_path())?,
        query: string(u.raw_query.clone())?,
        fragment: string(u.fragment.clone())?,
    })
}

/// Parses an absolute URL; user information, opaque URLs and a missing scheme are rejected.
pub fn parse(text: &str) -> Result<Components, Fail> {
    let u = gourl::parse(text.as_bytes()).map_err(|_| Fail::InvalidData)?;
    if u.scheme.is_empty() || u.has_user() {
        return Err(Fail::InvalidData);
    }
    components(&u)
}

/// Rebuilds a Go URL from components, rejecting anything that would not parse back.
fn go_url(v: &Components) -> Option<Url> {
    let mut host: S = v.host.as_bytes().to_vec();
    if host.contains(&b':') {
        let mut h = alloc::vec![b'['];
        h.extend_from_slice(&host);
        h.push(b']');
        host = h;
    }
    if let Some(n) = v.port {
        if !(0..=65535).contains(&n) {
            return None;
        }
        // net.JoinHostPort
        let mut h = v.host.as_bytes().to_vec();
        if h.contains(&b':') {
            let mut b = alloc::vec![b'['];
            b.extend_from_slice(&h);
            b.push(b']');
            h = b;
        }
        h.push(b':');
        h.extend_from_slice(alloc::format!("{n}").as_bytes());
        host = h;
    }
    let raw = v.path.as_bytes();
    // Without an authority, a relative path would be serialized as a hostname.
    if host.is_empty() && !raw.is_empty() && raw[0] != b'/' {
        return None;
    }
    let decoded = gourl::path_unescape(raw).ok()?;
    if !valid_utf8(&decoded) {
        return None;
    }
    if !valid_query(v.query.as_bytes()) || host.iter().any(|b| b" <>\"".contains(b)) {
        return None;
    }
    let u = Url {
        scheme: v.scheme.as_bytes().to_vec(),
        host,
        path: decoded,
        raw_path: raw.to_vec(),
        raw_query: v.query.as_bytes().to_vec(),
        fragment: v.fragment.as_bytes().to_vec(),
        ..Url::default()
    };
    let parsed = gourl::parse(&u.render()).ok()?;
    if parsed.scheme.is_empty()
        || !parsed.scheme.eq_ignore_ascii_case(&u.scheme)
        || !parsed.opaque.is_empty()
        || parsed.has_user()
        || u.host.iter().any(|b| b"/@\\\r\n".contains(b))
    {
        return None;
    }
    Some(u)
}

/// Formats components as an absolute hierarchical URL.
pub fn format(v: &Components) -> Result<String, Fail> {
    let u = go_url(v).ok_or(Fail::InvalidInput)?;
    let mut text = u.render();
    if u.host.is_empty() && u.path.is_empty() {
        // Go omits the empty authority; keep "//" so the text parses back.
        let mut with = u.scheme.clone();
        with.extend_from_slice(b"://");
        with.extend_from_slice(
            text.strip_prefix(&[u.scheme.as_slice(), b":"].concat()[..])
                .unwrap_or(&text),
        );
        text = with;
    }
    string(text)
}

/// Resolves a relative reference against `base` (RFC 3986 section 5.2 as in Go).
pub fn resolve(base: &Components, reference: &str) -> Result<Components, Fail> {
    let b = go_url(base).ok_or(Fail::InvalidInput)?;
    let r = gourl::parse(reference.as_bytes()).map_err(|_| Fail::InvalidData)?;
    if r.has_user() {
        return Err(Fail::InvalidData);
    }
    components(&b.resolve_reference(&r))
}

/// Parses a query string into decoded entries, preserving duplicates and order.
pub fn parse_query(text: &str, max_entries: Option<i64>) -> Result<Vec<(String, String)>, Fail> {
    let limit = match max_entries {
        None => usize::MAX,
        Some(n) if n < 0 => return Err(Fail::InvalidInput),
        Some(n) => n as usize,
    };
    let mut items = Vec::new();
    if text.is_empty() {
        return Ok(items);
    }
    for part in text.split('&') {
        if part.is_empty() {
            continue;
        }
        if items.len() >= limit {
            return Err(Fail::LimitExceeded);
        }
        let (k, v) = part.split_once('=').unwrap_or((part, ""));
        let (k, v) = match (
            gourl::query_unescape(k.as_bytes()),
            gourl::query_unescape(v.as_bytes()),
        ) {
            (Ok(k), Ok(v)) => (string(k)?, string(v)?),
            _ => return Err(Fail::InvalidData),
        };
        items.push((k, v));
    }
    Ok(items)
}

/// Encodes entries as `key=value` pairs joined by `&`.
pub fn format_query<K: AsRef<str>, V: AsRef<str>>(entries: &[(K, V)]) -> String {
    let mut out = String::new();
    for (i, (k, v)) in entries.iter().enumerate() {
        if i > 0 {
            out.push('&');
        }
        for part in [
            gourl::query_escape(k.as_ref().as_bytes()),
            alloc::vec![b'='],
            gourl::query_escape(v.as_ref().as_bytes()),
        ] {
            out.push_str(core::str::from_utf8(&part).unwrap_or(""));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    extern crate std;
    use super::*;

    fn c(
        scheme: &str,
        host: &str,
        port: Option<i64>,
        path: &str,
        query: &str,
        fragment: &str,
    ) -> Components {
        Components {
            scheme: scheme.into(),
            host: host.into(),
            port,
            path: path.into(),
            query: query.into(),
            fragment: fragment.into(),
        }
    }

    #[test]
    fn components_encode_decode() {
        assert_eq!(encode_component("a b/é~"), "a%20b%2F%C3%A9~");
        assert_eq!(decode_component("a%20b+c").unwrap(), "a b+c");
        assert_eq!(decode_component("%zz"), Err(Fail::InvalidData));
        assert_eq!(decode_component("%ff"), Err(Fail::InvalidData));
    }

    #[test]
    fn component_decoder_preserves_previous_results() {
        let check = |input: &str| {
            let previous = gourl::path_unescape(input.as_bytes())
                .map_err(|_| Fail::InvalidData)
                .and_then(string);
            assert_eq!(decode_component(input), previous, "{input:?}");
        };
        for input in [
            "",
            "a+b",
            "a\0b",
            "%00",
            "%2b",
            "%2B",
            "%",
            "%0",
            "%zz",
            "%C3%A9",
            "%F0%9F%95%B0",
            "%ff",
            "%C0%AF",
            "%ED%A0%80",
            "%F4%90%80%80",
            "é%20🕰",
            "%é",
            "%1é",
            "%41%zz",
            "%41%",
            "%C3%A9%zz",
            "é%00",
            "%25%32%30",
        ] {
            check(input);
        }
        for byte in 0..=255 {
            check(&alloc::format!("prefix%{byte:02x}+suffix"));
            check(&alloc::format!("prefix%{byte:02X}+suffix"));
        }
        let chunks = ["a", "+", "%", "0", "f", "é", "🕰", "\0"];
        for mut seed in 0..chunks.len().pow(5) {
            let mut input = String::new();
            for _ in 0..5 {
                input.push_str(chunks[seed % chunks.len()]);
                seed /= chunks.len();
            }
            check(&input);
        }
        for tail in ["", "%", "%ff", "%20", "%C3%A9"] {
            check(&alloc::format!("{}{tail}", "a".repeat(16384)));
            check(&alloc::format!("{}{tail}", "%20".repeat(16384)));
        }
    }

    #[test]
    fn parses() {
        assert_eq!(
            parse("HTTPS://Example.COM:8080/a%2Fb/c?x=1&y#frag").unwrap(),
            c(
                "https",
                "example.com",
                Some(8080),
                "/a%2Fb/c",
                "x=1&y",
                "frag"
            )
        );
        assert_eq!(
            parse("http://[::1]:80/").unwrap(),
            c("http", "::1", Some(80), "/", "", "")
        );
        assert_eq!(
            parse("file:///etc/hosts").unwrap(),
            c("file", "", None, "/etc/hosts", "", "")
        );
        assert_eq!(parse("mailto:a@b"), Err(Fail::InvalidData));
        assert_eq!(parse("/relative"), Err(Fail::InvalidData));
        assert_eq!(parse("http://u:p@host/"), Err(Fail::InvalidData));
        assert_eq!(parse("http://host:99999/"), Err(Fail::InvalidData));
        assert_eq!(parse("http://host:80:80/"), Err(Fail::InvalidData));
        assert_eq!(parse("http://a b/"), Err(Fail::InvalidData));
        assert_eq!(parse("http://h/?q=a b"), Err(Fail::InvalidData));
        assert_eq!(parse("http://h/%zz"), Err(Fail::InvalidData));
    }

    #[test]
    fn formats() {
        let u = c("http", "example.com", Some(80), "/a b", "x=1", "f g");
        assert_eq!(format(&u).unwrap(), "http://example.com:80/a%20b?x=1#f%20g");
        assert_eq!(format(&c("file", "", None, "", "", "")).unwrap(), "file://");
        assert_eq!(
            format(&c("http", "::1", Some(8), "", "", "")).unwrap(),
            "http://[::1]:8"
        );
        assert_eq!(
            format(&c("http", "h", Some(70000), "", "", "")),
            Err(Fail::InvalidInput)
        );
        assert_eq!(
            format(&c("", "h", None, "", "", "")),
            Err(Fail::InvalidInput)
        );
        assert_eq!(
            format(&c("http", "", None, "rel", "", "")),
            Err(Fail::InvalidInput)
        );
    }

    #[test]
    fn resolves() {
        let base = parse("http://a/b/c/d;p?q").unwrap();
        for (r, want) in [
            ("g", "http://a/b/c/g"),
            ("./g", "http://a/b/c/g"),
            ("g/", "http://a/b/c/g/"),
            ("/g", "http://a/g"),
            ("//g", "http://g"),
            ("?y", "http://a/b/c/d;p?y"),
            ("#s", "http://a/b/c/d;p?q#s"),
            ("../g", "http://a/b/g"),
            ("../../../g", "http://a/g"),
            ("g?y#s", "http://a/b/c/g?y#s"),
            ("", "http://a/b/c/d;p?q"),
        ] {
            let got = resolve(&base, r).unwrap();
            assert_eq!(format(&got).unwrap(), want, "{r}");
        }
        assert_eq!(resolve(&base, "http://u@x/"), Err(Fail::InvalidData));
    }

    #[test]
    fn queries() {
        let e = parse_query("a=1&b&a=2&&c=%20+x", None).unwrap();
        assert_eq!(
            e,
            [("a", "1"), ("b", ""), ("a", "2"), ("c", "  x")]
                .map(|(k, v)| (String::from(k), String::from(v)))
        );
        assert_eq!(parse_query("a=1&b=2", Some(1)), Err(Fail::LimitExceeded));
        assert_eq!(parse_query("a=1", Some(-1)), Err(Fail::InvalidInput));
        assert_eq!(parse_query("a=%zz", None), Err(Fail::InvalidData));
        assert_eq!(
            format_query(&[("a b", "c&d"), ("é", "")]),
            "a+b=c%26d&%C3%A9="
        );
        assert_eq!(parse_query("", None).unwrap(), []);
    }
}
