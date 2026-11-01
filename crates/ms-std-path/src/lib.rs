//! `@std/os/fs.ms` natives. Every operation is a
//! method of [`Rules`], which selects POSIX or Windows conventions; the host-rule functions of the
//! language pass the host's flag.
#![no_std]

extern crate alloc;

pub mod ffi;
pub mod glob;

use alloc::string::{String, ToString};
use alloc::vec::Vec;

/// The `PathParts` record of `@std/os/fs.ms`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Parts {
    pub root: String,
    pub directory: String,
    pub base: String,
    pub extension: String,
    pub name: String,
}

/// `PathError.InvalidInput` is the only error case.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct InvalidInput;

#[derive(Clone, Copy, Debug)]
pub struct Rules {
    pub windows: bool,
}

pub const POSIX: Rules = Rules { windows: false };
pub const WIN32: Rules = Rules { windows: true };

fn is_letter(c: u8) -> bool {
    c.is_ascii_alphabetic()
}

/// Go's `path.Ext`.
fn ext_of(base: &str) -> &str {
    for (i, c) in base.bytes().enumerate().rev() {
        if c == b'/' {
            break;
        }
        if c == b'.' {
            return &base[i..];
        }
    }
    ""
}

fn equal_fold(a: &str, b: &str) -> bool {
    a.chars()
        .flat_map(char::to_lowercase)
        .eq(b.chars().flat_map(char::to_lowercase))
}

impl Rules {
    fn slash(self, s: &str) -> String {
        if self.windows {
            s.replace('\\', "/")
        } else {
            s.to_string()
        }
    }

    fn native(self, s: &str) -> String {
        if self.windows {
            s.replace('/', "\\")
        } else {
            s.to_string()
        }
    }

    /// Root of an already slash-normalized path.
    fn root_of(self, s: &str) -> String {
        let b = s.as_bytes();
        if self.windows {
            if b.len() >= 2 && is_letter(b[0]) && b[1] == b':' {
                return if b.len() > 2 && b[2] == b'/' {
                    s[..3].to_string()
                } else {
                    s[..2].to_string()
                };
            }
            if s.starts_with("//") {
                let mut start = 2;
                while start < b.len() && b[start] == b'/' {
                    start += 1;
                }
                if let Some(server_end) = s[start..].find('/') {
                    let server_end = server_end + start;
                    let mut share_start = server_end + 1;
                    while share_start < b.len() && b[share_start] == b'/' {
                        share_start += 1;
                    }
                    if share_start < b.len() {
                        return match s[share_start..].find('/') {
                            None => s.to_string(),
                            Some(share_end) => s[..share_start + share_end + 1].to_string(),
                        };
                    }
                }
            }
        }
        if s.starts_with('/') {
            "/".to_string()
        } else {
            String::new()
        }
    }

    fn root(self, s: &str) -> String {
        self.root_of(&self.slash(s))
    }

    pub fn is_absolute(self, s: &str) -> bool {
        let root = self.root(s);
        root.ends_with('/') || self.windows && root.starts_with("//")
    }

    pub fn normalize(self, s: &str) -> String {
        let normalized = self.windows.then(|| self.slash(s));
        let s = normalized.as_deref().unwrap_or(s);
        if s.is_empty() {
            return ".".to_string();
        }
        let mut root = self.root_of(s);
        let tail = &s[root.len()..];
        if self.windows && root.starts_with("//") && !root.ends_with('/') {
            root.push('/');
        }
        let mut stack: Vec<&str> = Vec::new();
        for part in tail.split('/') {
            match part {
                "" | "." => {}
                ".." => {
                    if stack.last().is_some_and(|&l| l != "..") {
                        stack.pop();
                    } else if !root.ends_with('/') {
                        stack.push(part);
                    }
                }
                _ => stack.push(part),
            }
        }
        let mut value = alloc::format!("{root}{}", stack.join("/"));
        if value.is_empty() {
            value = ".".to_string();
        }
        if s.ends_with('/') && !value.ends_with('/') {
            value.push('/');
        }
        if self.windows && root.len() == 2 && stack.is_empty() {
            value = alloc::format!("{root}.");
        }
        // A relative first component shaped like a drive ("./C:") must not become
        // a drive-relative path once the leading "." is removed.
        if self.windows && root.is_empty() && !stack.is_empty() && !self.root(stack[0]).is_empty() {
            value = alloc::format!("./{value}");
        }
        if self.windows {
            self.native(&value)
        } else {
            value
        }
    }

