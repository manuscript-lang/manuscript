//! Skill files embedded in the compiler so installation needs no network or checkout.

pub const FILES: &[(&str, &str)] = &[
    ("SKILL.md", include_str!("../../data/agent-skill/SKILL.md")),
    (
        "references/program-structure.md",
        include_str!("../../data/agent-skill/references/program-structure.md"),
    ),
    (
        "references/values-and-control.md",
        include_str!("../../data/agent-skill/references/values-and-control.md"),
    ),
    (
        "references/types-and-functions.md",
        include_str!("../../data/agent-skill/references/types-and-functions.md"),
    ),
    (
        "references/errors-and-optionals.md",
        include_str!("../../data/agent-skill/references/errors-and-optionals.md"),
    ),
    (
        "references/ownership-and-cleanup.md",
        include_str!("../../data/agent-skill/references/ownership-and-cleanup.md"),
    ),
    (
        "references/collections-and-pipelines.md",
        include_str!("../../data/agent-skill/references/collections-and-pipelines.md"),
    ),
    (
        "references/effects-and-concurrency.md",
        include_str!("../../data/agent-skill/references/effects-and-concurrency.md"),
    ),
    (
        "references/validation.md",
        include_str!("../../data/agent-skill/references/validation.md"),
    ),
];

/// A single Markdown skill for piping or saving, with all references inlined.
pub fn document(version: &str) -> String {
    let mut result = FILES[0].1.replace("{{MS_VERSION}}", version);
    for (path, text) in &FILES[1..] {
        let slug = path
            .trim_start_matches("references/")
            .trim_end_matches(".md");
        result = result.replace(&format!("({path})"), &format!("(#{slug})"));
        let mut title = slug.replace('-', " ");
        title[..1].make_ascii_uppercase();
        result.push_str(&format!("\n## {title}\n"));
        // The entry point links by stable filenames, so give inlined references
        // matching anchors rather than their sometimes longer standalone titles.
        let mut in_fence = false;
        for line in text.lines().skip(1) {
            if line.starts_with("```") {
                in_fence = !in_fence;
            }
            if !in_fence && line.starts_with('#') {
                result.push('#');
            }
            result.push_str(line);
            result.push('\n');
        }
    }
    result.replace("{{MS_VERSION}}", version)
}
