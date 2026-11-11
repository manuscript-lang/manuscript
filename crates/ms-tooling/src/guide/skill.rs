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
