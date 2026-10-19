//! A cookie jar with the matching rules of Go's `net/http/cookiejar`.

use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug)]
struct Entry {
    name: String,
    value: String,
    quoted: bool,
    domain: String,
    path: String,
    secure: bool,
    host_only: bool,
    /// Unix seconds, or `None` for a session cookie.
    expires: Option<i64>,
    creation: u64,
}

/// One cookie of a `Set-Cookie` header.
#[derive(Clone, Debug, Default)]
struct SetCookie {
    name: String,
    value: String,
    quoted: bool,
    domain: String,
    path: String,
    secure: bool,
    max_age: i64,
    expires: Option<i64>,
}

#[derive(Default)]
pub struct Jar {
    /// Entries by registrable domain, then `domain;path;name`.
    entries: HashMap<String, HashMap<String, Entry>>,
    seq: u64,
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

fn trim(s: &str) -> &str {
    s.trim_matches(|c| c == ' ' || c == '\t')
}

fn token(name: &str) -> bool {
    super::headers::valid_name(name)
}

/// `parseCookieValue`: printable ASCII without `"`, `;`, `\`; optionally quoted.
fn cookie_value(raw: &str, allow_quote: bool) -> Option<(String, bool)> {
    let (inner, quoted) = match raw.strip_prefix('"').and_then(|r| r.strip_suffix('"')) {
        Some(inner) if allow_quote && raw.len() > 1 => (inner, true),
        _ => (raw, false),
    };
    inner
        .bytes()
        .all(|b| (0x20..0x7f).contains(&b) && b != b'"' && b != b';' && b != b'\\')
        .then(|| (inner.to_string(), quoted))
}

fn parse_month(s: &str) -> Option<i64> {
    const M: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    M.iter()
        .position(|m| m.eq_ignore_ascii_case(s))
        .map(|i| i as i64 + 1)
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// `time.Parse` with RFC1123 (`Mon, 02 Jan 2006 15:04:05 MST`) or the dashed
/// variant; zone abbreviations count as UTC offsets of zero.
fn parse_expires(text: &str) -> Option<i64> {
    let (_, rest) = text.split_once(", ")?;
    let mut parts = rest.split(' ');
    let date = parts.next()?;
    if !date.contains('-') {
        return parse_spaced(text);
    }
    let (time, zone) = (parts.next()?, parts.next()?);
    if parts.next().is_some() || zone.is_empty() || !zone.bytes().all(|b| b.is_ascii_alphabetic()) {
        return None;
    }
    let mut p = date.split('-');
    to_unix(p.next()?, p.next()?, p.next()?, time)
}

fn parse_spaced(text: &str) -> Option<i64> {
    let (_, rest) = text.split_once(", ")?;
    let mut p = rest.split(' ');
    let (d, m, y, time, zone) = (p.next()?, p.next()?, p.next()?, p.next()?, p.next()?);
    if p.next().is_some() || zone.is_empty() || !zone.bytes().all(|b| b.is_ascii_alphabetic()) {
        return None;
    }
    to_unix(d, m, y, time)
}

fn to_unix(d: &str, m: &str, y: &str, time: &str) -> Option<i64> {
    let day: i64 = d.parse().ok().filter(|d| (1..=31).contains(d))?;
    let month = parse_month(m)?;
    let year: i64 = y.parse().ok()?;
    if y.len() != 4 {
        return None;
    }
    let mut t = time.split(':');
    let (h, mi, s): (i64, i64, i64) = (
        t.next()?.parse().ok()?,
        t.next()?.parse().ok()?,
        t.next()?.parse().ok()?,
    );
    if t.next().is_some() || h > 23 || mi > 59 || s > 59 {
        return None;
    }
    Some(days_from_civil(year, month, day) * 86_400 + h * 3600 + mi * 60 + s)
}

fn parse_set_cookie(line: &str) -> Option<SetCookie> {
    let parts: Vec<&str> = trim(line).split(';').collect();
    if parts.len() == 1 && parts[0].is_empty() {
        return None;
    }
    let first = trim(parts[0]);
    let (name, value) = first.split_once('=')?;
    let name = trim(name);
    if !token(name) {
        return None;
    }
    let (value, quoted) = cookie_value(value, true)?;
    let mut c = SetCookie {
        name: name.to_string(),
        value,
        quoted,
        ..SetCookie::default()
    };
    for part in &parts[1..] {
        let part = trim(part);
        if part.is_empty() {
            continue;
        }
        let (attr, val) = part.split_once('=').unwrap_or((part, ""));
        let Some((val, _)) = cookie_value(val, false) else {
            continue;
        };
        match attr.to_ascii_lowercase().as_str() {
            "secure" => c.secure = true,
            "domain" => c.domain = val,
            "path" => c.path = val,
            "max-age" => {
                if let Ok(secs) = val.parse::<i64>()
                    && (secs == 0 || !val.starts_with('0'))
                {
                    c.max_age = if secs <= 0 { -1 } else { secs };
                }
            }
            "expires" => c.expires = parse_expires(&val),
            _ => {}
        }
    }
    Some(c)
}

fn is_ip(host: &str) -> bool {
    host.parse::<std::net::IpAddr>().is_ok()
}

fn has_dot_suffix(s: &str, suffix: &str) -> bool {
    s.len() > suffix.len()
        && s.ends_with(suffix)
        && s.as_bytes()[s.len() - suffix.len() - 1] == b'.'
}

/// The registrable domain used as the jar's bucket.
fn jar_key(host: &str) -> String {
    if is_ip(host) {
        return host.to_string();
    }
    let Some(suffix) = psl::suffix(host.as_bytes()) else {
        return host.to_string();
    };
    let suffix = std::str::from_utf8(suffix.as_bytes()).unwrap_or("");
    if suffix == host {
        return host.to_string();
    }
    let Some(i) = host.len().checked_sub(suffix.len()) else {
        return host.to_string();
    };
    if i == 0 || host.as_bytes()[i - 1] != b'.' {
        return host.to_string();
    }
    match host[..i - 1].rfind('.') {
        Some(dot) => host[dot + 1..].to_string(),
        None => host.to_string(),
    }
}

fn default_path(path: &str) -> String {
    if !path.starts_with('/') {
        return "/".into();
    }
    match path.rfind('/') {
        Some(0) | None => "/".into(),
        Some(i) => path[..i].into(),
    }
}

fn canonical_host(host: &str) -> String {
    host.trim_end_matches('.').to_ascii_lowercase()
}

impl Jar {
    pub fn new() -> Jar {
        Jar::default()
    }

    /// `SetCookies(u, cookies)` for the `Set-Cookie` lines of a response.
    pub fn set_cookies(&mut self, scheme: &str, host: &str, path: &str, lines: &[String]) {
        if scheme != "http" && scheme != "https" {
            return;
        }
        let host = canonical_host(host);
        let now = now();
        for line in lines {
            let Some(c) = parse_set_cookie(line) else {
                continue;
            };
            let Some(entry) = self.new_entry(&c, &host, path, now) else {
                continue;
            };
            let key = jar_key(&host);
            let id = format!("{};{};{}", entry.domain, entry.path, entry.name);
            let bucket = self.entries.entry(key).or_default();
            let remove = c.max_age < 0 || (c.max_age == 0 && c.expires.is_some_and(|e| e <= now));
            match (remove, bucket.get(&id)) {
                (true, _) => {
                    bucket.remove(&id);
                }
                (false, existing) => {
                    let mut entry = entry;
                    if let Some(old) = existing {
                        entry.creation = old.creation;
                    } else {
                        self.seq += 1;
                        entry.creation = self.seq;
                    }
                    bucket.insert(id, entry);
                }
            }
        }
    }

    fn new_entry(&mut self, c: &SetCookie, host: &str, path: &str, now: i64) -> Option<Entry> {
        let (domain, host_only) = domain_and_type(host, &c.domain)?;
        let cpath = if c.path.is_empty() || !c.path.starts_with('/') {
            default_path(path)
        } else {
            c.path.clone()
        };
        let expires = if c.max_age < 0 {
            Some(i64::MIN)
        } else if c.max_age > 0 {
            Some(now.saturating_add(c.max_age))
        } else {
            c.expires
        };
        Some(Entry {
            name: c.name.clone(),
            value: c.value.clone(),
            quoted: c.quoted,
            domain,
            path: cpath,
            secure: c.secure,
            host_only,
            expires,
            creation: 0,
        })
    }

    /// `Cookies(u)`: the `name=value` pairs to send, in Go's order.
    pub fn cookies(&mut self, scheme: &str, host: &str, path: &str) -> Vec<String> {
        if scheme != "http" && scheme != "https" {
            return Vec::new();
        }
        let host = canonical_host(host);
        let https = scheme == "https";
        let path = if path.is_empty() { "/" } else { path };
        let now = now();
        let key = jar_key(&host);
        let Some(bucket) = self.entries.get_mut(&key) else {
            return Vec::new();
        };
        bucket.retain(|_, e| e.expires.is_none_or(|x| x > now));
        let mut selected: Vec<&Entry> = bucket
            .values()
            .filter(|e| should_send(e, https, &host, path))
            .collect();
        selected.sort_by(|a, b| {
            b.path
                .len()
                .cmp(&a.path.len())
                .then(a.creation.cmp(&b.creation))
        });
        selected
            .into_iter()
            .map(|e| format!("{}={}", e.name, sanitize(&e.value, e.quoted)))
            .collect()
    }
}

fn sanitize(value: &str, quoted: bool) -> String {
    if quoted || value.contains(' ') || value.contains(',') {
        format!("\"{value}\"")
    } else {
        value.to_string()
    }
}

fn domain_and_type(host: &str, domain: &str) -> Option<(String, bool)> {
    if domain.is_empty() {
        return Some((host.to_string(), true));
    }
    if is_ip(host) {
        return (host == domain).then(|| (host.to_string(), true));
    }
    let domain = domain.strip_prefix('.').unwrap_or(domain);
    if domain.is_empty() || domain.starts_with('.') || domain.ends_with('.') {
        return None;
    }
    let domain = domain.to_ascii_lowercase();
    if let Some(suffix) = psl::suffix(domain.as_bytes()) {
        let suffix = std::str::from_utf8(suffix.as_bytes()).unwrap_or("");
        if !suffix.is_empty() && !has_dot_suffix(&domain, suffix) {
            return (host == domain).then(|| (host.to_string(), true));
        }
    }
    if host != domain && !has_dot_suffix(host, &domain) {
        return None;
    }
    Some((domain, false))
}

fn should_send(e: &Entry, https: bool, host: &str, path: &str) -> bool {
    let domain_ok = if e.host_only {
        host == e.domain
    } else {
        host == e.domain || has_dot_suffix(host, &e.domain) && !is_ip(host)
    };
    let path_ok = path == e.path
        || path.starts_with(&e.path)
            && (e.path.ends_with('/') || path.as_bytes().get(e.path.len()) == Some(&b'/'));
    domain_ok && path_ok && (https || !e.secure)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn set(j: &mut Jar, url: (&str, &str, &str), lines: &[&str]) {
        let lines: Vec<String> = lines.iter().map(|s| s.to_string()).collect();
        j.set_cookies(url.0, url.1, url.2, &lines);
    }

    /// Expected values were recorded from Go's `cookiejar` with the public suffix list.
    #[test]
    fn host_only_domain_path_and_secure() {
        let mut j = Jar::new();
        set(
            &mut j,
            ("http", "www.example.com", "/a/b"),
            &[
                "h=1",
                "d=2; Domain=example.com",
                "p=3; Path=/a",
                "s=4; Secure; Path=/",
            ],
        );
        assert_eq!(
            j.cookies("http", "www.example.com", "/a/b/c"),
            vec!["h=1", "d=2", "p=3"]
        );
        assert_eq!(
            j.cookies("https", "www.example.com", "/a/x"),
            vec!["h=1", "d=2", "p=3", "s=4"]
        );
        assert_eq!(j.cookies("http", "api.example.com", "/a/b"), vec!["d=2"]);
        assert!(j.cookies("http", "other.org", "/").is_empty());
        assert!(j.cookies("ftp", "www.example.com", "/").is_empty());
    }

    #[test]
    fn rejects_public_suffixes_and_foreign_domains() {
        let mut j = Jar::new();
        set(
            &mut j,
            ("http", "a.example.com", "/"),
            &[
                "x=1; Domain=com",
                "y=2; Domain=other.com",
                "z=3; Domain=.example.com",
            ],
        );
        assert_eq!(j.cookies("http", "a.example.com", "/"), vec!["z=3"]);
        assert!(j.cookies("http", "b.com", "/").is_empty());
        set(
            &mut j,
            ("http", "x.github.io", "/"),
            &["g=1; Domain=github.io", "h=2; Domain=x.github.io"],
        );
        assert_eq!(j.cookies("http", "x.github.io", "/"), vec!["h=2"]);
        assert!(j.cookies("http", "y.github.io", "/").is_empty());
    }

    #[test]
    fn max_age_expires_and_deletion() {
        let mut j = Jar::new();
        set(
            &mut j,
            ("http", "h.test", "/"),
            &[
                "a=1; Max-Age=100",
                "b=2; Max-Age=0",
                "c=3; Expires=Thu, 01 Jan 1970 00:00:01 GMT",
                "d=4; Expires=Fri, 01-Jan-2100 00:00:00 GMT",
                "e=5; Expires=Fri, 01 Jan 2100 00:00:00 GMT",
            ],
        );
        assert_eq!(j.cookies("http", "h.test", "/"), vec!["a=1", "d=4", "e=5"]);
        set(&mut j, ("http", "h.test", "/"), &["a=gone; Max-Age=-1"]);
        assert_eq!(j.cookies("http", "h.test", "/"), vec!["d=4", "e=5"]);
    }

    #[test]
    fn values_and_ordering() {
        let mut j = Jar::new();
        set(
            &mut j,
            ("http", "h.test", "/x/y"),
            &["q=\"a b\"", "r=a b", "bad name=1", "=2", "k=v; Path=/x/y/z"],
        );
        set(&mut j, ("http", "h.test", "/x/y/z/w"), &["deep=1"]);
        assert_eq!(
            j.cookies("http", "h.test", "/x/y/z/w"),
            vec!["k=v", "deep=1", "q=\"a b\"", "r=\"a b\""]
        );
        set(&mut j, ("http", "h.test", "/x/y"), &["q=again"]);
        assert_eq!(
            j.cookies("http", "h.test", "/x/y/z"),
            vec!["k=v", "deep=1", "q=again", "r=\"a b\""]
        );
        assert_eq!(default_path("/a/b"), "/a");
        assert_eq!(default_path("/a"), "/");
        assert_eq!(default_path("rel"), "/");
    }

    #[test]
    fn ip_hosts_only_match_exactly() {
        let mut j = Jar::new();
        set(
            &mut j,
            ("http", "127.0.0.1", "/"),
            &["a=1", "b=2; Domain=127.0.0.1", "c=3; Domain=0.0.1"],
        );
        assert_eq!(j.cookies("http", "127.0.0.1", "/"), vec!["a=1", "b=2"]);
    }
}
