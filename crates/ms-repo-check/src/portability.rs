//! Paths and line endings that must read the same on Linux, macOS and Windows.
//! Embedded standard-library sources, recorded corpora and import specifiers
//! are compared byte for byte, so a carriage return or a backslash that only
//! some checkouts produce becomes a platform-only failure.

use std::collections::HashMap;
use std::fs;

/// Windows device names; a file with one of these stems cannot be created there.
const RESERVED: &[&str] = &[
    "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8",
    "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
];

/// Extensions whose bytes tests compare, so they must be LF-only in every checkout.
const TEXT: &[&str] = &[
    "ms", "toml", "json", "md", "rs", "sh", "yml", "yaml", "txt", "src", "py", "html", "css",
];

pub fn check(files: &[String]) -> Vec<String> {
    let mut issues = Vec::new();
    issues.extend(attributes());
    issues.extend(path_names(files));
    issues.extend(line_endings(files));
    issues.extend(stdlib_imports(files));
    issues
}

/// `.gitattributes` must keep source and corpora LF on Windows checkouts.
fn attributes() -> Vec<String> {
    let Ok(text) = fs::read_to_string(".gitattributes") else {
        return vec![".gitattributes: missing".into()];
    };
    let mut issues = Vec::new();
    for rule in [
        "*.ms text eol=lf",
        "*.toml text eol=lf",
        "* text=auto eol=lf",
    ] {
        if !text.lines().any(|l| l.trim() == rule) {
            issues.push(format!(".gitattributes: missing the rule `{rule}`"));
        }
    }
    issues
}

/// Tracked paths must be creatable and distinct on case-insensitive,
/// reserved-name-aware file systems.
fn path_names(files: &[String]) -> Vec<String> {
    let mut issues = Vec::new();
    let mut folded: HashMap<String, &str> = HashMap::new();
    for path in files {
        if let Some(other) = folded.insert(path.to_lowercase(), path)
            && other != path
        {
            issues.push(format!("{path}: differs from {other} only by case"));
        }
        for part in path.split('/') {
            let stem = part.split('.').next().unwrap_or(part).to_lowercase();
            if RESERVED.contains(&stem.as_str()) {
                issues.push(format!("{path}: `{part}` is a reserved name on Windows"));
            }
            if part.ends_with('.') || part.ends_with(' ') {
                issues.push(format!("{path}: `{part}` ends in a dot or space"));
            }
            if part.contains(['<', '>', ':', '"', '\\', '|', '?', '*']) {
                issues.push(format!("{path}: `{part}` has a character Windows rejects"));
            }
        }
    }
    issues
}

/// No carriage returns in text the tests compare byte for byte.
fn line_endings(files: &[String]) -> Vec<String> {
    files
        .iter()
        .filter(|p| !crate::skipped(p))
        .filter(|p| {
            p.rsplit('.')
                .next()
                .is_some_and(|ext| TEXT.contains(&ext) && p.contains('.'))
        })
        .filter(|p| fs::read(p).is_ok_and(|bytes| bytes.contains(&b'\r')))
        .map(|p| format!("{p}: contains a carriage return; store it with LF line endings"))
        .collect()
}

/// Standard-library import specifiers are `@std/…` or `./…` with forward slashes.
fn stdlib_imports(files: &[String]) -> Vec<String> {
    let mut issues = Vec::new();
    for path in files
        .iter()
        .filter(|p| p.starts_with("stdlib/") && p.ends_with(".ms"))
    {
        let Ok(source) = fs::read_to_string(path) else {
            continue;
        };
        for (number, line) in source.lines().enumerate() {
            let line = line.trim_start();
            if !(line.starts_with("from \"") || line.starts_with("import \"")) {
                continue;
            }
            let spec = line.split('"').nth(1).unwrap_or("");
            let local = spec.starts_with("./") || spec.starts_with("../");
            if spec.contains('\\') || !(spec.starts_with("@std/") || local) {
                issues.push(format!(
                    "{path}:{}: import `{spec}` is not a forward-slash `@std/` or relative path",
                    number + 1
                ));
            }
        }
    }
    issues
}

#[cfg(test)]
mod tests {
    use super::path_names;

    #[test]
    fn flags_case_collisions_and_reserved_names() {
        let files = ["a/Lib.ms", "a/lib.ms", "b/aux.ms", "c/ok.ms"].map(String::from);
        let issues = path_names(&files);
        assert_eq!(issues.len(), 2, "{issues:?}");
    }
}
