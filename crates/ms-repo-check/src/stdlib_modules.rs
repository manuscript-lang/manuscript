//! What the standard-library source rules share: reading and parsing `stdlib/*.ms`, and the
//! only-shrinking allow-lists that record violations predating a rule.

use ms_syntax::ast::Module;
use ms_syntax::parser::parse;
use std::collections::BTreeSet;
use std::sync::Arc;

/// Each parsed standard-library module among `files`, with its path. Files that cannot be read or parsed
/// are skipped; the compiler reports those.
pub fn parsed(files: &[String]) -> impl Iterator<Item = (&str, Module)> {
    files
        .iter()
        .map(String::as_str)
        .filter(|p| p.starts_with("stdlib/") && p.ends_with(".ms"))
        .filter_map(|path| {
            let source = std::fs::read_to_string(path).ok()?;
            let file: Arc<str> = Arc::from(path);
            Some((path, parse(&file, &source).ok()?))
        })
}

/// The `path entry` lines of an allow-list file, without blanks and `//` comments.
pub fn allow_list(text: &str) -> BTreeSet<&str> {
    text.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with("//"))
        .collect()
}

/// Checks `found` `(path, entry)` pairs against an allow-list that may only shrink: an entry outside the
/// list is reported with `violation(path, entry)`, and a listed entry that nothing found is reported
/// with `stale(entry)`.
pub fn check_shrinking(
    allowed: &BTreeSet<&str>,
    found: impl IntoIterator<Item = (String, String)>,
    violation: impl Fn(&str, &str) -> String,
    stale: impl Fn(&str) -> String,
) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut issues = Vec::new();
    for (path, entry) in found {
        let key = format!("{path} {entry}");
        if allowed.contains(key.as_str()) {
            seen.insert(key);
        } else {
            issues.push(violation(&path, &entry));
        }
    }
    issues.extend(
        allowed
            .iter()
            .filter(|e| !seen.contains(**e))
            .map(|e| stale(e)),
    );
    issues
}
