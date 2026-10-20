//! URLs of HTTP and WebSocket requests, over byte strings.

/// A parsed absolute URL with a host and no user info.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Url {
    /// Lowercase scheme.
    pub scheme: String,
    /// Host without brackets.
    pub host: String,
    /// Explicit port text (digits) or empty.
    pub port: String,
    /// Authority exactly as written (`host:port`, brackets kept).
    pub authority: String,
    /// Percent-encoded path as sent on the wire (never empty).
    pub path: String,
    /// Raw query text, without `?`.
    pub query: String,
    pub has_query: bool,
}

fn scheme_end(text: &str) -> Option<usize> {
    let mut chars = text.char_indices();
    let (_, first) = chars.next()?;
    if !first.is_ascii_alphabetic() {
        return None;
    }
    for (i, c) in chars {
        match c {
            ':' => return Some(i),
            c if c.is_ascii_alphanumeric() || "+-.".contains(c) => {}
            _ => return None,
        }
    }
    None
}

fn valid_escapes(s: &str) -> bool {
    let b = s.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            if i + 2 >= b.len() || !b[i + 1].is_ascii_hexdigit() || !b[i + 2].is_ascii_hexdigit() {
                return false;
            }
            i += 3;
        } else {
            i += 1;
        }
    }
    true
}

/// Characters allowed unescaped in an encoded path.
fn path_char(c: u8) -> bool {
    c.is_ascii_alphanumeric() || b"-_.~$&+,/:;=@%!'()*[]".contains(&c)
}

fn escape_path(decoded: &[u8]) -> String {
    let mut out = String::new();
    for &c in decoded {
        if c.is_ascii_alphanumeric() || b"-_.~$&+,/:;=@".contains(&c) {
            out.push(c as char);
        } else {
            out.push_str(&format!("%{c:02X}"));
        }
    }
    out
}

fn valid_host_text(host: &str) -> bool {
    host.bytes()
        .all(|b| b > 0x20 && b != 0x7f && !b"\\^`{|}#?/@".contains(&b) && b != b'%')
}

/// An http or https URL with a host, a valid port
/// and no user info.
pub fn parse(text: &str) -> Option<Url> {
    if text.bytes().any(|b| b < 0x20 || b == 0x7f) {
        return None;
    }
    let colon = scheme_end(text)?;
    let scheme = text[..colon].to_ascii_lowercase();
    if scheme != "http" && scheme != "https" {
        return None;
    }
    let rest = text[colon + 1..].strip_prefix("//")?;
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let authority = &rest[..end];
    let mut tail = &rest[end..];
    if authority.is_empty() || authority.contains('@') {
        return None;
    }
    if let Some(i) = tail.find('#') {
        tail = &tail[..i];
    }
    let (host, port) = split_authority(authority)?;
    if !port.bytes().all(|b| b.is_ascii_digit())
        || port.parse::<u32>().is_ok_and(|p| p > 65535)
        || port.len() > 9
    {
        return None;
    }
    let (raw_path, query, has_query) = match tail.split_once('?') {
        Some((p, q)) => (p, q, true),
        None => (tail, "", false),
    };
    if !valid_escapes(raw_path) {
        return None;
    }
    let path = if raw_path.bytes().all(path_char) {
        raw_path.to_string()
    } else {
        let decoded = super::target::unescape(raw_path)?;
        escape_path(&decoded)
    };
    let path = if path.is_empty() {
        "/".to_string()
    } else {
        path
    };
    Some(Url {
        scheme,
        host: host.to_string(),
        port: port.to_string(),
        authority: authority.to_string(),
        path,
        query: query.to_string(),
        has_query,
    })
}

/// Splits `host[:port]` (bracketed IPv6 allowed); `None` when malformed.
fn split_authority(authority: &str) -> Option<(&str, &str)> {
    if let Some(rest) = authority.strip_prefix('[') {
        let close = rest.find(']')?;
        let host = &rest[..close];
        let after = &rest[close + 1..];
        let port = match after {
            "" => "",
            p => p.strip_prefix(':')?,
        };
        if host.is_empty()
            || !host.bytes().all(|b| {
                b.is_ascii_hexdigit()
                    || b == b':'
                    || b == b'.'
                    || b == b'%'
                    || b.is_ascii_alphanumeric()
            })
        {
            return None;
        }
        return Some((host, port));
    }
    let (host, port) = match authority.rfind(':') {
        Some(i) => (&authority[..i], &authority[i + 1..]),
        None => (authority, ""),
    };
    if host.contains(':') || !valid_host_text(host) {
        return None;
    }
    Some((host, port))
}

impl Url {
    pub fn is_https(&self) -> bool {
        self.scheme == "https"
    }

