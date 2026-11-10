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

/// Escapes the bytes of a path that cannot appear in a request target (spaces, controls and
/// non-ASCII), leaving existing percent escapes and delimiters alone so an escaped `/` stays one.
fn escape_path(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    for &c in raw.as_bytes() {
        if path_char(c) {
            out.push(c as char);
        } else {
            out.push_str(&format!("%{c:02X}"));
        }
    }
    out
}

/// Escapes the bytes of a query that cannot appear in a request target (spaces, non-ASCII and the
/// characters RFC 3986 excludes), leaving existing escapes and delimiters alone.
fn escape_query(query: &str) -> String {
    let mut out = String::with_capacity(query.len());
    for &c in query.as_bytes() {
        if c <= b' ' || c >= 0x7f || b"\"<>\\^`{|}".contains(&c) {
            out.push_str(&format!("%{c:02X}"));
        } else {
            out.push(c as char);
        }
    }
    out
}

fn valid_host_text(host: &str) -> bool {
    host.bytes()
        .all(|b| b > 0x20 && b != 0x7f && !b"\\^`{|}#?/@".contains(&b) && b != b'%')
}

/// RFC 3986 section 5.2.4 over an encoded path. Empty segments are significant,
/// and a final `/.` or `/..` leaves the slash that denotes a directory.
fn remove_dot_segments(mut input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    while !input.is_empty() {
        if let Some(rest) = input.strip_prefix("../") {
            input = rest;
        } else if let Some(rest) = input.strip_prefix("./") {
            input = rest;
        } else if input.starts_with("/./") {
            input = &input[2..];
        } else if input == "/." {
            input = "/";
        } else if input.starts_with("/../") || input == "/.." {
            input = if input == "/.." { "/" } else { &input[3..] };
            out.truncate(out.rfind('/').unwrap_or(0));
        } else if input == "." || input == ".." {
            break;
        } else {
            // Include the initial slash, but stop at the next slash. In `//`,
            // each slash therefore survives as a separate empty path segment.
            let skip = usize::from(input.starts_with('/'));
            let end = input[skip..].find('/').map_or(input.len(), |i| skip + i);
            out.push_str(&input[..end]);
            input = &input[end..];
        }
    }
    out
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
    let path = escape_path(raw_path);
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
        query: escape_query(query),
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
    if host.is_empty() || host.contains(':') || !valid_host_text(host) {
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
            let mut resolved = parse(reference)?;
            resolved.path = remove_dot_segments(&resolved.path);
            return Some(resolved);
        }
        if let Some(rest) = reference.strip_prefix("//") {
            let mut resolved = parse(&format!("{}://{rest}", self.scheme))?;
            resolved.path = remove_dot_segments(&resolved.path);
            return Some(resolved);
        }
        let (path_part, query_part) = match reference.split_once('?') {
            Some((p, q)) => (p, Some(q)),
            None => (reference, None),
        };
        let merged = if path_part.is_empty() {
            self.path.clone()
        } else if path_part.starts_with('/') {
            remove_dot_segments(path_part)
        } else {
            let base = match self.path.rfind('/') {
                Some(i) => &self.path[..=i],
                None => "/",
            };
            remove_dot_segments(&format!("{base}{path_part}"))
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
        for (input, path) in [
            ("http://h/a%2Fb c", "/a%2Fb%20c"),
            ("http://h/a%2Fb%20c", "/a%2Fb%20c"),
            ("http://h/a%3Ab c", "/a%3Ab%20c"),
            ("http://h/a%40b/\u{e9}", "/a%40b/%C3%A9"),
            ("http://h/%41 b", "/%41%20b"),
        ] {
            assert_eq!(parse(input).unwrap().path, path, "{input}");
        }
        // A query cannot carry a space or non-ASCII text onto the request line.
        assert_eq!(
            parse("http://h/a?b c&d=\u{fc}%41|\"")
                .unwrap()
                .request_uri(),
            "/a?b%20c&d=%C3%BC%41%7C%22"
        );
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
    fn rejects_empty_hosts_even_when_authority_contains_a_port() {
        for bad in [
            "http://:80/",
            "https://:443/",
            "http://:/",
            "https://:/",
            "http://:0?query",
        ] {
            assert!(parse(bad).is_none(), "{bad}");
        }
        let base = parse("http://example.com/base").unwrap();
        for bad in ["//:80/", "//:/", "http://:80/", "https://:443/"] {
            assert!(base.resolve(bad).is_none(), "{bad}");
        }
        for good in ["http://example.com:/", "https://[::1]:/"] {
            assert!(parse(good).is_some(), "{good}");
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

    #[test]
    fn resolves_rfc3986_normal_and_abnormal_examples() {
        // RFC 3986 sections 5.4.1 and 5.4.2. HTTP URLs omit fragments and use `/`
        // for an empty path; non-HTTP schemes and authority-free URLs are refused.
        let base = parse("http://a/b/c/d;p?q").unwrap();
        let examples = [
            ("g", "http://a/b/c/g"),
            ("./g", "http://a/b/c/g"),
            ("g/", "http://a/b/c/g/"),
            ("/g", "http://a/g"),
            ("//g", "http://g/"),
            ("?y", "http://a/b/c/d;p?y"),
            ("g?y", "http://a/b/c/g?y"),
            ("#s", "http://a/b/c/d;p?q"),
            ("g#s", "http://a/b/c/g"),
            ("g?y#s", "http://a/b/c/g?y"),
            (";x", "http://a/b/c/;x"),
            ("g;x", "http://a/b/c/g;x"),
            ("g;x?y#s", "http://a/b/c/g;x?y"),
            ("", "http://a/b/c/d;p?q"),
            (".", "http://a/b/c/"),
            ("./", "http://a/b/c/"),
            ("..", "http://a/b/"),
            ("../", "http://a/b/"),
            ("../g", "http://a/b/g"),
            ("../..", "http://a/"),
            ("../../", "http://a/"),
            ("../../g", "http://a/g"),
            ("../../../g", "http://a/g"),
            ("../../../../g", "http://a/g"),
            ("/./g", "http://a/g"),
            ("/../g", "http://a/g"),
            ("g.", "http://a/b/c/g."),
            (".g", "http://a/b/c/.g"),
            ("g..", "http://a/b/c/g.."),
            ("..g", "http://a/b/c/..g"),
            ("./../g", "http://a/b/g"),
            ("./g/.", "http://a/b/c/g/"),
            ("g/./h", "http://a/b/c/g/h"),
            ("g/../h", "http://a/b/c/h"),
            ("g;x=1/./y", "http://a/b/c/g;x=1/y"),
            ("g;x=1/../y", "http://a/b/c/y"),
            ("g?y/./x", "http://a/b/c/g?y/./x"),
            ("g?y/../x", "http://a/b/c/g?y/../x"),
            ("g#s/./x", "http://a/b/c/g"),
            ("g#s/../x", "http://a/b/c/g"),
        ];
        for (reference, expected) in examples {
            assert_eq!(
                base.resolve(reference).unwrap().text(),
                expected,
                "{reference}"
            );
        }
        for unsupported in ["g:h", "http:g"] {
            assert!(base.resolve(unsupported).is_none(), "{unsupported}");
        }
    }

    #[test]
    fn redirect_resolution_preserves_encoded_path_structure() {
        let base = parse("http://a/b/c/d;p?q").unwrap();
        for (reference, expected) in [
            ("/a/.", "http://a/a/"),
            ("/a/b/..", "http://a/a/"),
            ("/a//b", "http://a/a//b"),
            ("g//h", "http://a/b/c/g//h"),
            ("/a///b/../c", "http://a/a///c"),
            ("/a//..", "http://a/a/"),
            ("/a//../c", "http://a/a/c"),
            ("http://a/b/./c", "http://a/b/c"),
            ("http://a/b/c/..", "http://a/b/"),
            ("http://a/b//./c/../d", "http://a/b//d"),
            ("//a/b/c/..", "http://a/b/"),
            ("../%2e%2e//g?x=/./y", "http://a/b/%2e%2e//g?x=/./y"),
            ("/a%2fb/%2E/../c", "http://a/a%2fb/c"),
            ("/a//b?", "http://a/a//b?"),
        ] {
            assert_eq!(
                base.resolve(reference).unwrap().text(),
                expected,
                "{reference}"
            );
        }
        let repeated = parse("http://a/b//c/d").unwrap();
        assert_eq!(repeated.resolve("../g").unwrap().text(), "http://a/b//g");
        // Parsing a URL for the first request does not normalize its path.
        let original = parse("http://a/b//./c/..").unwrap();
        assert_eq!(original.path, "/b//./c/..");
        assert_eq!(original.resolve("").unwrap().path, original.path);
        assert_eq!(original.resolve("?x").unwrap().path, original.path);
    }
}
