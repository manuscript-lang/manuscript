//! Release pins: the extension version and the required workflows' triggers.

pub fn extension_version() -> Vec<String> {
    let (Ok(release), Ok(manifest)) = (
        std::fs::read_to_string(".msversion"),
        std::fs::read_to_string("extensions/vscode/package.json"),
    ) else {
        return vec!["cannot read .msversion or extensions/vscode/package.json".into()];
    };
    let parsed = ms_json::parse(&manifest);
    let version = parsed
        .as_ref()
        .ok()
        .and_then(|json| json.get("version"))
        .and_then(ms_json::Json::as_str)
        .unwrap_or("");
    if version == release.trim() {
        return Vec::new();
    }
    vec![format!(
        "extensions/vscode/package.json version {version} disagrees with .msversion"
    )]
}

/// Required workflows must report on every PR and on the queue's combined commit. The ruleset on
/// `main` requires checks from cicd.yml only; release.yml runs on tags and merge groups.
pub fn workflow_triggers() -> Vec<String> {
    let path = ".github/workflows/cicd.yml";
    match std::fs::read_to_string(path) {
        Ok(text) => triggers(&text)
            .map(|e| format!("{path}: {e}"))
            .into_iter()
            .collect(),
        Err(e) => vec![format!("{path}: {e}")],
    }
}

/// Lines of the child block of `key:` at `indent`, stopping at the next sibling.
fn block<'a>(lines: &[&'a str], key: &str, indent: usize) -> Option<Vec<&'a str>> {
    let head = format!("{}{key}:", " ".repeat(indent));
    let start = lines
        .iter()
        .position(|l| l.trim_end() == head || l.starts_with(&format!("{head} ")))?;
    Some(
        lines[start + 1..]
            .iter()
            .copied()
            .take_while(|l| l.trim().is_empty() || l.len() - l.trim_start().len() > indent)
            .collect(),
    )
}

fn triggers(text: &str) -> Option<String> {
    let lines: Vec<&str> = text.lines().collect();
    let on = block(&lines, "on", 0).unwrap_or_default();
    // `pull_request:` may carry an inline value; any child key is a filter.
    let filtered = block(&on, "pull_request", 2)
        .is_none_or(|b| b.iter().any(|l| l.trim_start().starts_with("paths")));
    if filtered {
        return Some("required checks must run on every pull request without path filters".into());
    }
    let queue = block(&on, "merge_group", 2).unwrap_or_default();
    let types: Vec<String> = queue
        .iter()
        .map(|l| l.trim())
        .filter(|l| l.starts_with("types:") || l.starts_with("- "))
        .map(|l| l.trim_start_matches("types:").trim().to_string())
        .collect();
    if types != ["[checks_requested]"] && types != ["- checks_requested"] {
        return Some("required checks must run on merge_group checks_requested".into());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::triggers;

    const GOOD: &str = "name: x\n\non:\n  push:\n    branches: [main]\n  pull_request:\n  merge_group:\n    types: [checks_requested]\n\njobs:\n  a:\n    paths: x\n";

    #[test]
    fn accepts_required_triggers() {
        assert_eq!(triggers(GOOD), None);
    }

    #[test]
    fn rejects_path_filters_and_missing_queue() {
        let filtered = GOOD.replace("  pull_request:\n", "  pull_request:\n    paths: [a]\n");
        assert!(triggers(&filtered).unwrap().contains("path filters"));
        let no_queue = GOOD.replace("  merge_group:\n    types: [checks_requested]\n", "");
        assert!(triggers(&no_queue).unwrap().contains("merge_group"));
    }
}
