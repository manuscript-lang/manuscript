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

/// Marks the generated module map in `references/standard-modules.md`.
pub const MODULES_START: &str = "<!-- modules:start -->";
pub const MODULES_END: &str = "<!-- modules:end -->";

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

/// `page` with the block between `start` and `end` replaced by `block`; none when a marker is missing.
pub fn splice_between(page: &str, start: &str, end: &str, block: &str) -> Option<String> {
    let from = page.find(start)?;
    let to = page.find(end)? + end.len();
    let rest = page[to..].strip_prefix('\n').unwrap_or(&page[to..]);
    Some(format!("{}{}{}", &page[..from], block, rest))
}

/// The block between `start` and `end` as it stands in `page`.
pub fn block_between(page: &str, start: &str, end: &str) -> Option<String> {
    let from = page.find(start)?;
    let to = page.find(end)? + end.len();
    Some(format!("{}\n", &page[from..to]))
}

/// `skill` with its generated block replaced by `block`; none when the markers are missing.
pub fn splice(skill: &str, block: &str) -> Option<String> {
    splice_between(skill, START, END, block)
}

/// The generated block as it stands in `skill`.
pub fn block_of(skill: &str) -> Option<String> {
    block_between(skill, START, END)
}

/// Every standard module with the names it exports, so an agent finds the import it needs.
pub fn render_modules() -> String {
    render_modules_with(standard_library(ms_syntax::Names::global()))
}

pub fn render_modules_with(modules: &[ApiModule]) -> String {
    let mut out = String::new();
    out.push_str(MODULES_START);
    out.push('\n');
    for module in modules {
        if !module.path.starts_with("@std/") || module.path.contains("/internal/") {
            continue;
        }
        let names: Vec<&str> = module
            .declarations
            .iter()
            .map(|d| d.name.as_str())
            .collect();
        if names.is_empty() {
            continue;
        }
        out.push_str(&format!("- `{}`: {}\n", module.path, names.join(", ")));
    }
    out.push_str(MODULES_END);
    out.push('\n');
    out
}
