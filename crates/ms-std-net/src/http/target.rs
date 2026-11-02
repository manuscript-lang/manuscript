//! Request targets: percent-decoding and the path normalization of the server.

/// A request target split into the routable path and raw query.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Target {
    /// Decoded, cleaned path (never climbs above the root).
    pub path: String,
    /// Raw query text without the `?`.
    pub query: String,
    /// Host of an absolute-form target.
    pub host: Option<String>,
}

/// Why a target was refused; the text is the body of the 400 answer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BadTarget(pub &'static str);

fn hex(b: u8) -> Option<u8> {
    (b as char).to_digit(16).map(|d| d as u8)
}

/// Percent-decodes `raw`; `None` when an escape is malformed.
pub fn unescape(raw: &str) -> Option<Vec<u8>> {
    let b = raw.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            let hi = hex(*b.get(i + 1)?)?;
            let lo = hex(*b.get(i + 2)?)?;
            out.push(hi << 4 | lo);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    Some(out)
}

/// `path.Clean` keeping a trailing slash of the input (except for the root).
pub fn clean(path: &str) -> String {
    let rooted = path.starts_with('/');
    let mut stack: Vec<&str> = Vec::new();
    for seg in path.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                if stack.last().is_some_and(|s| *s != "..") {
                    stack.pop();
                } else if !rooted {
                    stack.push("..");
                }
            }
            s => stack.push(s),
        }
    }
    let mut out = String::new();
    if rooted {
        out.push('/');
    }
    out.push_str(&stack.join("/"));
    if out.is_empty() {
        out.push('.');
    }
    if path.ends_with('/') && out != "/" {
        out.push('/');
    }
    out
}

/// `clean` for a request path that must stay encoded: dot segments are
/// removed but the text is not decoded.
pub fn clean_keep(path: &str) -> String {
    clean(path)
}

/// Splits and normalizes the target of a request line.
pub fn parse(target: &str) -> Result<Target, BadTarget> {
    if target.bytes().any(|b| b < 0x20 || b == 0x7f || b == b' ') {
        return Err(BadTarget("Bad Request"));
    }
    let mut host = None;
    let rest = if let Some(after) = target
        .strip_prefix("http://")
        .or_else(|| target.strip_prefix("https://"))
    {
        let end = after.find(['/', '?']).unwrap_or(after.len());
        host = Some(after[..end].to_string());
        &after[end..]
    } else {
        target
    };
    let rest = rest.split('#').next().unwrap_or("");
    let (raw_path, query) = match rest.split_once('?') {
        Some((p, q)) => (p, q),
        None => (rest, ""),
    };
    let raw_path = if raw_path.is_empty() && host.is_some() {
        "/"
    } else {
        raw_path
    };
    if raw_path == "*" {
        return Ok(Target {
            path: "*".into(),
            query: query.into(),
            host,
        });
    }
    let decoded = unescape(raw_path).ok_or(BadTarget("Bad Request"))?;
    let path = String::from_utf8(decoded).map_err(|_| BadTarget("invalid UTF-8 URL"))?;
    if std::str::from_utf8(query.as_bytes()).is_err() {
        return Err(BadTarget("invalid UTF-8 URL"));
    }
    let lower = raw_path.to_ascii_lowercase();
    if lower.contains("%00") || lower.contains("%2f") || path.contains('\0') {
        return Err(BadTarget("invalid request path"));
    }
    let path = if path.starts_with('/') {
        clean(&path)
    } else {
        path
    };
    Ok(Target {
        path,
        query: query.into(),
        host,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleans_like_go() {
        assert_eq!(clean("/a/../b"), "/b");
        assert_eq!(clean("/../.."), "/");
        assert_eq!(clean("/a/./b/"), "/a/b/");
        assert_eq!(clean("//a///b"), "/a/b");
        assert_eq!(clean("/"), "/");
        assert_eq!(clean("a/.."), ".");
    }

    #[test]
    fn parses_targets() {
        let t = parse("/a%20b/../c?x=1&y=%2F").unwrap();
        assert_eq!(t.path, "/c");
        assert_eq!(t.query, "x=1&y=%2F");
        assert_eq!(parse("/a/%2e%2e/b").unwrap().path, "/b");
        assert_eq!(parse("/a%2Fb"), Err(BadTarget("invalid request path")));
        assert_eq!(parse("/a%00"), Err(BadTarget("invalid request path")));
        assert_eq!(parse("/%zz"), Err(BadTarget("Bad Request")));
        assert_eq!(parse("/%ff"), Err(BadTarget("invalid UTF-8 URL")));
        assert_eq!(parse("*").unwrap().path, "*");
        let t = parse("http://example.com:8080/p?q").unwrap();
        assert_eq!(
            (t.path.as_str(), t.query.as_str(), t.host.as_deref()),
            ("/p", "q", Some("example.com:8080"))
        );
        assert_eq!(parse("http://h").unwrap().path, "/");
        assert_eq!(parse("/dir/").unwrap().path, "/dir/");
        assert_eq!(parse("/é").unwrap().path, "/é");
    }
}
