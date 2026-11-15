//! The standard-call tables of the agent skill, rendered from the standard library's own
//! declarations and the use counts of the programs agents wrote.
//!
//! The skill lists exact names so an agent does not guess `contains_key` for `contains`. Which
//! calls appear comes from counts, not taste: `count` reads a corpus of agent programs and
//! `render` keeps the most used calls that the declarations still have. The committed counts
//! are `data/agent-skill/call-counts.tsv`; a test renders them again and compares the result
//! with the block in `SKILL.md`, so a renamed or removed call fails the build instead of
//! going stale.

use crate::guide::api::{ApiModule, standard_library};
use std::collections::{BTreeMap, BTreeSet};

/// Marks the generated block in `SKILL.md`.
pub const START: &str = "<!-- calls:start -->";
pub const END: &str = "<!-- calls:end -->";

/// Prelude types in table order, with how many calls each row shows.
const TYPES: &[(&str, usize)] = &[
    ("String", 14),
    ("List", 14),
    ("Map", 9),
    ("Set", 5),
    ("Optional", 5),
    ("Result", 5),
    ("Int", 4),
    ("Float", 3),
];

/// How many imported names the import table shows.
const IMPORTS: usize = 16;

/// A call or import must appear in this many programs to be listed.
const MIN_PROGRAMS: usize = 2;

/// Use counts: for each method name and each imported name with its module, the number of
/// programs that use it.
#[derive(Default, Debug, PartialEq, Eq)]
pub struct Counts {
    pub calls: BTreeMap<String, usize>,
    pub imports: BTreeMap<(String, String), usize>,
}

impl Counts {
    /// Parses the committed counts file.
    pub fn parse(text: &str) -> Counts {
        let mut counts = Counts::default();
        for line in text.lines().filter(|l| !l.is_empty()) {
            let fields: Vec<&str> = line.split('\t').collect();
            match fields[..] {
                ["call", name, n] => {
                    counts
                        .calls
                        .insert(name.to_string(), n.parse().unwrap_or(0));
                }
                ["import", name, path, n] => {
                    counts
                        .imports
                        .insert((name.to_string(), path.to_string()), n.parse().unwrap_or(0));
                }
                _ => {}
            }
        }
        counts
    }

    /// The counts file: one line per call or import, in name order.
    pub fn to_text(&self) -> String {
        let mut out = String::new();
        for (name, n) in &self.calls {
            out.push_str(&format!("call\t{name}\t{n}\n"));
        }
        for ((name, path), n) in &self.imports {
            out.push_str(&format!("import\t{name}\t{path}\t{n}\n"));
        }
        out
    }
}

/// Counts, over `programs`, the programs that call each `.name(` and import each name.
pub fn count<'a>(programs: impl IntoIterator<Item = &'a str>) -> Counts {
    let mut counts = Counts::default();
    for source in programs {
        let mut calls = BTreeSet::new();
        let mut imports = BTreeSet::new();
        for line in source.lines() {
            let code = line.split("//").next().unwrap_or("");
            let mut rest = code;
            while let Some(at) = rest.find('.') {
                rest = &rest[at + 1..];
                let name: String = rest
                    .chars()
                    .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                    .collect();
                let after = rest[name.len()..].trim_start();
                if !name.is_empty()
                    && !name.starts_with(|c: char| c.is_ascii_digit())
                    && (after.starts_with('(') || after.starts_with('['))
                {
                    calls.insert(name);
                }
            }
        }
        let flat = source.replace('\n', " ");
        for statement in flat.split("import ").skip(1) {
            let Some((names, rest)) = statement.split_once(" from \"") else {
                continue;
            };
            let Some((path, _)) = rest.split_once('"') else {
                continue;
            };
            for name in names.split(',') {
                let name = name
                    .trim()
                    .trim_start_matches('(')
                    .trim_end_matches(')')
                    .trim();
                if !name.is_empty() && !name.contains(' ') {
                    imports.insert((name.to_string(), path.to_string()));
                }
            }
        }
        for name in calls {
            *counts.calls.entry(name).or_default() += 1;
        }
        for key in imports {
            *counts.imports.entry(key).or_default() += 1;
        }
    }
    counts
}

/// `fn(A, B) R` as `(A, B) R`: the call shape without the keyword.
fn shape(signature: &str) -> String {
    signature
        .strip_prefix("fn")
        .unwrap_or(signature)
        .to_string()
}

/// The generated block: calls per prelude type, then imports, both from the declarations.
pub fn render(counts: &Counts) -> String {
    render_with(counts, standard_library(ms_syntax::Names::global()))
}

pub fn render_with(counts: &Counts, modules: &[ApiModule]) -> String {
    let mut out = String::new();
    out.push_str(START);
    out.push('\n');
    out.push_str("Exact calls, most used first (from the declarations; `ms search_symbol <name>` shows the rest):\n\n");
    let prelude = modules.iter().find(|m| m.path == "prelude");
    for (type_name, limit) in TYPES {
        let Some(declaration) =
            prelude.and_then(|m| m.declarations.iter().find(|d| d.name == *type_name))
        else {
            continue;
        };
        // One entry per name: the shortest signature, so a name with overloads shows its plain form.
        let mut by_name: BTreeMap<&str, &str> = BTreeMap::new();
        for operation in &declaration.operations {
            let Some((name, signature)) = operation.split_once(": ") else {
                continue;
            };
            let name = name.split('[').next().unwrap_or(name);
            let entry = by_name.entry(name).or_insert(signature);
            if signature.len() < entry.len() {
                *entry = signature;
            }
        }
        let mut ranked: Vec<(&str, usize)> = by_name
            .keys()
            .filter_map(|name| {
                let n = counts.calls.get(*name).copied().unwrap_or(0);
                (n >= MIN_PROGRAMS).then_some((*name, n))
            })
            .collect();
        ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
        let calls: Vec<String> = ranked
            .into_iter()
            .take(*limit)
            .map(|(name, _)| format!("{name}{}", shape(by_name[name])))
            .collect();
        if !calls.is_empty() {
            out.push_str(&format!("- {type_name}: {}\n", calls.join("; ")));
        }
    }
    out.push('\n');
    out.push_str("Imports (a name must be imported unless it is in the prelude):\n\n");
    let mut ranked: Vec<(&(String, String), usize)> = counts
        .imports
        .iter()
        .filter(|((name, path), n)| {
            **n >= MIN_PROGRAMS
                && modules
                    .iter()
                    .any(|m| m.path == *path && m.declarations.iter().any(|d| d.name == *name))
        })
        .map(|(key, n)| (key, *n))
        .collect();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    let mut by_path: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    let mut order: Vec<&str> = Vec::new();
    for ((name, path), _) in ranked.into_iter().take(IMPORTS) {
        if !by_path.contains_key(path.as_str()) {
            order.push(path);
        }
        by_path.entry(path).or_default().push(name);
    }
    for path in order {
        let mut names = by_path[path].clone();
        names.sort_unstable();
        out.push_str(&format!(
            "- `import {} from \"{path}\"`\n",
            names.join(", ")
        ));
    }
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
