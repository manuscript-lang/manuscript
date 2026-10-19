//! Lexical path helpers matching Go's `path/filepath` on Unix.
use alloc::vec::Vec;

/// `filepath.Clean`.
pub fn clean(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return alloc::vec![b'.'];
    }
    let rooted = path[0] == b'/';
    let mut out: Vec<u8> = Vec::with_capacity(path.len());
    let n = path.len();
    let (mut r, mut dotdot) = (0, 0);
    if rooted {
        out.push(b'/');
        r = 1;
        dotdot = 1;
    }
    while r < n {
        if path[r] == b'/' || (path[r] == b'.' && (r + 1 == n || path[r + 1] == b'/')) {
            r += 1;
        } else if path[r] == b'.' && path[r + 1] == b'.' && (r + 2 == n || path[r + 2] == b'/') {
            r += 2;
            if out.len() > dotdot {
                let mut w = out.len() - 1;
                while w > dotdot && out[w] != b'/' {
                    w -= 1;
                }
                out.truncate(w);
            } else if !rooted {
                if !out.is_empty() {
                    out.push(b'/');
                }
                out.extend_from_slice(b"..");
                dotdot = out.len();
            }
        } else {
            if (rooted && out.len() != 1) || (!rooted && !out.is_empty()) {
                out.push(b'/');
            }
            while r < n && path[r] != b'/' {
                out.push(path[r]);
                r += 1;
            }
        }
    }
    if out.is_empty() {
        out.push(b'.');
    }
    out
}

/// `filepath.Join` of two elements.
pub fn join(a: &[u8], b: &[u8]) -> Vec<u8> {
    if a.is_empty() {
        return if b.is_empty() { Vec::new() } else { clean(b) };
    }
    if b.is_empty() {
        return clean(a);
    }
    let mut v = Vec::with_capacity(a.len() + b.len() + 1);
    v.extend_from_slice(a);
    v.push(b'/');
    v.extend_from_slice(b);
    clean(&v)
}

/// `filepath.Base`.
pub fn base(path: &[u8]) -> &[u8] {
    if path.is_empty() {
        return b".";
    }
    let mut p = path;
    while p.len() > 1 && p[p.len() - 1] == b'/' {
        p = &p[..p.len() - 1];
    }
    if p == b"/" {
        return b"/";
    }
    match p.iter().rposition(|&c| c == b'/') {
        Some(i) => &p[i + 1..],
        None => p,
    }
}

/// `filepath.Dir`.
pub fn dir(path: &[u8]) -> Vec<u8> {
    let i = path.iter().rposition(|&c| c == b'/').map_or(0, |i| i + 1);
    let d = &path[..i];
    let mut d = d;
    while d.len() > 1 && d[d.len() - 1] == b'/' {
        d = &d[..d.len() - 1];
    }
    let cleaned = clean(d);
    if cleaned == b"." && i > 0 && path[0] == b'/' {
        alloc::vec![b'/']
    } else {
        cleaned
    }
}

pub fn is_abs(path: &[u8]) -> bool {
    path.first() == Some(&b'/')
}

/// `os.basename`, the name `os.Stat` reports for a path.
pub fn stat_name(path: &[u8]) -> &[u8] {
    let mut end = path.len();
    while end > 1 && path[end - 1] == b'/' {
        end -= 1;
    }
    let p = &path[..end];
    match p[..p.len().saturating_sub(1)]
        .iter()
        .rposition(|&c| c == b'/')
    {
        Some(i) => &p[i + 1..],
        None => p,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_go_filepath() {
        let cases: &[(&str, &str)] = &[
            ("", "."),
            ("a/c", "a/c"),
            ("a//c", "a/c"),
            ("a/c/.", "a/c"),
            ("a/c/b/..", "a/c"),
            ("/../a/c", "/a/c"),
            ("../../x", "../../x"),
            ("a/../..", ".."),
            ("/", "/"),
            ("//a", "/a"),
            ("a/./b/../../c/", "c"),
        ];
        for (input, want) in cases {
            assert_eq!(clean(input.as_bytes()), want.as_bytes(), "clean({input})");
        }
        assert_eq!(base(b"/a/b/"), b"b");
        assert_eq!(base(b"/"), b"/");
        assert_eq!(base(b""), b".");
        assert_eq!(dir(b"/a/b"), b"/a");
        assert_eq!(dir(b"a"), b".");
        assert_eq!(dir(b"/a"), b"/");
        assert_eq!(stat_name(b"/a/b/"), b"b");
        assert_eq!(stat_name(b"/"), b"/");
        assert_eq!(stat_name(b"x"), b"x");
        assert_eq!(join(b"/tmp", b"x/../y"), b"/tmp/y");
    }
}
