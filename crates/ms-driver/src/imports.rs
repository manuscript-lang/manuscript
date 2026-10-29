//! Import suggestions for unresolved names that a project module exports.
//!
//! The checker only knows standard modules, so its `add: import ... from "@std/..."` hint
//! cannot name a sibling file nobody imported yet. This pass scans the project's
//! `.ms` files for top-level `export` declarations and, for an unknown name one
//! of them exports, replaces the hint with that file's import (preferred over a
//! standard-library one).

use std::collections::BTreeMap;
use std::path::Path;

use ms_syntax::{Diagnostic, DiagnosticFix, Phase, Pos};

use crate::project::pathops;

/// The most files one scan reads, so a huge tree cannot stall a check.
const MAX_FILES: usize = 2000;

/// Names declared by top-level `export` lines of `source`, without checking it.
pub fn exported_names(source: &str) -> Vec<String> {
    let mut names = Vec::new();
    for line in source.lines() {
        let Some(rest) = line.strip_prefix("export ") else {
            continue;
        };
        let rest = rest.strip_prefix("extern ").unwrap_or(rest);
        let Some((keyword, rest)) = rest.split_once(' ') else {
            continue;
        };
        if !matches!(keyword, "fn" | "type" | "interface" | "let") {
            continue;
        }
        let name: String = rest
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
            .collect();
        if !name.is_empty() {
            names.push(name);
        }
    }
    names
}

/// The name an `unknown binding`/`unknown type` diagnostic is about.
pub fn unresolved_name(message: &str) -> Option<&str> {
    let rest = message
        .strip_prefix("unknown binding ")
        .or_else(|| message.strip_prefix("unknown type "))?;
    let name = rest.split(';').next()?.trim();
    (!name.is_empty() && name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_'))
        .then_some(name)
}

/// The import path of `target` as written in a file inside `dir`.
pub fn import_path(dir: &str, target: &str) -> Option<String> {
    let relative = pathops::rel(dir, target).ok()?.replace('\\', "/");
    Some(if relative.starts_with("../") {
        relative
    } else {
        format!("./{relative}")
    })
}

fn walk(dir: &Path, files: &mut Vec<String>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let mut entries: Vec<_> = entries.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        if files.len() >= MAX_FILES {
            return;
        }
        let Ok(kind) = entry.file_type() else {
            continue;
        };
        let name = entry.file_name().to_string_lossy().into_owned();
        let path = entry.path();
        if kind.is_dir() {
            if !name.starts_with('.') && name != "node_modules" && name != "vendor" {
                walk(&path, files);
            }
        } else if kind.is_file() && name.ends_with(".ms") {
            files.push(path.to_string_lossy().into_owned());
        }
    }
}

/// Rewrites the hint of each unresolved name that a project file exports.
pub fn suggest_project_imports(diagnostics: &mut [Diagnostic], source_root: &str) {
    let wanted = |d: &Diagnostic| {
        d.phase == Phase::Resolution
            && !d.file.starts_with('@')
            && unresolved_name(&d.message).is_some()
    };
    if source_root.is_empty() || !diagnostics.iter().any(wanted) {
        return;
    }
    let mut files = Vec::new();
    walk(Path::new(source_root), &mut files);
    // export name -> files exporting it
    let mut exports: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for file in files {
        let Ok(data) = std::fs::read(&file) else {
            continue;
        };
        for name in exported_names(&String::from_utf8_lossy(&data)) {
            exports.entry(name).or_default().push(file.clone());
        }
    }
    for d in diagnostics.iter_mut().filter(|d| wanted(d)) {
        let Some(name) = unresolved_name(&d.message).map(str::to_string) else {
            continue;
        };
        let Some(candidates) = exports.get(&name) else {
            continue;
        };
        let Ok(here) = pathops::abs(&d.file) else {
            continue;
        };
        let dir = pathops::dir(&here);
        let paths: Vec<String> = candidates
            .iter()
            .filter(|c| **c != here)
            .filter_map(|c| import_path(&dir, c))
            .collect();
        let head = d.message.split(';').next().unwrap_or("").to_string();
        match paths.as_slice() {
            [] => {}
            [path] => {
                let statement = format!("import {name} from \"{path}\"");
                d.message = format!("{head}; add: {statement}");
                let start = Pos::new(0, 1, 1);
                d.fix = Some(DiagnosticFix {
                    pos: start,
                    end: start,
                    replacement: format!("{statement}\n"),
                });
            }
            _ => {
                let shown: Vec<String> = paths.iter().take(4).map(|p| format!("\"{p}\"")).collect();
                d.message = format!(
                    "{head}; {name} is exported by several project modules ({}); import it from the one you mean",
                    shown.join(", ")
                );
                d.fix = None;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unknown(file: &str) -> Diagnostic {
        Diagnostic {
            file: file.into(),
            pos: Pos::new(12, 1, 13),
            phase: Phase::Resolution,
            message: "unknown type Bytes; add: import Bytes from \"@std/bytes.ms\"".into(),
            end: None,
            fix: None,
        }
    }

    #[test]
    fn a_project_export_replaces_the_standard_hint() {
        let root = std::env::temp_dir().join(format!("ms-imports-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("lib")).unwrap();
        std::fs::write(
            root.join("lib/blobs.ms"),
            "export type Bytes:\n    n: Int\n",
        )
        .unwrap();
        let root = pathops::eval_symlinks(root.to_str().unwrap()).unwrap();
        let main = pathops::join(&[&root, "main.ms"]);
        let mut found = vec![unknown(&main)];
        suggest_project_imports(&mut found, &root);
        assert_eq!(
            found[0].message,
            "unknown type Bytes; add: import Bytes from \"./lib/blobs.ms\""
        );
        assert_eq!(
            found[0].fix.as_ref().unwrap().replacement,
            "import Bytes from \"./lib/blobs.ms\"\n"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn exports_are_read_from_top_level_lines() {
        let source = "export type A:\n    x: Int\nexport extern fn b() Int: ...\nexport let C = 1\nfn d() Int:\n    return 0\n";
        assert_eq!(exported_names(source), ["A", "b", "C"]);
    }
}