    pub fn parse(self, original: &str) -> Parts {
        let s = self.slash(original);
        let root = self.root_of(&s);
        let trimmed = s.trim_end_matches('/');
        let mut base = "";
        let mut dir = "";
        let root_original = &original[..root.len()];
        if trimmed.len() > root.trim_end_matches('/').len() {
            let at = trimmed.rfind('/');
            base = &trimmed[at.map_or(0, |i| i + 1)..];
            if let Some(at) = at {
                dir = &original[..at];
            }
            if self.windows && root.len() == 2 && at.is_none() {
                base = &trimmed[2..];
                dir = root_original;
            }
            if dir.len() < root.len() {
                dir = root_original;
            }
        }
        if base.is_empty() && !root.is_empty() {
            dir = root_original;
        }
        let mut ext = ext_of(base);
        if base == ".." || ext.len() == base.len() {
            ext = "";
        }
        Parts {
            root: root_original.to_string(),
            directory: dir.to_string(),
            base: base.to_string(),
            extension: ext.to_string(),
            name: base.strip_suffix(ext).unwrap_or(base).to_string(),
        }
    }

    pub fn extension(self, s: &str) -> String {
        if !self.windows {
            let base = s.trim_end_matches('/').rsplit('/').next().unwrap_or("");
            let Some(at) = base.rfind('.') else {
                return String::new();
            };
            if at == 0 || base == ".." {
                return String::new();
            }
            return base[at..].to_string();
        }
        self.parse(s).extension
    }

    fn resolve_inner(self, base: &str, parts: &[&str]) -> Option<String> {
        if !self.is_absolute(base) || base.contains('\0') || parts.iter().any(|p| p.contains('\0'))
        {
            return None;
        }
        let value = if self.windows {
            // Resolve from the last component: absolute paths supersede earlier tails, while an
            // earlier absolute path on the chosen drive supplies its base.
            let (mut device, mut tail, mut absolute) = (String::new(), String::new(), false);
            let mut components: Vec<&str> = alloc::vec![base];
            components.extend_from_slice(parts);
            for comp in components.iter().rev() {
                let part = self.slash(comp);
                if part.is_empty() {
                    continue;
                }
                let root = self.root_of(&part);
                let part_device = root.strip_suffix('/').unwrap_or(&root);
                if !part_device.is_empty() {
                    if !device.is_empty() && !equal_fold(&device, part_device) {
                        continue;
                    }
                    device = part_device.to_string();
                }
                if !absolute {
                    tail = alloc::format!("{}/{tail}", &part[root.len()..]);
                    absolute = self.is_absolute(&part);
                }
                if absolute && !device.is_empty() {
                    break;
                }
            }
            if !absolute {
                return None;
            }
            alloc::format!("{device}/{tail}")
        } else {
            let mut value = self.slash(base);
            for part in parts {
                if self.is_absolute(part) {
                    value = part.to_string();
                } else if !part.is_empty() {
                    value = alloc::format!("{}/{part}", value.trim_end_matches('/'));
                }
            }
            value
        };
        let mut normalized = self.normalize(&value);
        if normalized != self.native(&self.root(&normalized)) {
            let sep = self.native("/");
            if let Some(stripped) = normalized.strip_suffix(sep.as_str()) {
                normalized = stripped.to_string();
            }
        }
        Some(normalized)
    }

    pub fn resolve(self, base: &str, parts: &[&str]) -> Result<String, InvalidInput> {
        self.resolve_inner(base, parts).ok_or(InvalidInput)
    }

