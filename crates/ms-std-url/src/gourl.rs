//! URL parsing and escaping over byte vectors, because strings may hold invalid UTF-8 after
//! unescaping.

use alloc::vec::Vec;

pub type S = Vec<u8>;

const UPPERHEX: &[u8; 16] = b"0123456789ABCDEF";

fn ishex(c: u8) -> bool {
    c.is_ascii_hexdigit()
}

fn unhex(c: u8) -> u8 {
    match c {
        b'0'..=b'9' => c - b'0',
        b'a'..=b'f' => c - b'a' + 10,
        b'A'..=b'F' => c - b'A' + 10,
        _ => 0,
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Enc {
    Path,
    PathSegment,
    Host,
    Zone,
    UserPassword,
    QueryComponent,
    Fragment,
}

pub struct Bad;

fn should_escape(c: u8, mode: Enc) -> bool {
    if c.is_ascii_alphanumeric() {
        return false;
    }
    if matches!(mode, Enc::Host | Enc::Zone)
        && matches!(
            c,
            b'!' | b'$'
                | b'&'
                | b'\''
                | b'('
                | b')'
                | b'*'
                | b'+'
                | b','
                | b';'
                | b'='
                | b':'
                | b'['
                | b']'
                | b'<'
                | b'>'
                | b'"'
        )
    {
        return false;
    }
    match c {
        b'-' | b'_' | b'.' | b'~' => return false,
        b'$' | b'&' | b'+' | b',' | b'/' | b':' | b';' | b'=' | b'?' | b'@' => match mode {
            Enc::Path => return c == b'?',
            Enc::PathSegment => return matches!(c, b'/' | b';' | b',' | b'?'),
            Enc::UserPassword => return matches!(c, b'@' | b'/' | b'?' | b':'),
            Enc::QueryComponent => return true,
            Enc::Fragment => return false,
            _ => {}
        },
        _ => {}
    }
    if mode == Enc::Fragment && matches!(c, b'!' | b'(' | b')' | b'*') {
        return false;
    }
    true
}

pub fn unescape(s: &[u8], mode: Enc) -> Result<S, Bad> {
    let mut n = 0;
    let mut has_plus = false;
    let mut i = 0;
    while i < s.len() {
        match s[i] {
            b'%' => {
                n += 1;
                if i + 2 >= s.len() || !ishex(s[i + 1]) || !ishex(s[i + 2]) {
                    return Err(Bad);
                }
                if mode == Enc::Host && unhex(s[i + 1]) < 8 && &s[i..i + 3] != b"%25" {
                    return Err(Bad);
                }
                if mode == Enc::Zone {
                    let v = unhex(s[i + 1]) << 4 | unhex(s[i + 2]);
                    if &s[i..i + 3] != b"%25" && v != b' ' && should_escape(v, Enc::Host) {
                        return Err(Bad);
                    }
                }
                i += 3;
            }
            b'+' => {
                has_plus = mode == Enc::QueryComponent;
                i += 1;
            }
            c => {
                if matches!(mode, Enc::Host | Enc::Zone) && c < 0x80 && should_escape(c, mode) {
                    return Err(Bad);
                }
                i += 1;
            }
        }
    }
    if n == 0 && !has_plus {
        return Ok(s.to_vec());
    }
    let mut t = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        match s[i] {
            b'%' => {
                t.push(unhex(s[i + 1]) << 4 | unhex(s[i + 2]));
                i += 2;
            }
            b'+' => t.push(if mode == Enc::QueryComponent {
                b' '
            } else {
                b'+'
            }),
            c => t.push(c),
        }
        i += 1;
    }
    Ok(t)
}

pub fn escape(s: &[u8], mode: Enc) -> S {
    let mut t = Vec::with_capacity(s.len());
    for &c in s {
        if c == b' ' && mode == Enc::QueryComponent {
            t.push(b'+');
        } else if should_escape(c, mode) {
            t.extend_from_slice(&[
                b'%',
                UPPERHEX[(c >> 4) as usize],
                UPPERHEX[(c & 15) as usize],
            ]);
        } else {
            t.push(c);
        }
    }
    t
}

#[derive(Clone, Default)]
pub struct Userinfo {
    username: S,
    password: S,
    password_set: bool,
}

impl Userinfo {
    fn render(&self) -> S {
        let mut s = escape(&self.username, Enc::UserPassword);
        if self.password_set {
            s.push(b':');
            s.extend(escape(&self.password, Enc::UserPassword));
        }
        s
    }
}

#[derive(Clone, Default)]
pub struct Url {
    pub scheme: S,
    pub opaque: S,
    pub user: Option<Userinfo>,
    pub host: S,
    pub path: S,
    pub raw_path: S,
    pub omit_host: bool,
    pub force_query: bool,
    pub raw_query: S,
    pub fragment: S,
    pub raw_fragment: S,
}

fn cut(s: &[u8], sep: u8) -> (&[u8], Option<&[u8]>) {
    match s.iter().position(|&b| b == sep) {
        Some(i) => (&s[..i], Some(&s[i + 1..])),
        None => (s, None),
    }
}

fn contains(s: &[u8], c: u8) -> bool {
    s.contains(&c)
}

fn get_scheme(raw: &[u8]) -> Result<(S, &[u8]), Bad> {
    for (i, &c) in raw.iter().enumerate() {
        match c {
            b'a'..=b'z' | b'A'..=b'Z' => {}
            b'0'..=b'9' | b'+' | b'-' | b'.' => {
                if i == 0 {
                    return Ok((Vec::new(), raw));
                }
            }
            b':' => {
                if i == 0 {
                    return Err(Bad);
                }
                return Ok((raw[..i].to_vec(), &raw[i + 1..]));
            }
            _ => return Ok((Vec::new(), raw)),
        }
    }
    Ok((Vec::new(), raw))
}

fn has_ctl(s: &[u8]) -> bool {
    s.iter().any(|&b| b < b' ' || b == 0x7f)
}

/// `url.Parse`.
pub fn parse(raw: &[u8]) -> Result<Url, Bad> {
    let (u, frag) = cut(raw, b'#');
    let mut url = parse_inner(u, false)?;
    match frag {
        Some(f) if !f.is_empty() => url.set_fragment(f)?,
        _ => {}
    }
    Ok(url)
}

fn parse_inner(raw: &[u8], via_request: bool) -> Result<Url, Bad> {
    if has_ctl(raw) {
        return Err(Bad);
    }
    if raw.is_empty() && via_request {
        return Err(Bad);
    }
    let mut url = Url::default();
    if raw == b"*" {
        url.path = b"*".to_vec();
        return Ok(url);
    }
    let (scheme, mut rest) = get_scheme(raw)?;
    url.scheme = scheme.to_ascii_lowercase();
    if rest.ends_with(b"?") && rest.iter().filter(|&&b| b == b'?').count() == 1 {
        url.force_query = true;
        rest = &rest[..rest.len() - 1];
    } else {
        let (r, q) = cut(rest, b'?');
        rest = r;
        url.raw_query = q.unwrap_or(&[]).to_vec();
    }
    if !rest.starts_with(b"/") {
        if !url.scheme.is_empty() {
            url.opaque = rest.to_vec();
            return Ok(url);
        }
        if via_request {
            return Err(Bad);
        }
        let (segment, _) = cut(rest, b'/');
        if contains(segment, b':') {
            return Err(Bad);
        }
    }
    if (!url.scheme.is_empty() || !via_request && !rest.starts_with(b"///"))
        && rest.starts_with(b"//")
    {
        let mut authority = &rest[2..];
        rest = &[];
        if let Some(i) = authority.iter().position(|&b| b == b'/') {
            rest = &authority[i..];
            authority = &authority[..i];
        }
        let (user, host) = parse_authority(authority)?;
        url.user = user;
        url.host = host;
    } else if !url.scheme.is_empty() && rest.starts_with(b"/") {
        url.omit_host = true;
    }
    url.set_path(rest)?;
    Ok(url)
}

fn rfind(s: &[u8], c: u8) -> Option<usize> {
    s.iter().rposition(|&b| b == c)
}

fn parse_authority(authority: &[u8]) -> Result<(Option<Userinfo>, S), Bad> {
    let i = rfind(authority, b'@');
    let host = parse_host(match i {
        None => authority,
        Some(i) => &authority[i + 1..],
    })?;
    let Some(i) = i else {
        return Ok((None, host));
    };
    let userinfo = &authority[..i];
    if !valid_userinfo(userinfo) {
        return Err(Bad);
    }
    let user = match cut(userinfo, b':') {
        (name, None) => Userinfo {
            username: unescape(name, Enc::UserPassword)?,
            ..Userinfo::default()
        },
        (name, Some(pass)) => Userinfo {
            username: unescape(name, Enc::UserPassword)?,
            password: unescape(pass, Enc::UserPassword)?,
            password_set: true,
        },
    };
    Ok((Some(user), host))
}

fn parse_host(host: &[u8]) -> Result<S, Bad> {
    if host.starts_with(b"[") {
        let i = rfind(host, b']').ok_or(Bad)?;
        if !valid_optional_port(&host[i + 1..]) {
            return Err(Bad);
        }
        if let Some(zone) = find(&host[..i], b"%25") {
            let mut out = unescape(&host[..zone], Enc::Host)?;
            out.extend(unescape(&host[zone..i], Enc::Zone)?);
            out.extend(unescape(&host[i..], Enc::Host)?);
            return Ok(out);
        }
    } else if let Some(i) = rfind(host, b':')
        && !valid_optional_port(&host[i..])
    {
        return Err(Bad);
    }
    unescape(host, Enc::Host)
}

fn find(s: &[u8], needle: &[u8]) -> Option<usize> {
    s.windows(needle.len()).position(|w| w == needle)
}

impl Url {
    fn set_path(&mut self, p: &[u8]) -> Result<(), Bad> {
        let path = unescape(p, Enc::Path)?;
        self.raw_path = if escape(&path, Enc::Path) == p {
            Vec::new()
        } else {
            p.to_vec()
        };
        self.path = path;
        Ok(())
    }

    fn set_fragment(&mut self, f: &[u8]) -> Result<(), Bad> {
        let frag = unescape(f, Enc::Fragment)?;
        self.raw_fragment = if escape(&frag, Enc::Fragment) == f {
            Vec::new()
        } else {
            f.to_vec()
        };
        self.fragment = frag;
        Ok(())
    }

    pub fn escaped_path(&self) -> S {
        if !self.raw_path.is_empty()
            && valid_encoded(&self.raw_path, Enc::Path)
            && let Ok(p) = unescape(&self.raw_path, Enc::Path)
            && p == self.path
        {
            return self.raw_path.clone();
        }
        if self.path == b"*" {
            return self.path.clone();
        }
        escape(&self.path, Enc::Path)
    }

    fn escaped_fragment(&self) -> S {
        if !self.raw_fragment.is_empty()
            && valid_encoded(&self.raw_fragment, Enc::Fragment)
            && let Ok(f) = unescape(&self.raw_fragment, Enc::Fragment)
            && f == self.fragment
        {
            return self.raw_fragment.clone();
        }
        escape(&self.fragment, Enc::Fragment)
    }

    /// `URL.String`.
    pub fn render(&self) -> S {
        let mut buf = Vec::new();
        if !self.scheme.is_empty() {
            buf.extend_from_slice(&self.scheme);
            buf.push(b':');
        }
        if !self.opaque.is_empty() {
            buf.extend_from_slice(&self.opaque);
        } else {
            if (!self.scheme.is_empty() || !self.host.is_empty() || self.user.is_some())
                && !(self.omit_host && self.host.is_empty() && self.user.is_none())
            {
                if !self.host.is_empty() || !self.path.is_empty() || self.user.is_some() {
                    buf.extend_from_slice(b"//");
                }
                if let Some(ui) = &self.user {
                    buf.extend(ui.render());
                    buf.push(b'@');
                }
                if !self.host.is_empty() {
                    buf.extend(escape(&self.host, Enc::Host));
                }
            }
            let path = self.escaped_path();
            if !path.is_empty() && path[0] != b'/' && !self.host.is_empty() {
                buf.push(b'/');
            }
            if buf.is_empty() && contains(cut(&path, b'/').0, b':') {
                buf.extend_from_slice(b"./");
            }
            buf.extend(path);
        }
        if self.force_query || !self.raw_query.is_empty() {
            buf.push(b'?');
            buf.extend_from_slice(&self.raw_query);
        }
        if !self.fragment.is_empty() {
            buf.push(b'#');
            buf.extend(self.escaped_fragment());
        }
        buf
    }

    /// `URL.ResolveReference`.
    pub fn resolve_reference(&self, r: &Url) -> Url {
        let mut url = r.clone();
        if r.scheme.is_empty() {
            url.scheme = self.scheme.clone();
        }
        if !r.scheme.is_empty() || !r.host.is_empty() || r.user.is_some() {
            let _ = url.set_path(&resolve_path(&r.escaped_path(), b""));
            return url;
        }
        if !r.opaque.is_empty() {
            url.user = None;
            url.host = Vec::new();
            url.path = Vec::new();
            return url;
        }
        if r.path.is_empty() && !r.force_query && r.raw_query.is_empty() {
            url.raw_query = self.raw_query.clone();
            if r.fragment.is_empty() {
                url.fragment = self.fragment.clone();
                url.raw_fragment = self.raw_fragment.clone();
            }
        }
        if r.path.is_empty() && !self.opaque.is_empty() {
            url.opaque = self.opaque.clone();
            url.user = None;
            url.host = Vec::new();
            url.path = Vec::new();
            return url;
        }
        url.host = self.host.clone();
        url.user = self.user.clone();
        let _ = url.set_path(&resolve_path(&self.escaped_path(), &r.escaped_path()));
        url
    }

    /// `URL.Hostname` and `URL.Port`.
    pub fn host_port(&self) -> (&[u8], &[u8]) {
        split_host_port(&self.host)
    }

    pub fn has_user(&self) -> bool {
        self.user.is_some()
    }
}

pub fn split_host_port(host_port: &[u8]) -> (&[u8], &[u8]) {
    let mut host = host_port;
    let mut port: &[u8] = &[];
    if let Some(colon) = rfind(host, b':')
        && valid_optional_port(&host[colon..])
    {
        port = &host[colon + 1..];
        host = &host[..colon];
    }
    if host.starts_with(b"[") && host.ends_with(b"]") && host.len() >= 2 {
        host = &host[1..host.len() - 1];
    }
    (host, port)
}

fn valid_encoded(s: &[u8], mode: Enc) -> bool {
    s.iter().all(|&c| match c {
        b'!' | b'$' | b'&' | b'\'' | b'(' | b')' | b'*' | b'+' | b',' | b';' | b'=' | b':'
        | b'@' | b'[' | b']' | b'%' => true,
        _ => !should_escape(c, mode),
    })
}

fn valid_optional_port(port: &[u8]) -> bool {
    match port.split_first() {
        None => true,
        Some((b':', digits)) => digits.iter().all(u8::is_ascii_digit),
        Some(_) => false,
    }
}

fn valid_userinfo(s: &[u8]) -> bool {
    // Go ranges over runes: any non-ASCII rune (or invalid byte) is rejected.
    s.iter().all(|&c| {
        c.is_ascii_alphanumeric()
            || matches!(
                c,
                b'-' | b'.'
                    | b'_'
                    | b':'
                    | b'~'
                    | b'!'
                    | b'$'
                    | b'&'
                    | b'\''
                    | b'('
                    | b')'
                    | b'*'
                    | b'+'
                    | b','
                    | b';'
                    | b'='
                    | b'%'
                    | b'@'
            )
    })
}

/// `resolvePath`.
pub fn resolve_path(base: &[u8], r: &[u8]) -> S {
    let full: S = if r.is_empty() {
        base.to_vec()
    } else if r[0] != b'/' {
        let i = rfind(base, b'/').map_or(0, |i| i + 1);
        let mut f = base[..i].to_vec();
        f.extend_from_slice(r);
        f
    } else {
        r.to_vec()
    };
    if full.is_empty() {
        return Vec::new();
    }
    let mut dst: S = alloc::vec![b'/'];
    let mut first = true;
    let mut remaining: &[u8] = &full;
    let mut elem: &[u8];
    loop {
        let (e, rest) = cut(remaining, b'/');
        elem = e;
        if elem == b"." {
            first = false;
        } else if elem == b".." {
            let str_ = dst[1..].to_vec();
            dst.clear();
            dst.push(b'/');
            match rfind(&str_, b'/') {
                None => first = true,
                Some(index) => dst.extend_from_slice(&str_[..index]),
            }
        } else {
            if !first {
                dst.push(b'/');
            }
            dst.extend_from_slice(elem);
            first = false;
        }
        match rest {
            Some(r) => remaining = r,
            None => break,
        }
    }
    if elem == b"." || elem == b".." {
        dst.push(b'/');
    }
    if dst.len() > 1 && dst[1] == b'/' {
        dst.remove(0);
    }
    dst
}

/// Stripped copy of `QueryUnescape`.
pub fn query_unescape(s: &[u8]) -> Result<S, Bad> {
    unescape(s, Enc::QueryComponent)
}

pub fn path_unescape(s: &[u8]) -> Result<S, Bad> {
    unescape(s, Enc::PathSegment)
}

pub fn query_escape(s: &[u8]) -> S {
    escape(s, Enc::QueryComponent)
}
