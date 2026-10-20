//! Lexical path helpers matching Go's `path/filepath` on Unix.
#[cfg(unix)]
pub use posix::{base, clean, dir, is_abs, join, stat_name};
#[cfg(windows)]
pub use win::{SEP, is_sep};
#[cfg(windows)]
pub use win::{base, clean, dir, is_abs, join, stat_name, volume_len};

/// Whether `c` separates path elements on this host.
#[cfg(unix)]
pub fn is_sep(c: u8) -> bool {
    c == b'/'
}

/// The separator written by `join` and `clean`.
#[cfg(unix)]
pub const SEP: u8 = b'/';

/// The length of a leading volume name; always `0` on Unix.
#[cfg(unix)]
pub fn volume_len(_: &[u8]) -> usize {
    0
}

/// Go's `path/filepath` on Unix.
pub mod posix {
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
            } else if path[r] == b'.' && path[r + 1] == b'.' && (r + 2 == n || path[r + 2] == b'/')
            {
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
}

/// Go's `path/filepath` on Windows: both separators, volume names, `\` output.
pub mod win {
    use alloc::vec::Vec;

    pub const SEP: u8 = b'\\';

    pub fn is_sep(c: u8) -> bool {
        c == b'/' || c == b'\\'
    }

    fn is_drive(b: &[u8]) -> bool {
        b.len() >= 2 && b[1] == b':' && b[0].is_ascii_alphabetic()
    }

    /// `volumeNameLen`: `C:`, `\\host\share`, and the `\\?\` / `\\.\` device prefixes.
    pub fn volume_len(p: &[u8]) -> usize {
        let l = p.len();
        if l < 2 {
            return 0;
        }
        if is_drive(p) {
            return 2;
        }
        if !(is_sep(p[0]) && is_sep(p[1])) {
            return 0;
        }
        // `\\?\C:` and `\\.\COM1` keep the next element as part of the volume.
        if l >= 4 && (p[2] == b'?' || p[2] == b'.') && is_sep(p[3]) {
            let mut n = 4;
            while n < l && !is_sep(p[n]) {
                n += 1;
            }
            return n;
        }
        if l >= 5 && !is_sep(p[2]) && p[2] != b'.' {
            let mut n = 3;
            while n < l - 1 {
                if is_sep(p[n]) {
                    n += 1;
                    if !is_sep(p[n]) {
                        if p[n] == b'.' {
                            break;
                        }
                        while n < l && !is_sep(p[n]) {
                            n += 1;
                        }
                        return n;
                    }
                    break;
                }
                n += 1;
            }
        }
        0
    }

    /// `filepath.Clean`.
    pub fn clean(original: &[u8]) -> Vec<u8> {
        let vol = volume_len(original);
        let path = &original[vol..];
        let to_slash = |v: &mut Vec<u8>| {
            v.iter_mut().for_each(|c| {
                if *c == b'/' {
                    *c = SEP
                }
            })
        };
        if path.is_empty() {
            let mut out = original.to_vec();
            if vol > 1 && is_sep(original[0]) && is_sep(original[1]) {
                to_slash(&mut out);
                return out;
            }
            out.push(b'.');
            to_slash(&mut out);
            return out;
        }
        let rooted = is_sep(path[0]);
        let n = path.len();
        let mut out: Vec<u8> = Vec::with_capacity(n);
        let (mut r, mut dotdot) = (0, 0);
        if rooted {
            out.push(SEP);
            r = 1;
            dotdot = 1;
        }
        while r < n {
            if is_sep(path[r]) || (path[r] == b'.' && (r + 1 == n || is_sep(path[r + 1]))) {
                r += 1;
            } else if path[r] == b'.' && path[r + 1] == b'.' && (r + 2 == n || is_sep(path[r + 2]))
            {
                r += 2;
                if out.len() > dotdot {
                    let mut w = out.len() - 1;
                    while w > dotdot && !is_sep(out[w]) {
                        w -= 1;
                    }
                    out.truncate(w);
                } else if !rooted {
                    if !out.is_empty() {
                        out.push(SEP);
                    }
                    out.extend_from_slice(b"..");
                    dotdot = out.len();
                }
            } else {
                if (rooted && out.len() != 1) || (!rooted && !out.is_empty()) {
                    out.push(SEP);
                }
                // A `:` in the first element of a relative path would read as a drive.
                if out.is_empty() && vol == 0 && r != 0 {
                    let mut i = r;
                    while i < n && !is_sep(path[i]) {
                        if path[i] == b':' {
                            out.extend_from_slice(b".\\");
                            break;
                        }
                        i += 1;
                    }
                }
                while r < n && !is_sep(path[r]) {
                    out.push(path[r]);
                    r += 1;
                }
            }
        }
        if out.is_empty() {
            out.push(b'.');
        }
        let mut full = original[..vol].to_vec();
        full.extend_from_slice(&out);
        to_slash(&mut full);
        full
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
        v.push(SEP);
        v.extend_from_slice(b);
        clean(&v)
    }

