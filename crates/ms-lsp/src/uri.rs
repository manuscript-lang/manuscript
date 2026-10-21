//! `file:` and `manuscript-stdlib:` URIs, with Go `net/url` path escaping.

const STDLIB_SCHEME: &str = "manuscript-stdlib";

/// Whether the URI names an immutable standard-library document.
pub fn is_standard_library(uri: &str) -> bool {
    uri.starts_with("manuscript-stdlib:")
}

/// A parsed URI: only what the server consults.
#[derive(Debug, Default)]
pub struct Url {
    /// Lowercased scheme.
    pub scheme: String,
    /// Authority host, empty when absent.
    pub host: String,
    /// Percent-decoded path.
    pub path: String,
    /// Whether a `?` query is present.
    pub query: bool,
    /// Whether a `#` fragment is present.
    pub fragment: bool,
}

/// Parses a URI the way `url.Parse` does for the shapes editors send.
pub fn parse(raw: &str) -> Option<Url> {
    let mut url = Url::default();
    let mut rest = raw;
    let colon = rest.find(':');
    if let Some(colon) = colon {
        let scheme = &rest[..colon];
        let valid = scheme
            .chars()
            .next()
            .is_some_and(|c| c.is_ascii_alphabetic())
            && scheme
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'));
        if valid {
            url.scheme = scheme.to_ascii_lowercase();
            rest = &rest[colon + 1..];
        } else if scheme.is_empty() {
            return None;
        }
    }
    if let Some(at) = rest.find('#') {
        url.fragment = true;
        rest = &rest[..at];
    }
    if let Some(at) = rest.find('?') {
        url.query = true;
        rest = &rest[..at];
    }
    if let Some(after) = rest.strip_prefix("//") {
        let end = after.find('/').unwrap_or(after.len());
        url.host = after[..end].to_string();
        rest = &after[end..];
    } else if url.scheme.is_empty() && rest.contains(':') {
        let first = rest.split('/').next().unwrap_or("");
        if first.contains(':') {
            return None; // invalid first path segment in URL
        }
    }
    url.path = unescape(rest)?;
    Some(url)
}

fn unescape(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut at = 0;
    while at < bytes.len() {
        if bytes[at] == b'%' {
            let digits = text.get(at + 1..at + 3)?;
            out.push(u8::from_str_radix(digits, 16).ok()?);
            at += 3;
        } else {
            out.push(bytes[at]);
            at += 1;
        }
    }
    Some(String::from_utf8_lossy(&out).into_owned())
}

/// The path of a `file:` URI; any other URI is its own name.
pub fn filename(uri: &str) -> String {
    match parse(uri) {
        Some(url) if url.scheme == "file" => native_path(&url.host, url.path),
        _ => uri.to_string(),
    }
}

/// The host's spelling of a `file:` path: Windows names a drive `D:/dir`, not `/D:/dir`, and a
/// URI host is a UNC server.
fn native_path(host: &str, path: String) -> String {
    if !cfg!(windows) {
        return path;
    }
    if !host.is_empty() {
        return format!("//{host}{path}");
    }
    drive_path(&path).map_or(path.clone(), str::to_string)
}

/// `D:/dir` for `/D:/dir`.
fn drive_path(path: &str) -> Option<&str> {
    let rest = path.strip_prefix('/')?;
    let bytes = rest.as_bytes();
    (bytes.first()?.is_ascii_alphabetic()
        && bytes.get(1) == Some(&b':')
        && matches!(bytes.get(2), None | Some(b'/')))
    .then_some(rest)
}

/// Escapes a path as `url.URL.EscapedPath` does.
fn escape_path(path: &str) -> String {
    let mut out = String::with_capacity(path.len());
    for &b in path.as_bytes() {
        let keep = b.is_ascii_alphanumeric()
            || matches!(
                b,
                b'-' | b'_'
                    | b'.'
                    | b'~'
                    | b'$'
                    | b'&'
                    | b'+'
                    | b','
                    | b'/'
                    | b':'
                    | b';'
                    | b'='
                    | b'@'
            );
        if keep {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// The `file:` URI of an absolute path.
pub fn file_uri(path: &str) -> String {
    let mut p = path.replace('\\', "/");
    // `canonicalize` on Windows returns verbatim `\\?\` paths, which are not part of the name.
    if let Some(rest) = p.strip_prefix("//?/UNC/") {
        return format!("file://{}", escape_path(rest));
    }
    if let Some(rest) = p.strip_prefix("//?/") {
        p = rest.to_string();
    }
    if !p.starts_with('/') && p.as_bytes().get(1) == Some(&b':') {
        p.insert(0, '/');
    }
    format!("file://{}", escape_path(&p))
}

/// The URI of a bundled standard module such as `@std/io.ms`.
pub fn standard_library_uri(file: &str) -> String {
    let rest = file.strip_prefix("@std/").unwrap_or(file);
    format!("{STDLIB_SCHEME}:///{}", escape_path(rest))
}

/// The standard-library path (`/io.ms`) of a well-formed URI.
pub fn standard_library_path(uri: &str) -> Result<String, &'static str> {
    match parse(uri) {
        Some(url)
            if url.scheme == STDLIB_SCHEME
                && url.host.is_empty()
                && !url.query
                && !url.fragment =>
        {
            Ok(url.path)
        }
        _ => Err("invalid standard-library URI"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_round_trip() {
        for path in ["/tmp/new.ms", "/tmp/a b/é#.ms", "/x/100%/y.ms"] {
            assert_eq!(filename(&file_uri(path)), path, "{path}");
        }
        assert_eq!(file_uri("/tmp/a b.ms"), "file:///tmp/a%20b.ms");
        assert_eq!(file_uri(r"\\?\D:\a\b.ms"), "file:///D:/a/b.ms");
        assert_eq!(
            file_uri(r"\\?\UNC\host\share\b.ms"),
            "file://host/share/b.ms"
        );
    }

    #[test]
    fn drive_letters_lose_the_leading_slash() {
        assert_eq!(drive_path("/D:/a/b.ms"), Some("D:/a/b.ms"));
        assert_eq!(drive_path("/D:"), Some("D:"));
        assert_eq!(drive_path("/tmp/a.ms"), None);
        assert_eq!(drive_path("/Dx:/a"), None);
        assert_eq!(drive_path("D:/a"), None);
    }

    #[test]
    fn other_schemes_are_their_own_name() {
        assert_eq!(filename("untitled:Untitled-1"), "untitled:Untitled-1");
        assert_eq!(
            filename("manuscript-stdlib:///io.ms"),
            "manuscript-stdlib:///io.ms"
        );
    }

    #[test]
    fn standard_library_uris() {
        assert_eq!(
            standard_library_uri("@std/io.ms"),
            "manuscript-stdlib:///io.ms"
        );
        assert_eq!(
            standard_library_path("manuscript-stdlib:///io.ms").as_deref(),
            Ok("/io.ms")
        );
        assert!(standard_library_path("manuscript-stdlib://host/io.ms").is_err());
        assert!(standard_library_path("file:///io.ms").is_err());
    }
}
