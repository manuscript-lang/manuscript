//! Lexical path operations with Go's `path/filepath` rules. Windows volumes and
//! native separators normalize to the resolver's forward-slash path spelling;
//! Unix symlink errors retain Go's exact behavior.

#[cfg(not(windows))]
use crate::error::ENOTDIR;
use crate::error::ProjectError;

const SEP: u8 = b'/';

pub fn is_abs(path: &str) -> bool {
    #[cfg(windows)]
    return std::path::Path::new(path).is_absolute();
    #[cfg(not(windows))]
    path.starts_with('/')
}

fn is_separator(c: char) -> bool {
    c == '/' || (cfg!(windows) && c == '\\')
}

#[cfg(windows)]
fn volume_len(path: &str) -> usize {
    match std::path::Path::new(path).components().next() {
        Some(std::path::Component::Prefix(prefix)) => prefix.as_os_str().len(),
        _ => 0,
    }
}

#[cfg(windows)]
fn is_verbatim(path: &str) -> bool {
    use std::path::{Component, Prefix};
    matches!(std::path::Path::new(path).components().next(),
        Some(Component::Prefix(prefix)) if matches!(prefix.kind(),
            Prefix::VerbatimDisk(_) | Prefix::VerbatimUNC(_, _) | Prefix::Verbatim(_)))
}

#[cfg(not(windows))]
fn volume_len(_: &str) -> usize {
    0
}

/// `filepath.Clean`.
pub fn clean(path: &str) -> String {
    if path.is_empty() {
        return ".".to_string();
    }
    // Verbatim paths have different separator and dot-name rules. Keep their
    // spelling intact; filesystem entry points perform checked conversion.
    #[cfg(windows)]
    if is_verbatim(path) {
        return path.to_string();
    }
    let volume_len = volume_len(path);
    #[cfg(windows)]
    let normalized = path.replace('\\', "/");
    #[cfg(windows)]
    let path = normalized.as_str();
    let (volume, path) = path.split_at(volume_len);
    if path.is_empty() && volume.starts_with("//") {
        return volume.to_string();
    }
    let rooted = path.starts_with('/');
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
    let cleaned = match (rooted, joined.is_empty()) {
        (true, _) => format!("/{joined}"),
        (false, true) => ".".to_string(),
        (false, false) => joined,
    };
    if volume.is_empty() {
        cleaned
    } else {
        format!("{volume}{cleaned}")
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
    let split = path
        .rfind(is_separator)
        .map_or(0, |i| i + 1)
        .max(volume_len(path));
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
    let trimmed = path.trim_end_matches(is_separator);
    let trimmed = &trimmed[volume_len(trimmed)..];
    if trimmed.is_empty() {
        return "/".to_string();
    }
    match trimmed.rfind(is_separator) {
        Some(i) => trimmed[i + 1..].to_string(),
        None => trimmed.to_string(),
    }
}

/// `filepath.Ext`: the suffix beginning at the final dot of the last element.
pub fn ext(path: &str) -> &str {
    let bytes = path.as_bytes();
    let mut i = bytes.len();
    while i > 0 && !is_separator(bytes[i - 1] as char) {
        i -= 1;
        if bytes[i] == b'.' {
            return &path[i..];
        }
    }
    ""
}

/// `filepath.Abs`.
pub fn abs(path: &str) -> Result<String, ProjectError> {
    #[cfg(windows)]
    {
        let path = if path.is_empty() { "." } else { path };
        let absolute =
            std::path::absolute(path).map_err(|e| ProjectError::path("abs", path, &e))?;
        let absolute = absolute.to_string_lossy();
        if is_verbatim(&absolute) {
            eval_symlinks(&absolute)
        } else {
            Ok(clean(&absolute))
        }
    }
    #[cfg(not(windows))]
    {
        if is_abs(path) {
            return Ok(clean(path));
        }
        let wd = std::env::current_dir().map_err(|e| ProjectError::path("getwd", "", &e))?;
        Ok(join(&[&wd.to_string_lossy(), path]))
    }
}

/// `filepath.Rel`.
pub fn rel(basepath: &str, targpath: &str) -> Result<String, ProjectError> {
    let fail = || ProjectError::msg(format!("Rel: can't make {targpath} relative to {basepath}"));
    let base = clean(basepath);
    let targ = clean(targpath);
    let (base_volume, base) = base.split_at(volume_len(&base));
    let (targ_volume, targ) = targ.split_at(volume_len(&targ));
    if !base_volume.eq_ignore_ascii_case(targ_volume) {
        return Err(fail());
    }
    // A bare UNC share is a root even without a trailing separator.
    let base = if base.is_empty() && base_volume.starts_with("//") {
        "/"
    } else {
        base
    };
    let targ = if targ.is_empty() && targ_volume.starts_with("//") {
        "/"
    } else {
        targ
    };
    if targ == base {
        return Ok(".".to_string());
    }
    let base = if base == "." { "" } else { base };
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
/// carry the failing prefix.
#[cfg(not(windows))]
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

/// Windows canonicalization resolves native drive roots and junctions. Convert
/// only the canonicalizer's disk/UNC namespace, and verify the ordinary spelling
/// still names exactly the same filesystem entry before using it as an identity.
#[cfg(windows)]
pub fn eval_symlinks(path: &str) -> Result<String, ProjectError> {
    use std::path::{Component, Prefix};

    let canonical =
        std::fs::canonicalize(path).map_err(|e| ProjectError::path("lstat", path, &e))?;
    let unsupported = || {
        ProjectError::msg(format!(
            "unsupported Windows project path {}; use names that do not require a verbatim namespace",
            canonical.display()
        ))
    };
    if canonical.components().any(|part| {
        matches!(part, Component::Normal(name)
        if name.to_string_lossy().ends_with(['.', ' ']))
    }) {
        return Err(unsupported());
    }
    let Some(Component::Prefix(prefix)) = canonical.components().next() else {
        return Err(unsupported());
    };
    let text = canonical.to_string_lossy();
    let suffix = &text[prefix.as_os_str().len()..];
    let ordinary = match prefix.kind() {
        Prefix::VerbatimDisk(drive) => format!("{}:{suffix}", char::from(drive)),
        Prefix::VerbatimUNC(server, share) => format!(
            "//{}/{}{suffix}",
            server.to_string_lossy(),
            share.to_string_lossy()
        ),
        _ => return Err(unsupported()),
    };
    let ordinary = clean(&ordinary);
    let roundtrip =
        std::fs::canonicalize(&ordinary).map_err(|e| ProjectError::path("lstat", &ordinary, &e))?;
    if roundtrip != canonical {
        return Err(unsupported());
    }
    Ok(ordinary)
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
