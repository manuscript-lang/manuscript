//! Manuscript programs belong in `.ms` files, not Rust strings. A string literal that spells a
//! multi-line program (`export def`, `def main(`, or a `@std` import over several lines) is a
//! violation unless its file is in `BASELINE` with at least that many. The baseline only goes
//! down: move the program to a `.ms` file loaded with `include_str!` (or a conformance fixture),
//! then lower the count here. Product text that must contain ms (help, templates) is listed too.

/// Existing literals per file; a count here is a ceiling, not a target.
const BASELINE: &[(&str, usize)] = &[
    ("crates/ms-check/tests/list_methods.rs", 1),
    ("crates/ms-cli/src/init.rs", 1),
    ("crates/ms-cli/tests/check_fix.rs", 3),
    ("crates/ms-cli/tests/deep_input.rs", 3),
    ("crates/ms-cli/tests/engine.rs", 3),
    ("crates/ms-cli/tests/many_joins.rs", 1),
    ("crates/ms-cli/tests/min_size_rel.rs", 1),
    ("crates/ms-cli/tests/review_diagram.rs", 2),
    ("crates/ms-cli/tests/search_symbol.rs", 1),
    ("crates/ms-driver/tests/load.rs", 3),
    ("crates/ms-lsp/src/features.rs", 1),
    ("crates/ms-lsp/tests/search_symbol.rs", 4),
    ("crates/ms-lsp/tests/snapshots.rs", 1),
    ("crates/ms-repo-check/src/inline_source.rs", 1),
    ("crates/ms-tooling/tests/guide_pages.rs", 2),
    ("crates/ms-tooling/tests/lint_bindings.rs", 2),
    ("crates/ms-tooling/tests/lint_tasks.rs", 4),
];

pub fn check(files: &[String]) -> Vec<String> {
    let mut issues = Vec::new();
    for path in files
        .iter()
        .filter(|p| p.starts_with("crates/") && p.ends_with(".rs"))
    {
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let found = programs(&source);
        let allowed = BASELINE
            .iter()
            .find(|(f, _)| f == path)
            .map_or(0, |(_, n)| *n);
        if found > allowed {
            issues.push(format!(
                "{path}: {found} Rust string literal(s) hold Manuscript programs (allowed {allowed}); move them to .ms files loaded with include_str!, see crates/ms-repo-check/src/inline_source.rs"
            ));
        }
    }
    issues
}

/// Number of string literals in `source` that look like multi-line Manuscript programs.
pub(crate) fn programs(source: &str) -> usize {
    literals(source).iter().filter(|l| is_program(l)).count()
}

fn is_program(text: &str) -> bool {
    let lines = text.lines().count();
    lines >= 4
        && (text.contains("export def ")
            || text.contains("def main(")
            || (lines >= 6 && text.contains("from \"@std/")))
}

/// The unescaped contents of every string literal outside comments.
fn literals(source: &str) -> Vec<String> {
    let chars: Vec<char> = source.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '/' && chars.get(i + 1) == Some(&'/') {
            while i < chars.len() && chars[i] != '\n' {
                i += 1;
            }
        } else if c == '/' && chars.get(i + 1) == Some(&'*') {
            i += 2;
            while i + 1 < chars.len() && !(chars[i] == '*' && chars[i + 1] == '/') {
                i += 1;
            }
            i += 2;
        } else if c == '\'' {
            // A char literal ('"', '\''), or a lifetime; skip a quoted char only.
            let closes = if chars.get(i + 1) == Some(&'\\') {
                i + 3
            } else {
                i + 2
            };
            i = if chars.get(closes) == Some(&'\'') {
                closes + 1
            } else {
                i + 1
            };
        } else if c == 'r' && raw_open(&chars, i).is_some() && !word_before(&chars, i) {
            let (hashes, start) = raw_open(&chars, i).expect("raw");
            let close: Vec<char> = std::iter::once('"')
                .chain(std::iter::repeat_n('#', hashes))
                .collect();
            let mut j = start;
            while j < chars.len()
                && chars[j..].len() >= close.len()
                && chars[j..j + close.len()] != close[..]
            {
                j += 1;
            }
            out.push(chars[start..j.min(chars.len())].iter().collect());
            i = j + close.len();
        } else if c == '"' {
            let mut text = String::new();
            i += 1;
            while i < chars.len() && chars[i] != '"' {
                if chars[i] == '\\' {
                    i += 1;
                    match chars.get(i) {
                        Some('n') => text.push('\n'),
                        Some('\n') => {
                            while chars.get(i).is_some_and(|c| c.is_whitespace()) {
                                i += 1;
                            }
                            continue;
                        }
                        Some(&other) => text.push(other),
                        None => break,
                    }
                } else {
                    text.push(chars[i]);
                }
                i += 1;
            }
            out.push(text);
            i += 1;
        } else {
            i += 1;
        }
    }
    out
}

/// `r"`, `r#"`, ...: the number of `#` and the index after the opening quote.
fn raw_open(chars: &[char], at: usize) -> Option<(usize, usize)> {
    let mut j = at + 1;
    while chars.get(j) == Some(&'#') {
        j += 1;
    }
    (chars.get(j) == Some(&'"')).then_some((j - at - 1, j + 1))
}

fn word_before(chars: &[char], at: usize) -> bool {
    at > 0 && (chars[at - 1].is_alphanumeric() || chars[at - 1] == '_')
}

#[cfg(test)]
mod tests {
    use super::programs;

    #[test]
    fn counts_multi_line_programs_only() {
        let program = "let a = \"export def main() -> Int:\\n    let x = 1\\n    let y = 2\\n    return 0\\n\";";
        assert_eq!(programs(program), 1);
        let raw = "const P: &str = r#\"export def main() -> Int:\n    a\n    b\n    return 0\n\"#;";
        assert_eq!(programs(raw), 1);
        assert_eq!(programs("let s = \"export def main() -> Int: 0\";"), 0);
        assert_eq!(programs("// \"export def\\n\\n\\n\\n\"\nlet c = '\"';"), 0);
    }
}
