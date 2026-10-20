//! Lexical path operations with the semantics of Go's `path/filepath` on Unix,
//! plus `EvalSymlinks` with Go's exact error behavior.

use crate::error::{ENOTDIR, ProjectError};

const SEP: u8 = b'/';

pub fn is_abs(path: &str) -> bool {
    path.starts_with('/') || (cfg!(windows) && windows_rooted(path))
}

/// A drive path (`C:\x`, `C:/x`) or a UNC / extended path (`\\host\share`, `\\?\C:\x`).
fn windows_rooted(path: &str) -> bool {
    let bytes = path.as_bytes();
    let drive = bytes.len() >= 3
        && bytes[0].is_ascii_alphabetic()
        && bytes[1] == b':'
        && matches!(bytes[2], b'\\' | b'/');
    drive || path.starts_with("\\\\")
}

/// `filepath.Clean`.
pub fn clean(path: &str) -> String {
    if path.is_empty() {
        return ".".to_string();
    }
    // Drive and UNC paths are not lexically cleaned: the Unix rules below do not apply to them.
    if cfg!(windows) && windows_rooted(path) {
        return path.to_string();
    }
    let rooted = is_abs(path);
    let mut out: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if out.last().is_some_and(|last| *last != "..") {
                    out.pop();
                } else if !rooted {
                    out.push("..");
                }
            }
            _ => out.push(part),
        }
    }
    let joined = out.join("/");
    match (rooted, joined.is_empty()) {
        (true, _) => format!("/{joined}"),
        (false, true) => ".".to_string(),
        (false, false) => joined,
    }
}

/// `filepath.Join`: ignores empty elements and cleans; all-empty gives "".
pub fn join(elements: &[&str]) -> String {
    let parts: Vec<&str> = elements.iter().copied().filter(|e| !e.is_empty()).collect();
    if parts.is_empty() {
        String::new()
    } else {
        clean(&parts.join("/"))
    }
}

/// `filepath.Dir`.
pub fn dir(path: &str) -> String {
    let split = path.rfind('/').map_or(0, |i| i + 1);
    let directory = clean(&path[..split]);
    if split == 0 {
        ".".to_string()
    } else {
        directory
    }
}

/// `filepath.Base`.
pub fn base(path: &str) -> String {
    if path.is_empty() {
        return ".".to_string();
    }
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return "/".to_string();
    }
    match trimmed.rfind('/') {
        Some(i) => trimmed[i + 1..].to_string(),
        None => trimmed.to_string(),
    }
}

/// `filepath.Ext`: the suffix beginning at the final dot of the last element.
pub fn ext(path: &str) -> &str {
    let bytes = path.as_bytes();
    let mut i = bytes.len();
    while i > 0 && bytes[i - 1] != SEP {
        i -= 1;
        if bytes[i] == b'.' {
            return &path[i..];
        }
    }
    ""
}

/// `filepath.Abs`.
pub fn abs(path: &str) -> Result<String, ProjectError> {
    if is_abs(path) {
        return Ok(clean(path));
    }
    let wd = std::env::current_dir().map_err(|e| ProjectError::path("getwd", "", &e))?;
    Ok(join(&[&wd.to_string_lossy(), path]))
}

/// `filepath.Rel`.
pub fn rel(basepath: &str, targpath: &str) -> Result<String, ProjectError> {
    let fail = || ProjectError::msg(format!("Rel: can't make {targpath} relative to {basepath}"));
    let base = clean(basepath);
    let targ = clean(targpath);
    if targ == base {
        return Ok(".".to_string());
    }
    let base = if base == "." { String::new() } else { base };
    let (base, targ) = (base.as_bytes(), targ.as_bytes());
    let base_slashed = base.first() == Some(&SEP);
    let targ_slashed = targ.first() == Some(&SEP);
    if base_slashed != targ_slashed {
        return Err(fail());
    }
    let (bl, tl) = (base.len(), targ.len());
    let (mut b0, mut bi, mut t0, mut ti) = (0, 0, 0, 0);
    loop {
        while bi < bl && base[bi] != SEP {
            bi += 1;
        }
        while ti < tl && targ[ti] != SEP {
            ti += 1;
        }
        if targ[t0..ti] != base[b0..bi] {
            break;
        }
        if bi < bl {
            bi += 1;
        }
        if ti < tl {
            ti += 1;
        }
        b0 = bi;
        t0 = ti;
    }
    if &base[b0..bi] == b".." {
        return Err(fail());
    }
    if b0 != bl {
        let seps = base[b0..bl].iter().filter(|&&c| c == SEP).count();
        let mut out = String::from("..");
        for _ in 0..seps {
            out.push_str("/..");
        }
        if t0 != tl {
            out.push('/');
            out.push_str(&String::from_utf8_lossy(&targ[t0..]));
        }
        return Ok(out);
    }
    Ok(String::from_utf8_lossy(&targ[t0..]).into_owned())
}

