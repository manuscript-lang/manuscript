//! Dependency layering of the `ms-std-*` crates, as written in `crates/DESIGN.md`
//! ("Standard-library crate layering"). Reads `[dependencies]` and target-specific
//! dependency tables; dev-dependencies are exempt.

use std::collections::BTreeSet;
use std::fs;

/// Layer 1 and 2: depend on `ms-rt-abi` only.
const FOUNDATION: &[&str] = &["ms-std-core", "ms-std-rt"];
/// Layer 3 crates may use the foundation; these are the only leaf-to-leaf edges, each
/// `(user, used)`. Adding one needs a reason in the change that does it.
const LEAF_EDGES: &[(&str, &str)] = &[
    ("ms-std-archive", "ms-std-compress"),
    ("ms-std-fs", "ms-std-path"),
    ("ms-std-io", "ms-std-fs"),
    ("ms-std-log", "ms-std-json"),
    ("ms-std-process", "ms-std-fs"),
    ("ms-std-process", "ms-std-io"),
    ("ms-std-system", "ms-std-process"),
];
/// Non-std crates that may depend on `ms-std-*` crates, with what they may use
/// (`*` for any). `ms-native` links them all; `ms-lower` folds decimal literals;
/// `ms-rt` hosts the natives that need runtime internals.
const CONSUMERS: &[(&str, &[&str])] = &[
    ("ms-native", &["*"]),
    ("ms-lower", &["ms-std-decimal"]),
    (
        "ms-rt",
        &[
            "ms-std-rt",
            "ms-std-core",
            "ms-std-math",
            "ms-std-time",
            "ms-std-fs",
            "ms-std-io",
            "ms-std-process",
        ],
    ),
];

pub fn check(files: &[String]) -> Vec<String> {
    let mut issues = Vec::new();
    for path in files {
        let Some(krate) = path
            .strip_prefix("crates/")
            .and_then(|p| p.strip_suffix("/Cargo.toml"))
            .filter(|k| !k.contains('/'))
        else {
            continue;
        };
        let Ok(manifest) = fs::read_to_string(path) else {
            continue;
        };
        issues.extend(violations(krate, &dependencies(&manifest)));
    }
    issues
}

/// Names of the `ms-*` path dependencies in non-dev dependency tables.
fn dependencies(manifest: &str) -> BTreeSet<String> {
    let mut found = BTreeSet::new();
    let mut live = false;
    for line in manifest.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            live = (line == "[dependencies]" || line.ends_with(".dependencies]"))
                && !line.contains("dev-dependencies")
                && !line.contains("build-dependencies");
        } else if live
            && let Some((name, _)) = line.split_once('=')
            && name.trim().starts_with("ms-")
        {
            found.insert(name.trim().to_string());
        }
    }
    found
}

fn violations(krate: &str, deps: &BTreeSet<String>) -> Vec<String> {
    let is_std = |c: &str| c.starts_with("ms-std-");
    let mut issues = Vec::new();
    for dep in deps {
        let allowed = if FOUNDATION.contains(&krate) {
            dep == "ms-rt-abi"
        } else if is_std(krate) {
            dep == "ms-rt-abi"
                || FOUNDATION.contains(&dep.as_str())
                || LEAF_EDGES.contains(&(krate, dep.as_str()))
        } else if is_std(dep) {
            CONSUMERS
                .iter()
                .find(|(c, _)| *c == krate)
                .is_some_and(|(_, used)| used.contains(&"*") || used.contains(&dep.as_str()))
        } else {
            true
        };
        if !allowed {
            issues.push(format!(
                "crates/{krate}/Cargo.toml: {krate} may not depend on {dep}; see \"Standard-library crate layering\" in crates/DESIGN.md and crates/ms-repo-check/src/layering.rs"
            ));
        }
    }
    issues
}

#[cfg(test)]
mod tests {
    use super::*;

    fn deps(names: &[&str]) -> BTreeSet<String> {
        names.iter().map(|n| n.to_string()).collect()
    }

    #[test]
    fn reads_normal_and_target_tables_not_dev() {
        let manifest = "[dependencies]\nms-std-core = { path = \"x\" }\nserde = \"1\"\n[target.'cfg(unix)'.dependencies]\nms-std-rt = { path = \"y\" }\n[dev-dependencies]\nms-rt = { path = \"z\" }\n";
        assert_eq!(dependencies(manifest), deps(&["ms-std-core", "ms-std-rt"]));
    }

    #[test]
    fn foundation_stays_below_leaves() {
        assert!(violations("ms-std-core", &deps(&["ms-rt-abi"])).is_empty());
        assert_eq!(violations("ms-std-core", &deps(&["ms-std-rt"])).len(), 1);
        assert_eq!(violations("ms-std-rt", &deps(&["ms-std-core"])).len(), 1);
    }

    #[test]
    fn leaves_use_foundation_and_listed_edges_only() {
        assert!(violations("ms-std-io", &deps(&["ms-std-core", "ms-std-fs"])).is_empty());
        assert_eq!(violations("ms-std-io", &deps(&["ms-std-net"])).len(), 1);
        assert_eq!(violations("ms-std-net", &deps(&["ms-std-fs"])).len(), 1);
    }

    #[test]
    fn only_listed_consumers_use_std_crates() {
        assert!(violations("ms-native", &deps(&["ms-std-net"])).is_empty());
        assert!(violations("ms-lower", &deps(&["ms-std-decimal"])).is_empty());
        assert_eq!(violations("ms-lower", &deps(&["ms-std-net"])).len(), 1);
        assert_eq!(violations("ms-check", &deps(&["ms-std-core"])).len(), 1);
        assert!(violations("ms-check", &deps(&["ms-syntax"])).is_empty());
    }
}
