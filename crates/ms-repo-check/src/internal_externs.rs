//! The internal-surface rule: every `extern fn` declared under `stdlib/internal/` is named by at least one
//! other standard-library source file. A native nobody imports costs a symbol, an ABI entry and tests for
//! nothing, so the change that removes its last use removes the declaration and the Rust side too.

use std::collections::BTreeMap;

pub fn check(files: &[String]) -> Vec<String> {
    let sources: BTreeMap<&str, String> = files
        .iter()
        .filter(|p| p.starts_with("stdlib/") && p.ends_with(".ms"))
        .filter_map(|p| Some((p.as_str(), std::fs::read_to_string(p).ok()?)))
        .collect();
    let mut issues = Vec::new();
    for (path, text) in &sources {
        if !path.starts_with("stdlib/internal/") {
            continue;
        }
        for name in extern_names(text) {
            let used = sources
                .iter()
                .any(|(other, source)| other != path && contains_word(source, name));
            if !used {
                issues.push(format!(
                    "{path}: `extern fn {name}` is not used by any other standard-library file; delete it and its Rust side"
                ));
            }
        }
    }
    issues
}

/// Names declared by `extern fn name` (optionally `export extern fn`), generic or not.
fn extern_names(text: &str) -> Vec<&str> {
    text.lines()
        .filter_map(|line| {
            let rest = line
                .trim_start()
                .strip_prefix("export ")
                .unwrap_or(line.trim_start());
            let rest = rest.strip_prefix("extern fn ")?;
            let end = rest.find(|c: char| !(c.is_alphanumeric() || c == '_'))?;
            Some(&rest[..end])
        })
        .collect()
}

/// Whether `word` occurs in `text` bounded by non-identifier characters.
fn contains_word(text: &str, word: &str) -> bool {
    let is_identifier = |c: char| c.is_alphanumeric() || c == '_';
    text.match_indices(word).any(|(at, _)| {
        let before = text[..at].chars().next_back();
        let after = text[at + word.len()..].chars().next();
        !before.is_some_and(is_identifier) && !after.is_some_and(is_identifier)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_declared_names() {
        let text =
            "export extern fn a_b(x: Int) Int\nextern fn c[T](y: T) T\n// extern fn skipped\n";
        assert_eq!(extern_names(text), vec!["a_b", "c"]);
    }

    #[test]
    fn matches_whole_words_only() {
        assert!(contains_word("import a, b_c from x", "b_c"));
        assert!(!contains_word("import ab_c from x", "b_c"));
    }
}
