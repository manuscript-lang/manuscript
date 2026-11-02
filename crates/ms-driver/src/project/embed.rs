//! `[embed]`: a directory baked into the program as a generated Manuscript module.
//!
//! The module exports `files()`, which builds an `EmbeddedTree` (`@std/os/tree.ms`) holding every
//! file of the directory as a base64 string literal that is decoded only when the file is read. Nothing about it is special to the
//! checker, lowering, or the runtime.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};

use crate::project::error::ProjectError;

/// Largest single embedded file.
pub const MAX_FILE: u64 = 16 * 1024 * 1024;
/// Largest total of embedded file contents per name.
pub const MAX_TOTAL: u64 = 64 * 1024 * 1024;

/// Directory in the project root that holds the logical paths of generated modules.
pub const MODULE_DIR: &str = ".ms-embed";

/// One directory entry found by the walk, with its path below the embedded root.
struct Found {
    path: String,
    directory: bool,
    source: PathBuf,
}

fn walk(root: &Path, relative: &str, out: &mut Vec<Found>) -> Result<(), ProjectError> {
    let directory = if relative.is_empty() {
        root.to_path_buf()
    } else {
        root.join(relative)
    };
    let mut names = Vec::new();
    let entries = std::fs::read_dir(&directory)
        .map_err(|e| ProjectError::path("read directory", &directory.to_string_lossy(), &e))?;
    for entry in entries {
        let entry = entry
            .map_err(|e| ProjectError::path("read directory", &directory.to_string_lossy(), &e))?;
        let name = entry.file_name().into_string().map_err(|_| {
            ProjectError::msg(format!(
                "embedded name in {} is not valid UTF-8; rename it",
                directory.display()
            ))
        })?;
        names.push(name);
    }
    // Byte order, the same on every platform.
    names.sort();
    for name in names {
        let path = if relative.is_empty() {
            name.clone()
        } else {
            format!("{relative}/{name}")
        };
        let source = directory.join(&name);
        let kind = std::fs::symlink_metadata(&source)
            .map_err(|e| ProjectError::path("stat", &source.to_string_lossy(), &e))?;
        if kind.file_type().is_symlink() {
            return Err(ProjectError::msg(format!(
                "embedded {path} is a symbolic link; copy the file into the directory instead, since links are not followed"
            )));
        }
        if kind.is_dir() {
            out.push(Found {
                path: path.clone(),
                directory: true,
                source,
            });
            walk(root, &path, out)?;
        } else if kind.is_file() {
            out.push(Found {
                path,
                directory: false,
                source,
            });
        } else {
            return Err(ProjectError::msg(format!(
                "embedded {path} is neither a file nor a directory; remove it"
            )));
        }
    }
    Ok(())
}

fn found(root: &str) -> Result<Vec<Found>, ProjectError> {
    let mut out = Vec::new();
    walk(Path::new(root), "", &mut out)?;
    let mut lowered = std::collections::BTreeMap::new();
    for entry in &out {
        if let Some(other) = lowered.insert(entry.path.to_lowercase(), &entry.path) {
            return Err(ProjectError::msg(format!(
                "embedded {} and {other} differ only by letter case; rename one so the program behaves the same on every filesystem",
                entry.path
            )));
        }
    }
    Ok(out)
}