/// True when `rel` (from [`rel`]) leaves its base directory.
pub fn escapes(rel: &str) -> bool {
    rel == ".." || rel.starts_with("../")
}

/// `filepath.EvalSymlinks`: every component is resolved with `lstat`, errors
/// carry the failing prefix exactly as Go reports them.
pub fn eval_symlinks(path: &str) -> Result<String, ProjectError> {
    let mut path = path.as_bytes().to_vec();
    // The Unix volume name is empty; a leading separator counts as the volume.
    let vol_len = usize::from(path.first() == Some(&SEP));
    let vol: Vec<u8> = path[..vol_len].to_vec();
    let mut dest: Vec<u8> = vol.clone();
    let mut links = 0;
    let mut start = vol_len;
    while start < path.len() {
        while start < path.len() && path[start] == SEP {
            start += 1;
        }
        let mut end = start;
        while end < path.len() && path[end] != SEP {
            end += 1;
        }
        if end == start {
            break;
        }
        let component = path[start..end].to_vec();
        if component == b"." {
            start = end;
            continue;
        }
        if component == b".." {
            let mut r = dest.len() as isize - 1;
            while r >= vol_len as isize && dest[r as usize] != SEP {
                r -= 1;
            }
            if r < vol_len as isize || &dest[(r + 1) as usize..] == b".." {
                if dest.len() > vol_len {
                    dest.push(SEP);
                }
                dest.extend_from_slice(b"..");
            } else {
                dest.truncate(r as usize);
            }
            start = end;
            continue;
        }
        if dest.len() > vol_len && dest.last() != Some(&SEP) {
            dest.push(SEP);
        }
        dest.extend_from_slice(&component);
        let dest_text = String::from_utf8_lossy(&dest).into_owned();
        let meta = std::fs::symlink_metadata(&dest_text)
            .map_err(|e| ProjectError::path("lstat", &dest_text, &e))?;
        if !meta.file_type().is_symlink() {
            if !meta.is_dir() && end < path.len() {
                return Err(ProjectError::Errno(ENOTDIR));
            }
            start = end;
            continue;
        }
        links += 1;
        if links > 255 {
            return Err(ProjectError::msg("EvalSymlinks: too many links"));
        }
        let link = std::fs::read_link(&dest_text)
            .map_err(|e| ProjectError::path("readlink", &dest_text, &e))?;
        let link = link.to_string_lossy().into_owned().into_bytes();
        let mut next = link.clone();
        next.extend_from_slice(&path[end..]);
        path = next;
        if link.first() == Some(&SEP) {
            dest = vec![SEP];
        } else {
            let mut r = dest.len() as isize - 1;
            while r >= vol_len as isize && dest[r as usize] != SEP {
                r -= 1;
            }
            if r < vol_len as isize {
                dest = vol.clone();
            } else {
                dest.truncate(r as usize);
            }
        }
        start = 0;
    }
    Ok(clean(&String::from_utf8_lossy(&dest)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_matches_go() {
        for (input, want) in [
            ("", "."),
            ("/", "/"),
            ("a/b/../c", "a/c"),
            ("../a", "../a"),
            ("/../a", "/a"),
            ("a//b/./c/", "a/b/c"),
            ("./", "."),
            ("a/..", "."),
            ("../..", "../.."),
            ("/a/b/..", "/a"),
        ] {
            assert_eq!(clean(input), want, "{input}");
        }
    }

    #[test]
    fn dir_base_ext() {
        assert_eq!(dir("/a/b/c.ms"), "/a/b");
        assert_eq!(dir("c.ms"), ".");
        assert_eq!(dir("/c.ms"), "/");
        assert_eq!(base("/a/b/"), "b");
        assert_eq!(base(""), ".");
        assert_eq!(base("///"), "/");
        assert_eq!(ext("./dir.v/file"), "");
        assert_eq!(ext("./value"), "");
        assert_eq!(ext("a/b.tar.ms"), ".ms");
    }

    #[test]
    fn rel_matches_go() {
        assert_eq!(rel("/a/b", "/a/b/c/d").unwrap(), "c/d");
        assert_eq!(rel("/a/b", "/a/c").unwrap(), "../c");
        assert_eq!(rel("/a/b", "/a/b").unwrap(), ".");
        assert_eq!(rel("/a/b/c", "/a").unwrap(), "../..");
        assert_eq!(
            rel("/a", "b").unwrap_err().to_string(),
            "Rel: can't make b relative to /a"
        );
    }

    #[test]
    fn join_ignores_empty() {
        assert_eq!(join(&["", ""]), "");
        assert_eq!(join(&["/a", "../b"]), "/b");
    }
}