    pub fn separator(self) -> &'static str {
        if self.windows { "\\" } else { "/" }
    }

    pub fn delimiter(self) -> &'static str {
        if self.windows { ";" } else { ":" }
    }

    pub fn basename(self, raw: &str) -> String {
        self.basename_inner(raw, "", false)
    }

    pub fn basename_without(self, raw: &str, suffix: &str) -> String {
        self.basename_inner(raw, suffix, true)
    }

    fn basename_inner(self, raw: &str, suffix: &str, strip: bool) -> String {
        let mut original = self.slash(raw);
        let mut prefix = 0;
        let b = original.as_bytes();
        if self.windows && b.len() >= 2 && b[1] == b':' && is_letter(b[0]) {
            prefix = 2;
            original = original[2..].to_string();
        }
        let mut base = original.trim_end_matches('/');
        if let Some(at) = base.rfind('/') {
            base = &base[at + 1..];
        }
        if strip && !suffix.is_empty() && suffix.len() <= raw.len() {
            if raw == suffix {
                return String::new();
            }
            if base.is_empty() {
                return raw[prefix..].to_string();
            }
            if suffix != base {
                base = base.strip_suffix(suffix).unwrap_or(base);
            }
        }
        base.to_string()
    }

    pub fn dirname(self, original: &str) -> String {
        let s = self.slash(original);
        let root = self.root_of(&s);
        let s = s.trim_end_matches('/');
        match s.rfind('/') {
            None if !root.is_empty() => original[..root.len()].to_string(),
            None => ".".to_string(),
            Some(at) if at < root.len() => original[..root.len()].to_string(),
            Some(at) => original[..at].to_string(),
        }
    }

    pub fn join(self, items: &[&str]) -> String {
        let parts: Vec<&str> = items.iter().copied().filter(|p| !p.is_empty()).collect();
        let mut joined = parts.join("/");
        if self.windows && self.slash(&joined).starts_with("//") {
            let first = self.slash(parts[0]);
            let unc = first.len() > 2 && first.starts_with("//") && first.as_bytes()[2] != b'/';
            if !unc {
                joined = alloc::format!("/{}", self.slash(&joined).trim_start_matches('/'));
            }
        }
        self.normalize(&joined)
    }

    pub fn relative(self, base_arg: &str, target_arg: &str) -> Result<String, InvalidInput> {
        let (Some(base), Some(target)) = (
            self.resolve_inner(base_arg, &[]),
            self.resolve_inner(target_arg, &[]),
        ) else {
            return Err(InvalidInput);
        };
        let (b, t) = (self.slash(&base), self.slash(&target));
        let eq = |x: &str, y: &str| {
            if self.windows {
                equal_fold(x, y)
            } else {
                x == y
            }
        };
        let (rb, rt) = (self.root_of(&b), self.root_of(&t));
        if !eq(&rb, &rt) {
            return Ok(target);
        }
        let split = |s: &str| -> Vec<String> {
            let v: Vec<String> = s.split('/').map(String::from).collect();
            if v.len() == 1 && v[0].is_empty() {
                Vec::new()
            } else {
                v
            }
        };
        let (bs, ts) = (
            split(b.strip_prefix(rb.as_str()).unwrap_or(&b)),
            split(t.strip_prefix(rt.as_str()).unwrap_or(&t)),
        );
        let mut i = 0;
        while i < bs.len() && i < ts.len() && eq(&bs[i], &ts[i]) {
            i += 1;
        }
        let mut out: Vec<&str> = alloc::vec![".."; bs.len() - i];
        out.extend(ts[i..].iter().map(String::as_str));
        Ok(self.native(&out.join("/")))
    }

    pub fn format(self, f: &Parts) -> String {
        let dir = if f.directory.is_empty() {
            f.root.as_str()
        } else {
            f.directory.as_str()
        };
        let base = if f.base.is_empty() {
            let ext = f.extension.as_str();
            if !ext.is_empty() && !ext.starts_with('.') {
                alloc::format!("{}.{ext}", f.name)
            } else {
                alloc::format!("{}{ext}", f.name)
            }
        } else {
            f.base.clone()
        };
        if dir.is_empty() {
            return base;
        }
        if dir == f.root {
            return alloc::format!("{dir}{base}");
        }
        alloc::format!("{dir}{}{base}", self.native("/"))
    }

    pub fn to_namespaced_path(self, s: &str) -> String {
        let root = self.root(s);
        if !self.windows
            || !self.is_absolute(s)
            || root == "/"
            || s.starts_with("\\\\?\\")
            || s.starts_with("\\\\.\\")
        {
            return s.to_string();
        }
        match self.resolve_inner(s, &[]) {
            None => s.to_string(),
            Some(r) if r.starts_with("\\\\") => alloc::format!("\\\\?\\UNC\\{}", &r[2..]),
            Some(r) => alloc::format!("\\\\?\\{r}"),
        }
    }

    pub fn matches_glob(self, value: &str, pattern: &str) -> Result<bool, InvalidInput> {
        let glob = glob::Glob::new(&self.slash(pattern)).ok_or(InvalidInput)?;
        if value.contains('\0') {
            return Err(InvalidInput);
        }
        Ok(glob.matches(&self.slash(value)))
    }
}

#[cfg(test)]
mod tests {
    extern crate std;
    use super::*;

    // Frozen POSIX behavior from before the basename-only extension fast path.
    fn previous_posix_parts(original: &str) -> Parts {
        let s = original.to_string();
        let root = if s.starts_with('/') { "/" } else { "" };
        let trimmed = s.trim_end_matches('/');
        let mut base = "";
        let mut dir = "";
        if !trimmed.is_empty() {
            let at = trimmed.rfind('/');
            base = &trimmed[at.map_or(0, |i| i + 1)..];
            if let Some(at) = at {
                dir = &original[..at];
            }
            if dir.len() < root.len() {
                dir = root;
            }
        }
        if base.is_empty() && !root.is_empty() {
            dir = root;
        }
        let mut ext = "";
        for (i, c) in base.bytes().enumerate().rev() {
            if c == b'/' {
                break;
            }
            if c == b'.' {
                ext = &base[i..];
                break;
            }
        }
        if base == "." || base == ".." || base.starts_with('.') && base.matches('.').count() == 1 {
            ext = "";
        }
        Parts {
            root: root.to_string(),
            directory: dir.to_string(),
            base: base.to_string(),
            extension: ext.to_string(),
            name: base.strip_suffix(ext).unwrap_or(base).to_string(),
        }
    }