/// The directories and files whose stamps decide whether a cached build is still valid.
/// Directories catch added, removed and renamed entries; files catch edits.
pub fn inputs(root: &str) -> Result<Vec<PathBuf>, ProjectError> {
    let mut all = vec![PathBuf::from(root)];
    all.extend(found(root)?.into_iter().map(|f| f.source));
    Ok(all)
}

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn base64(data: &[u8], out: &mut String) {
    for chunk in data.chunks(3) {
        let n = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(ALPHABET[(n >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
}

fn literal(text: &str) -> Result<String, ProjectError> {
    let mut out = String::from("\"");
    for c in text.chars() {
        match c {
            '\\' | '"' | '{' | '}' => {
                out.push('\\');
                out.push(c);
            }
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                return Err(ProjectError::msg(format!(
                    "embedded name {text:?} has a control character; rename it"
                )));
            }
            c => out.push(c),
        }
    }
    out.push('"');
    Ok(out)
}

/// The source of the module that `name` (for example `@assets`) imports.
pub fn generate(name: &str, root: &str) -> Result<String, ProjectError> {
    let mut source = String::from(include_str!("embed_module.ms"));
    let mut total = 0u64;
    for entry in found(root)? {
        let path = literal(&entry.path)?;
        if entry.directory {
            let _ = writeln!(source, "    directories.add({path})");
            continue;
        }
        let data = std::fs::read(&entry.source)
            .map_err(|e| ProjectError::path("read", &entry.source.to_string_lossy(), &e))?;
        if data.len() as u64 > MAX_FILE {
            return Err(ProjectError::msg(format!(
                "embedded {} is larger than {} MiB; keep large data outside the program",
                entry.path,
                MAX_FILE >> 20
            )));
        }
        total += data.len() as u64;
        if total > MAX_TOTAL {
            return Err(ProjectError::msg(format!(
                "embedded {name} holds more than {} MiB; keep large data outside the program",
                MAX_TOTAL >> 20
            )));
        }
        let mut text = String::with_capacity(data.len().div_ceil(3) * 4);
        base64(&data, &mut text);
        let _ = writeln!(source, "    encoded.add({path}, \"{text}\")");
    }
    source.push_str("    return embedded_tree(encoded, directories)\n");
    Ok(source)
}

/// The logical module path that `name` resolves to, under the project root.
pub fn module_path(root: &str, name: &str) -> String {
    crate::project::pathops::join(&[
        root,
        MODULE_DIR,
        &format!("{}.ms", name.trim_start_matches('@')),
    ])
}

/// Reverse of [`module_path`]: the embed name whose generated module lives at `canonical`.
pub fn name_of<'a>(
    embed: &'a std::collections::BTreeMap<String, String>,
    root: &str,
    canonical: &str,
) -> Option<(&'a str, &'a str)> {
    embed
        .iter()
        .find(|(name, _)| module_path(root, name) == canonical)
        .map(|(name, dir)| (name.as_str(), dir.as_str()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn directory(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("ms-embed-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn base64_matches_known_vectors() {
        let cases: [(&[u8], &str); 5] = [
            (b"", ""),
            (b"f", "Zg=="),
            (b"fo", "Zm8="),
            (b"foo", "Zm9v"),
            (b"foobar", "Zm9vYmFy"),
        ];
        for (data, want) in cases {
            let mut got = String::new();
            base64(data, &mut got);
            assert_eq!(got, want);
        }
    }

    #[test]
    fn generated_source_lists_entries_in_byte_order_with_empty_directories() {
        let dir = directory("order");
        std::fs::write(dir.join("b.txt"), "b").unwrap();
        std::fs::write(dir.join("B2.txt"), "B2").unwrap();
        std::fs::create_dir(dir.join("empty")).unwrap();
        let source = generate("@assets", dir.to_str().unwrap()).unwrap();
        let at = |needle: &str| source.find(needle).unwrap_or_else(|| panic!("{needle}"));
        assert!(at("\"B2.txt\"") < at("\"b.txt\""));
        assert!(at("directories.add(\"empty\")") > at("\"b.txt\""));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn names_that_differ_only_by_case_are_rejected() {
        let dir = directory("case");
        std::fs::write(dir.join("a.txt"), "a").unwrap();
        std::fs::write(dir.join("A.txt"), "A").unwrap();
        // A case-insensitive filesystem cannot hold both; only assert where it can.
        if std::fs::read_dir(&dir).unwrap().count() == 2 {
            let error = generate("@assets", dir.to_str().unwrap())
                .unwrap_err()
                .to_string();
            assert!(error.contains("differ only by letter case"), "{error}");
        }
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn names_with_braces_and_quotes_are_escaped() {
        assert_eq!(literal("a{b}\"c\\").unwrap(), "\"a\\{b\\}\\\"c\\\\\"");
        assert!(literal("tab\there").is_err());
    }

    #[cfg(unix)]
    #[test]
    fn symbolic_links_are_rejected() {
        let dir = directory("link");
        std::fs::write(dir.join("real.txt"), "x").unwrap();
        std::os::unix::fs::symlink(dir.join("real.txt"), dir.join("link.txt")).unwrap();
        let error = generate("@assets", dir.to_str().unwrap())
            .unwrap_err()
            .to_string();
        assert!(error.contains("symbolic link"), "{error}");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn inputs_list_the_directory_and_every_entry() {
        let dir = directory("inputs");
        std::fs::create_dir(dir.join("sub")).unwrap();
        std::fs::write(dir.join("sub/f.txt"), "x").unwrap();
        let listed = inputs(dir.to_str().unwrap()).unwrap();
        assert_eq!(listed.len(), 3);
        assert_eq!(listed[0], dir);
        let _ = std::fs::remove_dir_all(dir);
    }
}