    /// `filepath.Base`.
    pub fn base(path: &[u8]) -> &[u8] {
        if path.is_empty() {
            return b".";
        }
        let mut p = path;
        while !p.is_empty() && is_sep(p[p.len() - 1]) {
            p = &p[..p.len() - 1];
        }
        p = &p[volume_len(p)..];
        if let Some(i) = p.iter().rposition(|&c| is_sep(c)) {
            p = &p[i + 1..];
        }
        if p.is_empty() { b"\\" } else { p }
    }

    /// `filepath.Dir`.
    pub fn dir(path: &[u8]) -> Vec<u8> {
        let vol = volume_len(path);
        let mut i = path.len();
        while i > vol && !is_sep(path[i - 1]) {
            i -= 1;
        }
        let d = clean(&path[vol..i]);
        if d == b"." && vol > 2 {
            return path[..vol].to_vec();
        }
        let mut out = path[..vol].to_vec();
        out.extend_from_slice(&d);
        out
    }

    /// `filepath.IsAbs`.
    pub fn is_abs(path: &[u8]) -> bool {
        let l = volume_len(path);
        if l == 0 {
            return false;
        }
        if path.len() >= 2 && is_sep(path[0]) && is_sep(path[1]) {
            return true;
        }
        path.get(l).is_some_and(|&c| is_sep(c))
    }

    /// `os.basename`, the name `os.Stat` reports for a path.
    pub fn stat_name(path: &[u8]) -> &[u8] {
        let mut p = path;
        while p.len() > 1 && is_sep(p[p.len() - 1]) {
            p = &p[..p.len() - 1];
        }
        if p.len() == 2 && p[1] == b':' {
            return b".";
        }
        if p.len() > 2 && p[1] == b':' {
            p = &p[2..];
        }
        match p.iter().rposition(|&c| is_sep(c)) {
            Some(j) => &p[j + 1..],
            None => p,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::posix::*;
    use super::win;

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

    #[test]
    fn matches_go_filepath_on_windows() {
        let cases: &[(&str, &str)] = &[
            ("", "."),
            ("a/c", "a\\c"),
            ("c:/a//b/../c", "c:\\a\\c"),
            ("C:", "C:."),
            ("C:\\", "C:\\"),
            ("c:a/../..", "c:.."),
            ("//host/share/x/..", "\\\\host\\share\\"),
            ("a/../c:", ".\\c:"),
            ("/../a", "\\a"),
        ];
        for (input, want) in cases {
            assert_eq!(
                win::clean(input.as_bytes()),
                want.as_bytes(),
                "clean({input})"
            );
        }
        assert_eq!(win::volume_len(b"\\\\host\\share\\x"), 12);
        assert_eq!(win::volume_len(b"\\\\?\\C:\\x"), 6);
        assert!(win::is_abs(b"C:\\x") && win::is_abs(b"c:/x") && win::is_abs(b"\\\\h\\s"));
        assert!(!win::is_abs(b"\\x") && !win::is_abs(b"C:x") && !win::is_abs(b"x"));
        assert_eq!(win::base(b"C:\\a\\b\\"), b"b");
        assert_eq!(win::base(b"C:\\"), b"\\");
        assert_eq!(win::dir(b"C:\\a\\b"), b"C:\\a");
        assert_eq!(win::dir(b"C:\\a"), b"C:\\");
        assert_eq!(win::dir(b"a"), b".");
        assert_eq!(win::join(b"C:\\tmp", b"x/../y"), b"C:\\tmp\\y");
        assert_eq!(win::stat_name(b"C:\\a\\b\\"), b"b");
        assert_eq!(win::stat_name(b"C:"), b".");
    }
}
