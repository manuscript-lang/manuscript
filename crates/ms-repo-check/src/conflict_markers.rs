//! A merge conflict that was committed with its markers left in. `git merge` leaves `<<<<<<< ours` and
//! `>>>>>>> theirs` lines at the start of a line; no compiler reads Markdown, so only this check notices
//! them there. `=======` alone is not flagged: it underlines a Markdown heading.

use crate::skipped;

const OURS: &str = "<<<<<<< ";
const THEIRS: &str = ">>>>>>> ";

pub fn check(files: &[String]) -> Vec<String> {
    files
        .iter()
        .filter(|p| !skipped(p))
        .filter_map(|p| Some((p, std::fs::read_to_string(p).ok()?)))
        .flat_map(|(path, text)| markers(path, &text))
        .collect()
}

fn markers(path: &str, text: &str) -> Vec<String> {
    text.lines()
        .enumerate()
        .filter(|(_, line)| line.starts_with(OURS) || line.starts_with(THEIRS))
        .map(|(i, line)| {
            let line = line.trim_end();
            format!("{path}:{}: merge conflict marker `{line}`; resolve the conflict and delete the marker lines", i + 1)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_both_sides_of_a_conflict_but_not_a_heading_underline() {
        let text = format!("Title\n=======\n{OURS}HEAD\nkept\n=======\ntaken\n{THEIRS}main\n");
        let found = markers("a.md", &text);
        assert_eq!(found.len(), 2);
        assert!(found[0].starts_with("a.md:3:"));
        assert!(found[1].starts_with("a.md:7:"));
        assert!(markers("b.md", "a << b\n>>> c\n").is_empty());
    }
}
