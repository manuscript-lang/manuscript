//! The timed-wait rule: a wait that wakes on a period to see whether something changed makes the
//! runtime fragile, burns CPU while idle and misses what happens between looks. Wait on the event
//! instead; a deadline with a meaning (a user timeout, a grace period, a policy) is fine and is a
//! single wait armed by an event. New calls that sleep or wait with a timeout need an entry, with
//! the reason, in `timed-waits-allowed.txt`.
//!
//! A file may not exceed its count, and a count that no longer matches fails so the list only
//! shrinks. Comments do not count.

use std::collections::BTreeMap;

const ALLOWED: &str = include_str!("../timed-waits-allowed.txt");

pub fn check(files: &[String]) -> Vec<String> {
    let mut allowed: BTreeMap<&str, usize> = BTreeMap::new();
    let mut issues = Vec::new();
    for line in ALLOWED.lines().map(str::trim) {
        if line.is_empty() || line.starts_with("//") {
            continue;
        }
        let mut parts = line.splitn(3, ' ');
        let (Some(path), Some(count), reason) = (parts.next(), parts.next(), parts.next()) else {
            continue;
        };
        match (count.parse::<usize>(), reason.map(str::trim)) {
            (Ok(count), Some(reason)) if !reason.is_empty() => {
                allowed.insert(path, count);
            }
            _ => issues.push(format!(
                "crates/ms-repo-check/timed-waits-allowed.txt: `{line}` needs `path count reason`"
            )),
        }
    }
    for path in files {
        if !path.starts_with("crates/")
            || !path.ends_with(".rs")
            || path.ends_with("ms-repo-check/src/timed_waits.rs")
        {
            continue;
        }
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let count = source.lines().filter(|l| waits_on_time(l)).count();
        let limit = allowed.get(path.as_str()).copied().unwrap_or(0);
        if count > limit {
            issues.push(format!(
                "{path}: {count} calls sleep or wait with a timeout (allowed {limit}); wait on the event instead, or if this is a deadline with a meaning add the file to crates/ms-repo-check/timed-waits-allowed.txt with the reason"
            ));
        } else if count < limit {
            issues.push(format!(
                "crates/ms-repo-check/timed-waits-allowed.txt: `{path}` now has {count} such calls; lower the entry from {limit}{}",
                if count == 0 { " (delete it)" } else { "" }
            ));
        }
    }
    for path in allowed.keys() {
        if !files.iter().any(|f| f == path) {
            issues.push(format!(
                "crates/ms-repo-check/timed-waits-allowed.txt: `{path}` no longer exists; delete the line"
            ));
        }
    }
    issues
}

/// Whether a code line calls something that sleeps or waits with a timeout (comments do not count).
fn waits_on_time(line: &str) -> bool {
    let code = line.split("//").next().unwrap_or("");
    ["sleep(", "park_timeout(", "recv_timeout(", "wait_timeout"]
        .iter()
        .any(|needle| code.contains(needle))
}
