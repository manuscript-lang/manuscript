//! The thread-affinity rule: `promise(fn:)` may run its entry on any scheduler thread, so a native
//! handle built on `Rc`, `Weak` or `RefCell` races when a promise captures it (#3047). A standard-library
//! crate does not add those types. Handles that must stay thread-bound say so with
//! `ms_std_net::bound::Bound`, which faults on use from another thread; everything else moves to `Arc`,
//! atomics or a lock.
//!
//! `thread-affinity-allowed.txt` lists `path count` for the files that still use them. A file may not
//! exceed its count, and a count that no longer matches fails so the list only shrinks.

use std::collections::BTreeMap;

const ALLOWED: &str = include_str!("../thread-affinity-allowed.txt");

pub fn check(files: &[String]) -> Vec<String> {
    let allowed: BTreeMap<&str, usize> = ALLOWED
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with("//"))
        .filter_map(|l| {
            let (path, count) = l.rsplit_once(' ')?;
            Some((path, count.parse().ok()?))
        })
        .collect();
    let mut issues = Vec::new();
    let mut seen = Vec::new();
    for path in files {
        if !path.starts_with("crates/ms-std-") || !path.ends_with(".rs") || !path.contains("/src/")
        {
            continue;
        }
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let count = source.lines().filter(|l| uses_thread_unsafe(l)).count();
        let limit = allowed.get(path.as_str()).copied().unwrap_or(0);
        if count > 0 {
            seen.push(path.as_str());
        }
        if count > limit {
            issues.push(format!(
                "{path}: {count} lines use Rc, Weak or RefCell (allowed {limit}); a promise may run on another thread, so use Arc, atomics or a lock, or wrap a deliberately thread-bound handle in `Bound`"
            ));
        } else if count < limit {
            issues.push(format!(
                "crates/ms-repo-check/thread-affinity-allowed.txt: `{path}` now has {count} such lines; lower the entry from {limit}{}",
                if count == 0 { " (delete it)" } else { "" }
            ));
        }
    }
    for path in allowed.keys() {
        if !seen.contains(path) && !files.iter().any(|f| f == path) {
            issues.push(format!(
                "crates/ms-repo-check/thread-affinity-allowed.txt: `{path}` no longer exists; delete the line"
            ));
        }
    }
    issues
}

/// Whether a code line names `Rc`, `rc::Weak` or `RefCell` (comments do not count).
fn uses_thread_unsafe(line: &str) -> bool {
    let code = line.split("//").next().unwrap_or("");
    words(code).any(|w| matches!(w, "Rc" | "RefCell"))
        || code.contains("rc::Weak")
        || (code.contains("Weak") && code.contains("rc"))
}

fn words(text: &str) -> impl Iterator<Item = &str> {
    text.split(|c: char| !(c.is_alphanumeric() || c == '_'))
}
