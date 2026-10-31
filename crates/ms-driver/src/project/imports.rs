//! The `[imports]` allow list: which modules each file may import.
//!
//! A rule maps an importer pattern to the patterns its imports must match. Patterns are
//! project-relative paths with `/` separators; `*` matches within one path segment and `**`
//! matches any number of segments. Standard modules are matched by their `@std/name.ms`
//! spelling, and `extern fn` declarations by the word `extern`. The matching rule with the
//! longest literal prefix (the text before its first `*`) decides; a file matching no rule, or
//! a project without the table, is unrestricted.

use crate::project::error::Location;
use crate::project::manifest::Project;
use crate::project::pathops;

/// One `[imports]` assignment: `"src/**" = ["src/**", "@std/json.ms"]`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ImportRule {
    pub pattern: String,
    pub allowed: Vec<String>,
    pub location: Location,
}

/// Whether `importer` (a canonical path under the project root) may import `target`:
/// a canonical local path, an `@std/` spelling, or `extern` for an `extern fn` declaration.
/// The error is a complete diagnostic message.
pub fn check_import(project: &Project, importer: &str, target: &str) -> Result<(), String> {
    if project.imports.is_empty() {
        return Ok(());
    }
    let Some(importer_rel) = project_relative(project, importer) else {
        // A symlink can resolve a source file outside the root; with a table present, such a
        // file matches no rule by construction, so it fails closed instead of escaping every rule.
        return Err(format!(
            "{importer} is outside the project root, so ms.toml [imports] cannot place it; keep source files inside the directory containing ms.toml"
        ));
    };
    let Some(rule) = rule_for(project, &importer_rel)? else {
        return Ok(());
    };
    let target_rel = if target.starts_with("@std/") || target == "extern" {
        target.to_string()
    } else {
        project_relative(project, target).unwrap_or_else(|| target.to_string())
    };
    if rule.allowed.iter().any(|p| matches(p, &target_rel)) {
        return Ok(());
    }
    Err(format!(
        "{importer_rel} may not import {target_rel}; ms.toml [imports] \"{}\" allows only {}, so import one of those or extend the list",
        rule.pattern,
        rule.allowed
            .iter()
            .map(|p| format!("\"{p}\""))
            .collect::<Vec<_>>()
            .join(", ")
    ))
}

fn project_relative(project: &Project, path: &str) -> Option<String> {
    let rel = pathops::rel(&project.root, path).ok()?;
    if pathops::escapes(&rel) || rel == "." {
        return None;
    }
    Some(rel)
}

/// The rule whose pattern matches `file` with the longest literal prefix.
fn rule_for<'a>(project: &'a Project, file: &str) -> Result<Option<&'a ImportRule>, String> {
    let mut best: Option<(&ImportRule, usize)> = None;
    let mut tied: Option<&ImportRule> = None;
    for rule in &project.imports {
        if !matches(&rule.pattern, file) {
            continue;
        }
        let prefix = literal_prefix(&rule.pattern);
        match best {
            Some((_, length)) if prefix < length => {}
            Some((_, length)) if prefix == length => tied = Some(rule),
            _ => {
                best = Some((rule, prefix));
                tied = None;
            }
        }
    }
    match (best, tied) {
        (Some((first, _)), Some(second)) => Err(format!(
            "ms.toml [imports] patterns \"{}\" and \"{}\" both match {file} with the same literal prefix; make one more specific",
            first.pattern, second.pattern
        )),
        (best, _) => Ok(best.map(|(rule, _)| rule)),
    }
}

fn literal_prefix(pattern: &str) -> usize {
    pattern.find('*').unwrap_or(pattern.len())
}

/// Why `pattern` is not a valid `[imports]` pattern, if it is not.
pub fn pattern_problem(pattern: &str) -> Option<&'static str> {
    if pattern.is_empty() || pattern.starts_with('/') || pattern.contains('\\') {
        return Some("patterns are project-relative paths with / separators");
    }
    if pattern.split('/').any(|s| s.contains("**") && s != "**") {
        return Some("** stands alone as a path segment, as in src/** or **/gen/*.ms");
    }
    None
}

/// Glob match over `/`-separated segments.
pub fn matches(pattern: &str, path: &str) -> bool {
    let pattern: Vec<&str> = pattern.split('/').collect();
    let path: Vec<&str> = path.split('/').collect();
    segments(&pattern, &path)
}

fn segments(pattern: &[&str], path: &[&str]) -> bool {
    match pattern.split_first() {
        None => path.is_empty(),
        Some((&"**", rest)) => (0..=path.len()).any(|skip| segments(rest, &path[skip..])),
        Some((first, rest)) => match path.split_first() {
            Some((segment, remaining)) => {
                segment_matches(first, segment) && segments(rest, remaining)
            }
            None => false,
        },
    }
}

