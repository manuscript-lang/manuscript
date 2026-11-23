//! Release pins: the extension version and the required workflow's triggers.

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

/// `.msversion` is a calendar version, `YYYY.M.PATCH`: a year, a month 1 to 12 and a patch, with no leading
/// zeros, so it is also valid semver (the VS Code extension, tags and installers rely on that).
pub fn calendar_version() -> Vec<String> {
    let Ok(text) = std::fs::read_to_string(".msversion") else {
        return vec!["cannot read .msversion".into()];
    };
    match calendar_error(text.trim()) {
        Some(why) => vec![format!(".msversion {:?}: {why}", text.trim())],
        None => Vec::new(),
    }
}

fn calendar_error(version: &str) -> Option<&'static str> {
    let parts: Vec<&str> = version.split('.').collect();
    let [year, month, patch] = parts.as_slice() else {
        return Some("write YYYY.M.PATCH, for example 2026.11.0");
    };
    let plain = |part: &str| {
        !part.is_empty()
            && part.bytes().all(|b| b.is_ascii_digit())
            && (part == "0" || !part.starts_with('0'))
    };
    if !(plain(year) && plain(month) && plain(patch)) {
        return Some("each part is digits with no leading zero, so the version is valid semver");
    }
    match (year.parse::<u32>(), month.parse::<u32>()) {
        (Ok(2000..=9999), Ok(1..=12)) => None,
        _ => Some("the year has four digits and the month is 1 to 12"),
    }
}

/// The CI workflow must run on every PR, whatever files it changes, and on the merge queue's combined
/// commit: the ruleset on `main` requires its `Platform checks` job.
pub fn workflow_triggers() -> Vec<String> {
    let path = ".github/workflows/ci.yml";
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
    use super::{calendar_error, triggers};

    const GOOD: &str = "name: x\n\non:\n  push:\n    branches: [main]\n  pull_request:\n  merge_group:\n    types: [checks_requested]\n\njobs:\n  a:\n    paths: x\n";

    #[test]
    fn calendar_versions_are_year_month_patch_without_leading_zeros() {
        for good in ["2026.11.0", "2027.1.3", "2026.12.10"] {
            assert_eq!(calendar_error(good), None, "{good}");
        }
        for bad in [
            "0.1.0",
            "2026.01.0",
            "2026.13.0",
            "2026.11",
            "2026.11.0.1",
            "v2026.11.0",
            "2026.11.01",
            "26.11.0",
        ] {
            assert!(calendar_error(bad).is_some(), "{bad}");
        }
    }

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
