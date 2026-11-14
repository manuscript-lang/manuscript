//! Crate layering: which workspace crates each compiler or tool crate may depend on.
//!
//! The layers, lowest first:
//!
//! ```text
//! ms-syntax  ->  ms-check  ->  ms-lower  ->  ms-clif / ms-mir-llvm / ms-build
//!                    \->  ms-driver, ms-tooling  ->  ms-lsp  ->  ms-cli
//! ```
//!
//! The runtime (`ms-rt-abi`, `ms-rt`, `ms-std-*`, `ms-native`) is a
//! separate world. The compiler meets it only through the C ABI described by
//! `ms-rt-abi`, so a runtime crate never depends on a compiler crate and a
//! compiler crate never depends on a runtime crate other than `ms-rt-abi`.
//! Test-only edges belong in `[dev-dependencies]`, which this check ignores.
//!
//! Widening a row below needs a reason beside it, in the same change.

use std::fs;

/// Allowed normal dependencies on other workspace crates, per compiler or tool crate.
const COMPILER_AND_TOOLS: &[(&str, &[&str])] = &[
    ("ms-syntax", &[]),
    ("ms-json", &[]),
    // `ms-mir` owns machine layout (`layout.rs`), which needs the runtime's value sizes.
    ("ms-mir", &["ms-rt-abi"]),
    ("ms-decimal", &[]),
    ("ms-check", &["ms-syntax"]),
    // `ms-decimal` is pure arithmetic: lowering folds Decimal literals with it.
    (
        "ms-lower",
        &["ms-check", "ms-mir", "ms-rt-abi", "ms-decimal"],
    ),
    // The two code generators know nothing of each other: `ms-mir-llvm` depends on MIR and the
    // ABI only, and `ms-build` runs it for release builds.
    ("ms-mir-llvm", &["ms-mir", "ms-rt-abi"]),
    ("ms-clif", &["ms-mir", "ms-rt-abi"]),
    (
        "ms-build",
        &["ms-check", "ms-clif", "ms-lower", "ms-mir", "ms-mir-llvm"],
    ),
    ("ms-driver", &["ms-check", "ms-syntax"]),
    ("ms-tooling", &["ms-check", "ms-json", "ms-syntax"]),
    (
        "ms-lsp",
        &[
            "ms-check",
            "ms-driver",
            "ms-json",
            "ms-syntax",
            "ms-tooling",
        ],
    ),
    (
        "ms-cli",
        &[
            "ms-build",
            "ms-check",
            "ms-driver",
            "ms-json",
            "ms-lsp",
            "ms-mir",
            "ms-rt-abi",
            "ms-syntax",
            "ms-tooling",
        ],
    ),
];

/// Pure arithmetic both worlds use: the compiler folds literals with it and the runtime wraps it.
const SHARED: &str = "ms-decimal";

const RUNTIME: &[&str] = &["ms-rt-abi", "ms-rt", "ms-std-", "ms-native"];

fn is_runtime(name: &str) -> bool {
    RUNTIME.iter().any(|r| name.starts_with(r))
}

pub fn check(files: &[String]) -> Vec<String> {
    let mut issues = crates(files);
    issues.extend(editor_is_a_leaf(files));
    issues
}

/// Editor queries (`editor.rs`) sit on top of the checker; the checker never calls back into them.
/// Only the public `api`, the module list and tests may name the module.
fn editor_is_a_leaf(files: &[String]) -> Vec<String> {
    let sources = files.iter().filter(|p| {
        p.starts_with("crates/ms-check/src/") && p.ends_with(".rs") && !allowed_to_name_editor(p)
    });
    sources
        .filter(|path| fs::read_to_string(path).is_ok_and(|text| text.contains("crate::editor")))
        .map(|path| {
            format!("{path}: checker code must not depend on `crate::editor` (editor queries are a leaf); see crates/ms-repo-check/src/layering.rs")
        })
        .collect()
}

fn allowed_to_name_editor(path: &str) -> bool {
    let file = path.rsplit('/').next().unwrap_or(path);
    matches!(file, "api.rs" | "editor.rs") || file.ends_with("_tests.rs")
}

fn crates(files: &[String]) -> Vec<String> {
    let manifests = files
        .iter()
        .filter(|p| p.starts_with("crates/") && p.ends_with("/Cargo.toml"));
    let mut issues = Vec::new();
    for path in manifests {
        let Ok(text) = fs::read_to_string(path) else {
            continue;
        };
        let Some(name) = package_name(&text) else {
            continue;
        };
        for dep in normal_dependencies(&text) {
            if let Some(why) = violation(&name, &dep) {
                issues.push(format!(
                    "{path}: {name} -> {dep}: {why}; see crates/ms-repo-check/src/layering.rs"
                ));
            }
        }
    }
    issues
}

fn violation(name: &str, dep: &str) -> Option<&'static str> {
    if is_runtime(name) {
        let compiler = dep != SHARED && COMPILER_AND_TOOLS.iter().any(|(c, _)| *c == dep);
        return compiler.then_some("a runtime crate must not depend on a compiler crate");
    }
    let (_, allowed) = COMPILER_AND_TOOLS.iter().find(|(c, _)| *c == name)?;
    (!allowed.contains(&dep)).then_some("not in this crate's allowed dependencies")
}

fn package_name(manifest: &str) -> Option<String> {
    let line = manifest.lines().find(|l| l.starts_with("name = "))?;
    Some(line.split('"').nth(1)?.to_string())
}

/// Workspace (`ms-*`) crates named in the `[dependencies]` table only.
fn normal_dependencies(manifest: &str) -> Vec<String> {
    let mut in_table = false;
    let mut found = Vec::new();
    for line in manifest.lines() {
        if line.starts_with('[') {
            in_table = line.trim() == "[dependencies]";
            continue;
        }
        let key = line.split(['=', '.', ' ']).next().unwrap_or("");
        if in_table && key.starts_with("ms-") {
            found.push(key.to_string());
        }
    }
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compiler_crate_may_not_reach_the_runtime() {
        assert!(violation("ms-lower", "ms-rt").is_some());
        assert!(violation("ms-lower", "ms-rt-abi").is_none());
    }

    #[test]
    fn runtime_crate_may_not_reach_the_compiler() {
        assert!(violation("ms-std-fs", "ms-check").is_some());
        assert!(violation("ms-std-fs", "ms-std-path").is_none());
    }

    #[test]
    fn dev_dependencies_are_ignored() {
        let manifest = "[dependencies]\nms-check = { path = \"../ms-check\" }\n[dev-dependencies]\nms-rt = { path = \"../ms-rt\" }\n";
        assert_eq!(normal_dependencies(manifest), ["ms-check"]);
    }

    #[test]
    fn only_the_api_editor_and_tests_may_name_the_editor_module() {
        assert!(allowed_to_name_editor("crates/ms-check/src/api.rs"));
        assert!(allowed_to_name_editor("crates/ms-check/src/x_tests.rs"));
        assert!(!allowed_to_name_editor("crates/ms-check/src/calls.rs"));
    }
}