fn segment_matches(pattern: &str, segment: &str) -> bool {
    match pattern.split_once('*') {
        None => pattern == segment,
        Some((head, tail)) => {
            segment.starts_with(head)
                && segment.len() >= head.len()
                && segment_matches_tail(tail, &segment[head.len()..])
        }
    }
}

fn segment_matches_tail(pattern: &str, segment: &str) -> bool {
    match pattern.split_once('*') {
        None => segment.ends_with(pattern),
        Some((head, tail)) => segment
            .match_indices(head)
            .any(|(at, _)| segment_matches_tail(tail, &segment[at + head.len()..])),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn glob_segments() {
        assert!(matches("src/**", "src/a/b.ms"));
        assert!(matches("src/**", "src/a.ms"));
        assert!(!matches("src/**", "lib/a.ms"));
        assert!(matches("**", "@std/fs.ms"));
        assert!(matches("@std/**", "@std/fs.ms"));
        assert!(matches("@std/j*.ms", "@std/json.ms"));
        assert!(!matches("@std/j*.ms", "@std/jsonx/a.ms"));
        assert!(matches("**/gen/*.ms", "src/x/gen/a.ms"));
        assert!(matches("**/gen/*.ms", "gen/a.ms"));
        assert!(!matches("**/gen/*.ms", "src/gen/a/b.ms"));
        assert!(matches("src/*_test.ms", "src/a_test.ms"));
        assert!(!matches("src/*_test.ms", "src/a.ms"));
        assert!(matches("*a*b*", "xaybz"));
        assert!(!matches("*a*b*", "xbya"));
    }

    fn project(rules: &[(&str, &[&str])]) -> Project {
        Project {
            root: "/p".to_string(),
            imports: rules
                .iter()
                .map(|(pattern, allowed)| ImportRule {
                    pattern: pattern.to_string(),
                    allowed: allowed.iter().map(|s| s.to_string()).collect(),
                    location: Location::default(),
                })
                .collect(),
            ..Project::default()
        }
    }

    #[test]
    fn most_specific_rule_decides() {
        let p = project(&[
            ("src/**", &["src/**", "@std/json.ms"]),
            ("src/gen/**", &["**"]),
            ("types/**", &["@std/**"]),
        ]);
        assert!(check_import(&p, "/p/src/a.ms", "/p/src/b.ms").is_ok());
        assert!(check_import(&p, "/p/src/a.ms", "@std/json.ms").is_ok());
        assert!(check_import(&p, "/p/src/gen/a.ms", "@std/fs.ms").is_ok());
        assert!(check_import(&p, "/p/types/a.ms", "@std/fs.ms").is_ok());
        assert!(
            check_import(&p, "/p/tests/a.ms", "@std/fs.ms").is_ok(),
            "unmatched file"
        );
        let error = check_import(&p, "/p/src/a.ms", "@std/fs.ms").unwrap_err();
        assert_eq!(
            error,
            "src/a.ms may not import @std/fs.ms; ms.toml [imports] \"src/**\" allows only \"src/**\", \"@std/json.ms\", so import one of those or extend the list"
        );
        let error = check_import(&p, "/p/src/a.ms", "/p/types/a.ms").unwrap_err();
        assert!(
            error.starts_with("src/a.ms may not import types/a.ms;"),
            "{error}"
        );
    }

    #[test]
    fn importers_outside_the_root_fail_closed() {
        let p = project(&[("src/**", &["**"])]);
        let error = check_import(&p, "/elsewhere/x.ms", "@std/fs.ms").unwrap_err();
        assert!(
            error.starts_with("/elsewhere/x.ms is outside the project root"),
            "{error}"
        );
        assert!(check_import(&Project::default(), "/elsewhere/x.ms", "@std/fs.ms").is_ok());
    }

    #[test]
    fn extern_declarations_need_the_word_extern() {
        let p = project(&[("src/**", &["src/**"]), ("native/**", &["extern"])]);
        assert!(check_import(&p, "/p/native/libc.ms", "extern").is_ok());
        let error = check_import(&p, "/p/src/a.ms", "extern").unwrap_err();
        assert!(
            error.starts_with("src/a.ms may not import extern;"),
            "{error}"
        );
    }

    #[test]
    fn pattern_problems() {
        assert!(pattern_problem("src/**").is_none());
        assert!(pattern_problem("**/gen/*.ms").is_none());
        assert!(pattern_problem("extern").is_none());
        assert!(pattern_problem("a**b").is_some());
        assert!(pattern_problem("src/**.ms").is_some());
        assert!(pattern_problem("/src").is_some());
        assert!(pattern_problem("").is_some());
    }

    #[test]
    fn equal_prefixes_are_an_error() {
        let p = project(&[("src/**", &["**"]), ("src/*.ms", &["**"])]);
        let error = check_import(&p, "/p/src/a.ms", "@std/fs.ms").unwrap_err();
        assert!(error.contains("both match src/a.ms"), "{error}");
        assert!(check_import(&p, "/p/src/x/a.ms", "@std/fs.ms").is_ok());
    }
}
