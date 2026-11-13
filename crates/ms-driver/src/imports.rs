//! Import suggestions for unresolved names that a project module exports.
//!
//! The checker only knows standard modules, so its `add: import ... from "@std/..."` hint
//! cannot name a sibling file nobody imported yet. This pass scans the project's
//! `.ms` files for top-level `export` declarations and, for an unknown name one
//! of them exports, replaces the hint with that file's import (preferred over a
//! standard-library one).

use std::collections::{BTreeMap, BTreeSet};
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
pub fn exported_names(syms: ms_syntax::Names, source: &str) -> Vec<String> {
    exported_declarations(syms, source)
        .into_iter()
        .map(|export| export.name)
        .collect()
}

/// A project export's name and whether it can resolve a type annotation.
pub struct Export {
    pub name: String,
    pub is_type: bool,
}

/// Export headers with their declaration kind, including recovered neighbors.
pub fn exported_declarations(syms: ms_syntax::Names, source: &str) -> Vec<Export> {
    let mut names = Vec::new();
    let mut headers = None;
    for (line, text) in source.lines().enumerate() {
        let Some(rest) = text.strip_prefix("export ") else {
            continue;
        };
        // A column-zero `export` inside a block comment or multi-line text declares nothing; only
        // a lexer `export` token does. Sources without such lines never lex.
        let Some(headers) = headers.get_or_insert_with(|| export_headers(source)) else {
            // Keep valid neighboring exports when lexing an incomplete file fails.
            return parsed_exported_names(syms, source);
        };
        if !headers.contains(&((line + 1) as u32)) {
            continue;
        }
        let rest = rest.trim_start();
        let rest = rest
            .strip_prefix("extern ")
            .or_else(|| rest.strip_prefix("opaque "))
            .unwrap_or(rest)
            .trim_start();
        // A declaration keyword, or a constant `NAME := value` / `NAME: Type := value`.
        let (keyword, rest) = match rest.split_once(char::is_whitespace) {
            Some((keyword, tail)) if matches!(keyword, "fn" | "type" | "enum" | "interface") => {
                (keyword, tail.trim_start())
            }
            _ => ("", rest),
        };
        let name: String = rest
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
            .collect();
        if keyword.is_empty() && !rest[name.len()..].trim_start().starts_with(':') {
            continue;
        }
        if !name.is_empty() {
            names.push(Export {
                name,
                is_type: matches!(keyword, "type" | "enum" | "interface"),
            });
        }
    }
    names
}

/// Whether the file at `path` names `name` in one of its `import` declarations.
fn imports_name(path: &str, name: &str) -> bool {
    let Ok(source) = std::fs::read_to_string(path) else {
        return false;
    };
    let file = Arc::from("<import-hints>");
    let Ok(lexed) = lexer::lex(&file, &source) else {
        return false;
    };
    let mut in_import = false;
    for token in &lexed.tokens {
        match token.kind {
            Tok::Import => in_import = true,
            Tok::Newline | Tok::Eof => in_import = false,
            Tok::Name
                if in_import && source.get(token.lo as usize..token.hi as usize) == Some(name) =>
            {
                return true;
            }
            _ => {}
        }
    }
    false
}

/// The lines where a real `export` token starts in column one.
fn export_headers(source: &str) -> Option<BTreeSet<u32>> {
    let file = Arc::from("<import-hints>");
    let lexed = lexer::lex(&file, source).ok()?;
    Some(
        lexed
            .tokens
            .iter()
            .filter(|token| token.kind == Tok::Export && token.pos.column == 1)
            .map(|token| token.pos.line)
            .collect(),
    )
}

fn parsed_exported_names(syms: ms_syntax::Names, source: &str) -> Vec<Export> {
    let file = Arc::from("<import-hints>");
    let (module, _) = ms_syntax::parse_partial(&file, source);
    module
        .decls
        .into_iter()
        .filter(|decl| decl.export)
        .filter_map(|decl| match decl.kind {
            DeclKind::Fn(function) => Some((function.name, false)),
            DeclKind::Const(constant) => Some((constant.name, false)),
            DeclKind::Type(decl) => Some((decl.name, true)),
            DeclKind::Alternative(alternative) => Some((alternative.name, true)),
            DeclKind::Alias(alias) => Some((alias.name, true)),
            DeclKind::Interface(interface) => Some((interface.name, true)),
            DeclKind::Impl(_) | DeclKind::Test(_) => None,
        })
        .map(|(name, is_type)| Export {
            name: syms.str(name).to_string(),
            is_type,
        })
        .collect()
}

/// A new leading import goes after a blank-terminated initial comment block.
/// Otherwise it would move file-wide effect permissions below the first import.
pub fn import_position(source: &str) -> Pos {
    let mut offset = 0;
    let mut comments = 0;
    for line in source.split_inclusive('\n') {
        if line.trim_start().starts_with("//") {
            offset += line.len();
            comments += 1;
        } else if comments > 0 && line.trim().is_empty() {
            return Pos::new((offset + line.len()) as u32, comments + 2, 1);
        } else {
            break;
        }
    }
    Pos::new(0, 1, 1)
}

/// A source import statement, with its module path quoted as Manuscript text.
pub fn import_statement(name: &str, path: &str) -> String {
    let mut literal = String::from("\"");
    for c in path.chars() {
        match c {
            '\\' | '"' | '{' | '}' => {
                literal.push('\\');
                literal.push(c);
            }
            '\n' => literal.push_str("\\n"),
            '\r' => literal.push_str("\\r"),
            '\t' => literal.push_str("\\t"),
            c if c.is_control()
                || matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}') =>
            {
                use std::fmt::Write;
                let _ = write!(literal, "\\u{{{:X}}}", c as u32);
            }
            c => literal.push(c),
        }
    }
    literal.push('"');
    format!("import {name} from {literal}")
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
    let relative = pathops::rel(dir, target).ok()?;
    // Native Windows separators are already normalized by `rel`. A remaining
    // backslash is a Unix filename byte, which the import-path grammar rejects.
    if relative.contains('\\') {
        return None;
    }
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
pub fn suggest_project_imports(
    syms: ms_syntax::Names,
    diagnostics: &mut [Diagnostic],
    source_root: &str,
) {
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
    let mut exports: BTreeMap<String, Vec<(String, bool)>> = BTreeMap::new();
    for file in files {
        let Ok(data) = std::fs::read(&file) else {
            continue;
        };
        for export in exported_declarations(syms, &String::from_utf8_lossy(&data)) {
            exports
                .entry(export.name)
                .or_default()
                .push((file.clone(), export.is_type));
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
        // A name the file already imports failed to resolve at that import; a second
        // import of the same name would not fix it.
        if imports_name(&here, &name) {
            continue;
        }
        let dir = pathops::dir(&here);
        let types_only = d.message.starts_with("unknown type ");
        let paths: Vec<String> = candidates
            .iter()
            .filter(|(file, is_type)| *file != here && (!types_only || *is_type))
            .filter_map(|(file, _)| import_path(&dir, file))
            .collect();
        let head = d.message.split(';').next().unwrap_or("").to_string();
        match paths.as_slice() {
            [] => {}
            [path] => {
                let statement = import_statement(&name, path);
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
            cause: Default::default(),
            opener_line: 0,
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
        let syms = ms_syntax::Names::global();
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
            suggest_project_imports(syms, &mut found, &root);
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
        let syms = ms_syntax::Names::global();
        let source = "export type A:\n    x: Int\nexport extern fn b() Int\nexport C := 1\nfn d() Int:\n    return 0\n";
        assert_eq!(exported_names(syms, source), ["A", "b", "C"]);
    }
}