    /// The port to dial.
    pub fn dial_port(&self) -> u16 {
        if self.port.is_empty() {
            if self.is_https() { 443 } else { 80 }
        } else {
            self.port.parse().unwrap_or(0)
        }
    }

    /// `host:port` for dialing, with IPv6 hosts bracketed.
    pub fn dial_address(&self) -> String {
        let port = self.dial_port();
        if self.host.contains(':') {
            format!("[{}]:{port}", self.host)
        } else {
            format!("{}:{port}", self.host)
        }
    }

    /// The request target (`RequestURI`).
    pub fn request_uri(&self) -> String {
        if self.has_query {
            format!("{}?{}", self.path, self.query)
        } else {
            self.path.clone()
        }
    }

    /// The URL as text (for redirects and `Referer`-free comparisons).
    pub fn text(&self) -> String {
        format!("{}://{}{}", self.scheme, self.authority, self.request_uri())
    }

    /// Whether two URLs share scheme and authority (case-insensitive).
    pub fn same_origin(&self, other: &Url) -> bool {
        self.scheme.eq_ignore_ascii_case(&other.scheme)
            && self.authority.eq_ignore_ascii_case(&other.authority)
    }

    /// Resolves a `Location` reference against this URL (RFC 3986).
    pub fn resolve(&self, reference: &str) -> Option<Url> {
        if reference.bytes().any(|b| b < 0x20 || b == 0x7f) {
            return None;
        }
        let reference = reference.split('#').next().unwrap_or("");
        if scheme_end(reference).is_some() {
            return parse(reference);
        }
        if let Some(rest) = reference.strip_prefix("//") {
            return parse(&format!("{}://{rest}", self.scheme));
        }
        let (path_part, query_part) = match reference.split_once('?') {
            Some((p, q)) => (p, Some(q)),
            None => (reference, None),
        };
        let merged = if path_part.is_empty() {
            self.path.clone()
        } else if path_part.starts_with('/') {
            super::target::clean_keep(path_part)
        } else {
            let base = match self.path.rfind('/') {
                Some(i) => &self.path[..=i],
                None => "/",
            };
            super::target::clean_keep(&format!("{base}{path_part}"))
        };
        let query = match (query_part, path_part.is_empty()) {
            (Some(q), _) => Some(q.to_string()),
            (None, true) if self.has_query => Some(self.query.clone()),
            _ => None,
        };
        let mut text = format!("{}://{}{}", self.scheme, self.authority, merged);
        if let Some(q) = query {
            text.push('?');
            text.push_str(&q);
        }
        parse(&text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_http_urls() {
        let u = parse("HTTP://Example.com:8080/a b?x=1#frag").unwrap();
        assert_eq!(u.scheme, "http");
        assert_eq!(u.host, "Example.com");
        assert_eq!(u.port, "8080");
        assert_eq!(u.path, "/a%20b");
        assert_eq!(u.request_uri(), "/a%20b?x=1");
        assert_eq!(u.dial_address(), "Example.com:8080");
        let v6 = parse("https://[::1]:99/").unwrap();
        assert_eq!(v6.host, "::1");
        assert_eq!(v6.dial_address(), "[::1]:99");
        assert_eq!(parse("https://h").unwrap().dial_port(), 443);
        assert_eq!(parse("http://h").unwrap().request_uri(), "/");
        assert_eq!(parse("http://h?q").unwrap().request_uri(), "/?q");
        assert_eq!(parse("http://h/%41%2f").unwrap().path, "/%41%2f");
    }

    #[test]
    fn rejects_invalid_urls() {
        for bad in [
            "ftp://h/",
            "http:///x",
            "http://u@h/",
            "http://h@/",
            "http://%41/",
            "http://exa mple/",
            "http://h:99999/",
            "http://h:ab/",
            "//h/",
            "h/x",
            "http://h/%zz",
            "http://h /",
            "http://h/\u{1}",
            "",
        ] {
            assert!(parse(bad).is_none(), "{bad}");
        }
    }

    #[test]
    fn resolves_references() {
        let base = parse("http://h/a/b/c?q=1").unwrap();
        assert_eq!(base.resolve("/x").unwrap().text(), "http://h/x");
        assert_eq!(base.resolve("d").unwrap().text(), "http://h/a/b/d");
        assert_eq!(base.resolve("../d").unwrap().text(), "http://h/a/d");
        assert_eq!(base.resolve("?z").unwrap().text(), "http://h/a/b/c?z");
        assert_eq!(base.resolve("//o/p").unwrap().text(), "http://o/p");
        assert_eq!(base.resolve("https://o/p#f").unwrap().text(), "https://o/p");
        assert!(base.resolve("ftp://o/").is_none());
        assert_eq!(base.resolve("./").unwrap().text(), "http://h/a/b/");
    }
}
