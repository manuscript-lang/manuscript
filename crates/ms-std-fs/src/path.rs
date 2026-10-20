//! Path helpers over byte strings, built on `std::path::Path` so the separator, volume and
//! absolute-path rules are the host's. Results follow Go's `path/filepath` where `std` has the
//! same operation; `clean` is the one function `std` does not offer (it normalizes `.` and
//! repeated separators in `components` but never resolves `..`).
use crate::sys::{os_bytes, path_of};
use alloc::vec::Vec;
use std::path::{Component, PathBuf};

/// The separator written by `join` and `clean`.
pub const SEP: u8 = std::path::MAIN_SEPARATOR as u8;

/// Whether `c` separates path elements on this host.
pub fn is_sep(c: u8) -> bool {
    c.is_ascii() && std::path::is_separator(c as char)
}

/// `filepath.Clean`: the shortest equivalent path by lexical processing.
pub fn clean(path: &[u8]) -> Vec<u8> {
    let p = path_of(path);
    let mut out = PathBuf::new();
    // Normal components pushed after the root; only those can be undone by `..`.
    let mut depth = 0usize;
    for c in p.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir if depth > 0 => {
                out.pop();
                depth -= 1;
            }
            // Above the root there is nothing to go up to.
            Component::ParentDir if out.has_root() => {}
            Component::ParentDir => out.push(".."),
            Component::Normal(name) => {
                out.push(name);
                depth += 1;
            }
            Component::Prefix(_) | Component::RootDir => out.push(c.as_os_str()),
        }
    }
    if out.as_os_str().is_empty() {
        out.push(".");
    }
    os_bytes(out.as_os_str())
}

/// `filepath.Join` of two elements.
pub fn join(a: &[u8], b: &[u8]) -> Vec<u8> {
    if a.is_empty() {
        return if b.is_empty() { Vec::new() } else { clean(b) };
    }
    if b.is_empty() {
        return clean(a);
    }
    clean(&os_bytes(path_of(a).join(path_of(b)).as_os_str()))
}

/// `filepath.Base`: the last element, `.` for an empty path, the root for a root.
pub fn base(path: &[u8]) -> Vec<u8> {
    path_of(path)
        .components()
        .next_back()
        .map_or_else(|| b".".to_vec(), |c| os_bytes(c.as_os_str()))
}

/// `filepath.Dir`: everything but the last element, cleaned.
pub fn dir(path: &[u8]) -> Vec<u8> {
    let p = path_of(path);
    let parent = p
        .parent()
        .map_or_else(|| path.to_vec(), |q| os_bytes(q.as_os_str()));
    clean(&parent)
}

/// `filepath.IsAbs`.
pub fn is_abs(path: &[u8]) -> bool {
    path_of(path).is_absolute()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
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
            ("../a/..", ".."),
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
        assert_eq!(dir(b"/"), b"/");
        assert_eq!(join(b"/tmp", b"x/../y"), b"/tmp/y");
        assert!(is_abs(b"/a") && !is_abs(b"a"));
        assert!(is_sep(b'/') && !is_sep(b'\\'));
    }

    #[cfg(windows)]
    #[test]
    fn follows_windows_rules() {
        let cases: &[(&str, &str)] = &[
            ("", "."),
            ("a/c", "a\\c"),
            ("c:/a//b/../c", "c:\\a\\c"),
            ("C:\\", "C:\\"),
            ("/../a", "\\a"),
        ];
        for (input, want) in cases {
            assert_eq!(clean(input.as_bytes()), want.as_bytes(), "clean({input})");
        }
        assert_eq!(base(b"C:\\a\\b\\"), b"b");
        assert_eq!(dir(b"C:\\a\\b"), b"C:\\a");
        assert_eq!(dir(b"a"), b".");
        assert_eq!(join(b"C:\\tmp", b"x/../y"), b"C:\\tmp\\y");
        assert!(is_abs(b"C:\\x") && is_abs(b"c:/x") && is_abs(b"\\\\h\\s\\x"));
        assert!(!is_abs(b"\\x") && !is_abs(b"C:x") && !is_abs(b"x"));
        assert!(is_sep(b'/') && is_sep(b'\\'));
    }
}
