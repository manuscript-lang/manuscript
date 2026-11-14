//! Language-stage layering inside `ms-check`: which module may name which.
//!
//! Crates are layered by `layering.rs`; this is the same rule for the stages the checker holds.
//! Every top-level module has a stage, and a module may name only its own stage or a lower one
//! (`proposals/compiler-stage-layering.md`). A reference to a higher stage is a back-edge: a later
//! stage reached into by an earlier one. Today's back-edges are listed in `BACK_EDGES`; the list
//! may only shrink, and an entry names the change that removes it.

use std::fs;

/// Stages, lowest first. A new module needs a row here, in the same change.
const STAGES: &[(&str, &[&str])] = &[
    (
        "syntax: tree facts, types, desugaring",
        &["syntax", "passes", "types", "tytable", "std_ops", "fxmap"],
    ),
    (
        "load: bundled sources and the session",
        &["bundled", "stdlib"],
    ),
    (
        "resolve: declarations, imports, signatures",
        &["checker", "constants", "prelude_imports"],
    ),
    (
        "typecheck: bodies, calls, contracts, diagnostics text",
        &[
            "hints",
            "suggestions",
            "contracts",
            "exprs",
            "stmts",
            "calls",
            "inference",
            "callbacks",
            "native",
            "native_defaults",
        ],
    ),
    (
        "analysis: effects, recursion, constant faults, typed HIR",
        &[
            "effect_directives",
            "effect_reach",
            "effects",
            "recursion",
            "constfaults",
            "hir",
        ],
    ),
    ("ownership: moves, borrows, exclusivity", &["ownership"]),
    ("lints and editor queries (leaves)", &["unused", "editor"]),
    ("api: the public surface", &["api"]),
];

/// Known back-edges `(from, to, what removes it)`. Remove a row when its change lands.
const BACK_EDGES: &[(&str, &str, &str)] = &[
    (
        "stdlib",
        "checker",
        "the session checks bundled sources with Checker; revisit after stage 2",
    ),
    (
        "checker",
        "ownership",
        "Program holds the one OwnershipFacts value; ends when Program is split from Checker",
    ),
    (
        "checker",
        "effect_reach",
        "Program holds the effect diagnostics; ends when Program is split from Checker",
    ),
    (
        "checker",
        "constfaults",
        "Program names the constant-fault literal facts; ends when Program is split from Checker",
    ),
    (
        "checker",
        "hints",
        "the checker emits hint text; moves with the typecheck diagnostics",
    ),
];

/// Lowering's own path-sensitive drop bookkeeping, which the proposal's step 4b would replace
/// with a checker-computed plan. `(identifier, uses in crates/ms-lower/src)`: the count may only
/// shrink, so the mechanism cannot grow while the plan is undecided.
const LOWERING_LEDGER: &[(&str, usize)] = &[
    ("closed_on_path", 18),
    ("scope_done", 0),
    ("rest_closers", 0),
    ("hidden_closers", 0),
    ("copy_gaps", 5),
];

/// Fails when a ledger identifier appears more often than recorded, or less often (the cap
/// must then be lowered, so progress is kept).
fn ledger(files: &[String]) -> Vec<String> {
    let mut counts = vec![0usize; LOWERING_LEDGER.len()];
    for path in files {
        if !path.starts_with("crates/ms-lower/src/") || !path.ends_with(".rs") {
            continue;
        }
        let Ok(text) = fs::read_to_string(path) else {
            continue;
        };
        for (i, (name, _)) in LOWERING_LEDGER.iter().enumerate() {
            counts[i] += text.matches(name).count();
        }
    }
    LOWERING_LEDGER
        .iter()
        .zip(counts)
        .filter(|((_, cap), n)| n != cap)
        .map(|((name, cap), n)| {
            let verb = if n > *cap { "grew" } else { "shrank" };
            format!(
                "stages.rs: `{name}` {verb} in crates/ms-lower/src ({n}, recorded {cap}); set its LOWERING_LEDGER cap in crates/ms-repo-check/src/stages.rs to {n} (it may only go down; proposals/compiler-stage-layering.md step 4b)"
            )
        })
        .collect()
}

fn stage(module: &str) -> Option<usize> {
    STAGES.iter().position(|(_, mods)| mods.contains(&module))
}

