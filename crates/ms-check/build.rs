//! Embeds `stdlib/*.ms` and `stdlib/*/*.ms`. The files in `stdlib/core/` are the implicit prelude; they keep
//! their flat `@std/<file>.ms` paths, so the directory groups them without changing any import.

use std::fmt::Write as _;
use std::path::PathBuf;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"));
    let dir = manifest
        .join("../../stdlib")
        .canonicalize()
        .expect("stdlib");
    println!("cargo:rerun-if-changed={}", dir.display());
    let mut names: Vec<String> = Vec::new();
    for entry in std::fs::read_dir(&dir)
        .expect("read stdlib")
        .filter_map(|e| e.ok())
    {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.ends_with(".ms") {
            names.push(name);
        } else if entry.path().is_dir() {
            for inner in std::fs::read_dir(entry.path())
                .expect("read stdlib dir")
                .filter_map(|e| e.ok())
            {
                let inner = inner.file_name().to_string_lossy().into_owned();
                if inner.ends_with(".ms") {
                    names.push(if name == "core" {
                        inner
                    } else {
                        format!("{name}/{inner}")
                    });
                }
            }
        }
    }
    names.sort();
    let texts: Vec<String> = names
        .iter()
        .map(|name| std::fs::read_to_string(source_path(&dir, name)).expect("read stdlib module"))
        .collect();
    let eager = eager_modules(&names, &texts);
    let mut out = String::from(
        "/// Bundled standard declarations in file-name order, and whether each loads with the standard declarations.\npub const SOURCES: &[(&str, &str, bool)] = &[\n",
    );
    for (i, name) in names.iter().enumerate() {
        let path = source_path(&dir, name);
        println!("cargo:rerun-if-changed={}", path.display());
        writeln!(
            out,
            "    ({name:?}, include_str!({:?}), {}),",
            path.display().to_string(),
            eager[i]
        )
        .unwrap();
    }
    out.push_str("];\n");
    runtime_facts(&manifest, &mut out);
    let dest = PathBuf::from(std::env::var("OUT_DIR").expect("out dir")).join("std_sources.rs");
    std::fs::write(dest, out).expect("write");
}

/// The file that holds a bundled module: the prelude files live in `stdlib/core/` but are named flat.
fn source_path(dir: &std::path::Path, name: &str) -> PathBuf {
    let flat = dir.join(name);
    if flat.exists() {
        flat
    } else {
        dir.join("core").join(name)
    }
}

/// The ownership facts the checker reads from the runtime's declarations (`rt_symbols.txt`, written
/// by `cargo xtask symbols`): the externs that keep the function values they are given
/// (`@keeps:`), and the value parameters a runtime function takes ownership of (`@takes:`).
fn runtime_facts(manifest: &std::path::Path, out: &mut String) {
    let path = manifest.join("../ms-lower/rt_symbols.txt");
    println!("cargo:rerun-if-changed={}", path.display());
    let table = std::fs::read_to_string(&path).expect("read rt_symbols.txt");
    let mut keeps = Vec::new();
    let mut takes = Vec::new();
    for line in table.lines().filter(|l| !l.starts_with('#')) {
        let name = line.split('(').next().unwrap_or_default();
        let flags = line.split(" @").skip(1);
        for flag in flags {
            if flag.starts_with("keeps:") && keeps.last() != Some(&name) {
                keeps.push(name);
            }
            if let Some(param) = flag.strip_prefix("takes:") {
                takes.push((name, param));
            }
        }
    }
    writeln!(
        out,
        "/// Runtime functions that keep the function values they are given."
    )
    .unwrap();
    writeln!(out, "pub const RUNTIME_KEEPS: &[&str] = &{keeps:?};").unwrap();
    writeln!(
        out,
        "/// Runtime functions and the value parameter each takes ownership of."
    )
    .unwrap();
    writeln!(
        out,
        "pub const RUNTIME_TAKES: &[(&str, &str)] = &{takes:?};"
    )
    .unwrap();
}

#[path = "src/bundled.rs"]
mod bundled;

/// Modules the standard declarations need at load: every module that is not pure source, the extension
/// modules every program uses, and everything they import. The rest load when a program first imports them.
fn eager_modules(names: &[String], texts: &[String]) -> Vec<bool> {
    let extension = |name: &str| {
        bundled::EXTENSION_MODULES
            .iter()
            .any(|path| path.trim_end_matches("+source") == format!("@std/{name}"))
    };
    let parsed: Vec<ms_syntax::ast::Module> = names
        .iter()
        .zip(texts)
        .map(|(name, text)| {
            let file: std::sync::Arc<str> = std::sync::Arc::from(format!("@std/{name}").as_str());
            ms_syntax::parser::parse(&file, text)
                .unwrap_or_else(|d| panic!("parse stdlib/{name}: {d}"))
        })
        .collect();
    let mut eager = vec![false; names.len()];
    let mut stack: Vec<usize> = (0..names.len())
        .filter(|&i| extension(&names[i]) || !bundled::is_pure_source(&parsed[i]))
        .collect();
    while let Some(i) = stack.pop() {
        if eager[i] {
            continue;
        }
        eager[i] = true;
        for import in &parsed[i].imports {
            let path = import.path.strip_prefix("@std/").unwrap_or(&import.path);
            if let Some(j) = names.iter().position(|n| n == path) {
                stack.push(j);
            }
        }
    }
    eager
}
