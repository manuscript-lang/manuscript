//! An `extern fn` declares `move` on exactly the parameters its runtime symbol takes or keeps
//! (`@takes:` / `@keeps:` in `ms-lower/rt_symbols.txt`; the runtime names a closure's
//! environment where the declaration names the function value, so counts are compared), so the checker's ownership facts and
//! the code lowering emits agree.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

fn sources(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).expect("stdlib dir") {
        let path = entry.expect("entry").path();
        if path.is_dir() {
            sources(&path, out);
        } else if path.extension().is_some_and(|e| e == "ms") {
            out.push(path);
        }
    }
}

/// Runtime symbol to the parameters its flags say it takes or keeps.
fn runtime_flags(text: &str) -> BTreeMap<String, BTreeSet<String>> {
    let mut flags = BTreeMap::new();
    for line in text.lines().filter(|l| !l.starts_with('#')) {
        let Some((name, _)) = line.split_once('(') else {
            continue;
        };
        let moved: BTreeSet<String> = line
            .split_whitespace()
            .filter_map(|w| {
                w.strip_prefix("@takes:")
                    .or_else(|| w.strip_prefix("@keeps:"))
            })
            .map(str::to_string)
            .collect();
        flags.insert(name.trim().to_string(), moved);
    }
    flags
}

#[test]
fn extern_move_markers_match_the_runtime_flags() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let flags = runtime_flags(
        &std::fs::read_to_string(root.join("crates/ms-lower/rt_symbols.txt")).expect("symbols"),
    );
    let mut files = Vec::new();
    sources(&root.join("src/stdlib"), &mut files);
    let names = ms_syntax::Names::global();
    let mut wrong = Vec::new();
    for path in files {
        let source = std::fs::read_to_string(&path).expect("source");
        let file: Arc<str> = Arc::from(path.to_string_lossy().as_ref());
        let module = ms_syntax::parser::parse(&file, &source).expect("parses");
        for decl in &module.decls {
            let ms_syntax::ast::DeclKind::Fn(f) = &decl.kind else {
                continue;
            };
            if !f.external {
                continue;
            }
            let name = names.str(f.name);
            let Some(expected) = flags.get(name) else {
                continue;
            };
            let declared: BTreeSet<String> = f
                .params
                .iter()
                .filter(|p| p.moving)
                .map(|p| names.str(p.name).to_string())
                .collect();
            if declared.len() != expected.len() {
                wrong.push(format!(
                    "{name}: declares move {declared:?}, runtime takes or keeps {expected:?}"
                ));
            }
        }
    }
    assert!(wrong.is_empty(), "{}", wrong.join("\n"));
}