pub fn check(files: &[String]) -> Vec<String> {
    let mut issues = Vec::new();
    let mut seen_edges: Vec<(&str, &str)> = Vec::new();
    for path in files {
        let Some(rest) = path.strip_prefix("crates/ms-check/src/") else {
            continue;
        };
        if !path.ends_with(".rs") || rest.starts_with("bin/") || is_test_file(rest) {
            continue;
        }
        let module = rest
            .split('/')
            .next()
            .unwrap_or(rest)
            .trim_end_matches(".rs");
        if module == "lib" {
            continue;
        }
        let Some(from) = stage(module) else {
            issues.push(format!(
                "{path}: module `{module}` has no stage; add it to STAGES in crates/ms-repo-check/src/stages.rs"
            ));
            continue;
        };
        let Ok(text) = fs::read_to_string(path) else {
            continue;
        };
        for target in crate_modules(production(&text)) {
            let Some(to) = stage(&target) else { continue };
            if target == module || to <= from {
                continue;
            }
            match BACK_EDGES.iter().find(|(f, t, _)| *f == module && *t == target) {
                Some((f, t, _)) => seen_edges.push((f, t)),
                None => issues.push(format!(
                    "{path}: `{module}` ({}) names `{target}` ({}), a later stage; see proposals/compiler-stage-layering.md",
                    STAGES[from].0.split(':').next().unwrap_or(""),
                    STAGES[to].0.split(':').next().unwrap_or("")
                )),
            }
        }
    }
    issues.extend(ledger(files));
    for (from, to, why) in BACK_EDGES {
        if !seen_edges.contains(&(from, to)) {
            issues.push(format!(
                "stages.rs: back-edge `{from}` -> `{to}` no longer exists; delete its BACK_EDGES row ({why})"
            ));
        }
    }
    issues
}

fn is_test_file(rest: &str) -> bool {
    let file = rest.rsplit('/').next().unwrap_or(rest);
    file.ends_with("_tests.rs") || file == "type_keys.rs" || file == "tests.rs"
}

/// The text before a trailing `#[cfg(test)]` module.
fn production(text: &str) -> &str {
    text.find("#[cfg(test)]\nmod ")
        .map_or(text, |at| &text[..at])
}

/// Top-level modules named as `crate::name` or inside `crate::{a, b::c}`.
fn crate_modules(text: &str) -> Vec<String> {
    let mut found = Vec::new();
    let mut rest = text;
    while let Some(at) = rest.find("crate::") {
        rest = &rest[at + "crate::".len()..];
        if let Some(group) = rest.strip_prefix('{') {
            let mut open = 1usize;
            let end = group
                .char_indices()
                .find(|&(_, c)| {
                    open = match c {
                        '{' => open + 1,
                        '}' => open - 1,
                        _ => open,
                    };
                    open == 0
                })
                .map_or(group.len(), |(i, _)| i);
            let mut depth = 0usize;
            let mut word = String::new();
            let mut at_start = true;
            for c in group[..end].chars() {
                match c {
                    '{' => depth += 1,
                    '}' => depth = depth.saturating_sub(1),
                    ',' => {
                        if depth == 0 {
                            at_start = true;
                        }
                        push_word(&mut found, &mut word);
                    }
                    c if c.is_alphanumeric() || c == '_' => {
                        if at_start && depth == 0 {
                            word.push(c);
                        }
                    }
                    _ => {
                        if !word.is_empty() {
                            push_word(&mut found, &mut word);
                        }
                        if depth == 0 && !c.is_whitespace() {
                            at_start = false;
                        }
                    }
                }
            }
            push_word(&mut found, &mut word);
        } else {
            let name: String = rest
                .chars()
                .take_while(|c| c.is_alphanumeric() || *c == '_')
                .collect();
            found.push(name);
        }
    }
    found.sort();
    found.dedup();
    found
}

fn push_word(found: &mut Vec<String>, word: &mut String) {
    if !word.is_empty() {
        found.push(std::mem::take(word));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_plain_and_grouped_paths() {
        let text = "use crate::types::Ty;\nuse crate::{hints, stdlib::Session};\nlet x = crate::checker::Program::new();";
        assert_eq!(crate_modules(text), ["checker", "hints", "stdlib", "types"]);
    }

    #[test]
    fn grouped_nested_paths_name_only_the_first_segment() {
        assert_eq!(crate_modules("use crate::{a::{b, c}, d};"), ["a", "d"]);
    }

    #[test]
    fn production_drops_the_test_module() {
        assert_eq!(
            production("fn a() {}\n#[cfg(test)]\nmod tests { crate::x::y }"),
            "fn a() {}\n"
        );
    }

    #[test]
    fn every_module_has_one_stage() {
        let mut all: Vec<&str> = STAGES.iter().flat_map(|(_, m)| m.iter().copied()).collect();
        all.sort_unstable();
        let total = all.len();
        all.dedup();
        assert_eq!(all.len(), total);
    }
}
