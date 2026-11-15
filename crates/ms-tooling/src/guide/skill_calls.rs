//! The standard-call table of the agent skill, rendered from the standard library's own
//! declarations.
//!
//! The skill lists exact names so an agent does not guess `contains_key` for `contains`. The
//! table holds every call of the core prelude types, so it needs no corpus and no taste: a
//! test renders it again and compares the result with the block in
//! `references/standard-calls.md`, so a renamed or removed call fails the build instead of
//! going stale.

use crate::guide::api::{ApiModule, standard_library};
use std::collections::BTreeMap;

/// Marks the generated block in `references/standard-calls.md`.
pub const START: &str = "<!-- calls:start -->";
pub const END: &str = "<!-- calls:end -->";

/// Prelude types in table order.
const TYPES: &[&str] = &[
    "String", "List", "Map", "Set", "Optional", "Result", "Int", "Float",
];

/// `fn(A, B) R` as `(A, B) R`: the call shape without the keyword.
fn shape(signature: &str) -> String {
    signature
        .strip_prefix("fn")
        .unwrap_or(signature)
        .to_string()
}

/// The generated block: every call of each prelude type, then the reserved words.
pub fn render() -> String {
    render_with(standard_library(ms_syntax::Names::global()))
}

pub fn render_with(modules: &[ApiModule]) -> String {
    let mut out = String::new();
    out.push_str(START);
    out.push('\n');
    let prelude = modules.iter().find(|m| m.path == "prelude");
    for type_name in TYPES {
        let Some(declaration) =
            prelude.and_then(|m| m.declarations.iter().find(|d| d.name == *type_name))
        else {
            continue;
        };
        // Every signature of a name, so an overload such as `sort(fn(T, T) Int)` is shown too.
        let mut by_name: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
        for operation in &declaration.operations {
            let Some((name, signature)) = operation.split_once(": ") else {
                continue;
            };
            let name = name.split('[').next().unwrap_or(name);
            let signatures = by_name.entry(name).or_default();
            if !signatures.contains(&signature) {
                signatures.push(signature);
            }
        }
        let calls: Vec<String> = by_name
            .iter()
            .map(|(name, signatures)| {
                let shapes: Vec<String> = signatures
                    .iter()
                    .map(|s| format!("{name}{}", shape(s)))
                    .collect();
                shapes.join(" | ")
            })
            .collect();
        if !calls.is_empty() {
            out.push_str(&format!("- {type_name}: {}\n", calls.join("; ")));
        }
    }
    out.push('\n');
    out.push_str(&format!(
        "Reserved words are never names (a variable called `type` or `test` fails): {}.\n",
        ms_syntax::token::KEYWORDS.join(" ")
    ));
    out.push_str(END);
    out.push('\n');
    out
}

/// `skill` with its generated block replaced by `block`; none when the markers are missing.
pub fn splice(skill: &str, block: &str) -> Option<String> {
    let start = skill.find(START)?;
    let end = skill.find(END)? + END.len();
    let tail = skill[end..].strip_prefix('\n').unwrap_or(&skill[end..]);
    Some(format!("{}{}{}", &skill[..start], block, tail))
}

/// The generated block as it stands in `skill`.
pub fn block_of(skill: &str) -> Option<String> {
    let start = skill.find(START)?;
    let end = skill.find(END)? + END.len();
    Some(format!("{}\n", &skill[start..end]))
}