    fn previous_posix_normalize(input: &str) -> String {
        let s = input.to_string();
        if s.is_empty() {
            return ".".to_string();
        }
        let root = if s.starts_with('/') { "/" } else { "" };
        let mut stack: Vec<&str> = Vec::new();
        for part in s[root.len()..].split('/') {
            match part {
                "" | "." => {}
                ".." => {
                    if stack.last().is_some_and(|&last| last != "..") {
                        stack.pop();
                    } else if !root.ends_with('/') {
                        stack.push(part);
                    }
                }
                _ => stack.push(part),
            }
        }
        let mut value = alloc::format!("{root}{}", stack.join("/"));
        if value.is_empty() {
            value = ".".to_string();
        }
        if s.ends_with('/') && !value.ends_with('/') {
            value.push('/');
        }
        value.to_string()
    }

    #[test]
    fn posix_component_fast_paths_preserve_parts() {
        let check = |input: &str| {
            let expected = previous_posix_parts(input);
            assert_eq!(POSIX.parse(input), expected, "parse {input:?}");
            assert_eq!(
                POSIX.extension(input),
                expected.extension,
                "extension {input:?}"
            );
            assert_eq!(
                POSIX.normalize(input),
                previous_posix_normalize(input),
                "normalize {input:?}"
            );
        };
        for input in [
            "",
            "/",
            "////",
            ".",
            "..",
            "...",
            ".env",
            ".env.local",
            "a.",
            "a..",
            "a.tar.gz/",
            "/a//b/.env//",
            "a\\b.txt",
            "a\0b.ext",
            "a/../",
            "../../a/../b/",
            "/../../a/../",
        ] {
            check(input);
        }
        let chunks = ["a", ".", "/", "\\", "é", "🕰", "\0"];
        for mut seed in 0..chunks.len().pow(5) {
            let mut path = String::new();
            for _ in 0..5 {
                path.push_str(chunks[seed % chunks.len()]);
                seed /= chunks.len();
            }
            check(&path);
            check(&alloc::format!("/{path}//"));
        }
        for input in [
            "x".repeat(16384),
            alloc::format!(".{}", "x".repeat(16384)),
            ".".repeat(16384),
            alloc::format!("/{}/file.tar.gz///", "dir/".repeat(4096)),
        ] {
            check(&input);
        }
    }

    #[test]
    fn posix_basics() {
        let p = POSIX;
        assert_eq!(p.basename("/a/b.txt/"), "b.txt");
        assert_eq!(p.basename_without("/a/b.txt", ".txt"), "b");
        assert_eq!(p.dirname("/a/b/c"), "/a/b");
        assert_eq!(p.dirname("a"), ".");
        assert_eq!(p.dirname("/"), "/");
        assert_eq!(p.normalize("/a/./b/../c//d/"), "/a/c/d/");
        assert_eq!(p.normalize("../../a"), "../../a");
        assert_eq!(p.normalize(""), ".");
        assert_eq!(p.join(&["a", "", "b", "../c"]), "a/c");
        assert_eq!(p.extension("x/.bashrc"), "");
        assert_eq!(p.extension("x/a.tar.gz"), ".gz");
        assert!(p.is_absolute("/x") && !p.is_absolute("x"));
        assert_eq!(p.resolve("/a/b", &["../c", "d"]).unwrap(), "/a/c/d");
        assert_eq!(p.resolve("rel", &[]), Err(InvalidInput));
        assert_eq!(p.relative("/a/b/c", "/a/d").unwrap(), "../../d");
        let parts = p.parse("/home/u/file.tar.gz");
        assert_eq!(
            parts,
            Parts {
                root: "/".into(),
                directory: "/home/u".into(),
                base: "file.tar.gz".into(),
                extension: ".gz".into(),
                name: "file.tar".into()
            }
        );
        assert_eq!(p.format(&parts), "/home/u/file.tar.gz");
        assert_eq!(p.matches_glob("a/b.ms", "a/*.ms"), Ok(true));
        assert_eq!(p.matches_glob("a", "["), Err(InvalidInput));
    }

    #[test]
    fn windows_basics() {
        let w = WIN32;
        assert_eq!(w.normalize("C:\\a\\..\\b"), "C:\\b");
        assert_eq!(w.basename("C:\\dir\\file.txt"), "file.txt");
        assert!(w.is_absolute("C:\\x") && !w.is_absolute("C:x"));
        assert_eq!(w.dirname("C:\\a\\b"), "C:\\a");
        assert_eq!(w.to_namespaced_path("C:\\a"), "\\\\?\\C:\\a");
        assert_eq!(w.separator(), "\\");
        assert_eq!(w.delimiter(), ";");
    }
}
