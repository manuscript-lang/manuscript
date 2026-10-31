//! Import suggestions for unresolved names that a project module exports.
//!
//! The checker only knows standard modules, so its `add: import ... from "@std/..."` hint
//! cannot name a sibling file nobody imported yet. This pass scans the project's
//! `.ms` files for top-level `export` declarations and, for an unknown name one
//! of them exports, replaces the hint with that file's import (preferred over a
//! standard-library one).

use std::collections::BTreeMap;
use std::path::Path;
use std::sync::Arc;

use ms_syntax::ast::DeclKind;
use ms_syntax::lexer;
use ms_syntax::token::Tok;
use ms_syntax::{Diagnostic, DiagnosticFix, Phase, Pos};

use crate::project::pathops;

/// The most files one scan reads, so a huge tree cannot stall a check.
const MAX_FILES: usize = 2000;

/// Names declared by top-level exports, without checking the source. Ordinary
/// headers need no body parsing; grouped constants share the lexer's delimiters.
pub fn exported_names(source: &str) -> Vec<String> {
    let mut names = Vec::new();
    let mut groups = None;
    for (line, text) in source.lines().enumerate() {
        let Some(rest) = text.strip_prefix("export ") else {
            continue;
        };
        let rest = rest.trim_start();
        let rest = rest
            .strip_prefix("extern ")
            .or_else(|| rest.strip_prefix("opaque "))
            .unwrap_or(rest)
            .trim_start();
        if rest
            .strip_prefix("let")
            .is_some_and(|tail| tail.trim_start().starts_with('('))
        {
            let Some(groups) = groups.get_or_insert_with(|| grouped_exports(source)) else {
                // Keep valid neighboring exports when lexing an incomplete file fails.
                return parsed_exported_names(source);
            };
            if let Some(group) = groups.get(&((line + 1) as u32)) {
                names.extend(group.iter().cloned());
            }
            continue;
        }
        let Some((keyword, rest)) = rest.split_once(char::is_whitespace) else {
            continue;
        };
        let rest = rest.trim_start();
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

/// Group entries start four columns past their export and outside any nested
/// initializer delimiter. Lex once per file, even when it has several groups.
fn grouped_exports(source: &str) -> Option<BTreeMap<u32, Vec<String>>> {
    let file = Arc::from("<import-hints>");
    let lexed = lexer::lex(&file, source).ok()?;
    let tokens = &lexed.tokens;
    let mut groups = BTreeMap::new();
    for (index, export) in tokens.iter().enumerate() {
        if export.kind != Tok::Export
            || export.pos.column != 1
            || tokens.get(index + 1)?.kind != Tok::Let
            || tokens.get(index + 2)?.kind != Tok::LParen
        {
            continue;
        }
        let mut names = Vec::new();
        let mut depth = 1;
        for (index, token) in tokens.iter().enumerate().skip(index + 3) {
            if token.kind == Tok::Name
                && depth == 1
                && token.pos.column == export.pos.column + 4
                && tokens
                    .get(index + 1)
                    .is_some_and(|next| matches!(next.kind, Tok::Assign | Tok::Colon))
            {
                names.push(lexed.source[token.lo as usize..token.hi as usize].to_string());
            }
            if matches!(token.kind, Tok::LParen | Tok::LBracket | Tok::LBrace) {
                depth += 1;
            } else if matches!(token.kind, Tok::RParen | Tok::RBracket | Tok::RBrace) {
                depth -= 1;
                if depth == 0 {
                    break;
                }
            }
        }
        groups.insert(export.pos.line, names);
    }
    Some(groups)
}

fn parsed_exported_names(source: &str) -> Vec<String> {
    let file = Arc::from("<import-hints>");
    let (module, _) = ms_syntax::parse_partial(&file, source);
    module
        .decls
        .into_iter()
        .filter(|decl| decl.export)
        .filter_map(|decl| match decl.kind {
            DeclKind::Fn(function) => Some(function.name.to_string()),
            DeclKind::Const(constant) => Some(constant.name.to_string()),
            DeclKind::Record(record) => Some(record.name.to_string()),
            DeclKind::Alternative(alternative) => Some(alternative.name.to_string()),
            DeclKind::Interface(interface) => Some(interface.name.to_string()),
            DeclKind::Impl(_) | DeclKind::Test(_) => None,
        })
        .collect()
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
        // Graph diagnostics name modules relative to source_root, not the
        // process working directory. Absolute diagnostic paths remain usable.
        let here = if pathops::is_abs(&d.file) {
            pathops::clean(&d.file)
        } else {
            pathops::join(&[source_root, &d.file])
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
        for (file, expected) in [
            (main.as_str(), "./lib/blobs.ms"),
            ("main.ms", "./lib/blobs.ms"),
            ("src/nested/main.ms", "../../lib/blobs.ms"),
        ] {
            let mut found = vec![unknown(file)];
            suggest_project_imports(&mut found, &root);
            assert_eq!(
                found[0].message,
                format!("unknown type Bytes; add: import Bytes from \"{expected}\"")
            );
            assert_eq!(
                found[0].fix.as_ref().unwrap().replacement,
                format!("import Bytes from \"{expected}\"\n")
            );
        }
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn exports_are_read_from_top_level_declarations() {
        let source = "export type A:\n    x: Int\nexport extern fn b() Int\nexport let C = 1\nfn d() Int:\n    return 0\n";
        assert_eq!(exported_names(source), ["A", "b", "C"]);
    }
}
