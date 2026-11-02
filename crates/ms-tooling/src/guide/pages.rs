//! The language cheat sheet and bounded standard-library pages
//!
//! Every page is bounded so an agent can read it without flooding its context:
//! the index and module pages list one line per item, a declaration page lists
//! its members as signatures, and only a single member shows its full doc.

use crate::guide::api::{ApiDeclaration, ApiModule, standard_library};
use std::sync::OnceLock;

const PAGE_BUDGET: usize = 3500;
const LINE_WIDTH: usize = 150;
const MODULE_LINES: usize = 45;

/// The one-page language guide for agents.
pub fn cheatsheet() -> &'static str {
    include_str!("../../data/cheatsheet.md")
}

/// One checked agent mistake: `wrong` and `right` replace `{}` in `body`.
pub struct Mistake {
    pub wrong: String,
    pub right: String,
    pub setup: String,
    pub body: String,
    /// A fragment of the diagnostic `wrong` produces, or `None` when it checks clean.
    pub diagnostic: Option<String>,
}

/// The common-mistakes entries from `data/mistakes.txt`.
pub fn mistake_entries() -> Vec<Mistake> {
    let field = |block: &str, key: &str| {
        let prefix = format!("{key}: ");
        let line = block.lines().find_map(|line| line.strip_prefix(&prefix));
        line.map(str::to_string)
    };
    let mut entries = Vec::new();
    let text = include_str!("../../data/mistakes.txt");
    for block in text.split("\n\n") {
        let block: String = block
            .lines()
            .filter(|l| !l.starts_with('#'))
            .collect::<Vec<_>>()
            .join("\n");
        let Some(wrong) = field(&block, "wrong") else {
            continue;
        };
        let diagnostic = field(&block, "diag").filter(|d| d != "-");
        entries.push(Mistake {
            wrong,
            right: field(&block, "right").expect("mistake without right"),
            setup: field(&block, "setup").unwrap_or_default(),
            body: field(&block, "body").unwrap_or_else(|| "{}".to_string()),
            diagnostic,
        });
    }
    entries
}

/// The mistakes section of `ms guide`: each wrong form beside its fix.
pub fn mistakes() -> String {
    let show = |text: &str| text.replace(";;", "; ");
    let mut out = String::from("\n## Common mistakes\n\n");
    for m in mistake_entries() {
        out.push_str(&format!("- `{}` -> `{}`\n", show(&m.wrong), show(&m.right)));
    }
    out
}

/// The name `ms search_symbol` shows for a module: `json` for `@std/data/json.ms`.
pub(crate) fn short_name(path: &str) -> &str {
    let path = path.strip_prefix("@std/").unwrap_or(path);
    let path = path.strip_suffix(".ms").unwrap_or(path);
    path.rsplit('/').next().unwrap_or(path)
}

/// The module path without `@std/` and `.ms`: `data/json`.
fn package_name(path: &str) -> &str {
    let path = path.strip_prefix("@std/").unwrap_or(path);
    path.strip_suffix(".ms").unwrap_or(path)
}

/// Drops a generic parameter list: `group_by[K: Hashable]` becomes `group_by`.
pub(crate) fn bare(name: &str) -> &str {
    name.split('[').next().unwrap_or(name)
}

/// The path that `ms search_symbol` accepts for a declaration or member.
pub(crate) fn std_path(module_path: &str, name: &str) -> String {
    format!("{}.{}", short_name(module_path), bare(name))
}

/// Collapses a signature to a single line of at most `limit` runes.
fn one_line(text: &str, limit: usize) -> String {
    let joined = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let text = joined.strip_suffix(':').unwrap_or(&joined).trim();
    let chars: Vec<char> = text.chars().collect();
    if chars.len() > limit {
        let mut out: String = chars[..limit - 1].iter().collect();
        out.push('…');
        return out;
    }
    text.to_string()
}

/// The first non-empty line of a doc, cut at a word boundary.
pub(crate) fn first_line(doc: &str, limit: usize) -> String {
    for line in doc.split('\n') {
        let line = line.split_whitespace().collect::<Vec<_>>().join(" ");
        if line.is_empty() {
            continue;
        }
        let chars: Vec<char> = line.chars().collect();
        if chars.len() > limit {
            let head: String = chars[..limit - 1].iter().collect();
            // The cut is a byte offset into the rune slice; kept for stable output.
            let mut cut = head.rfind(' ').map_or(-1, |i| i as isize);
            if cut < (limit / 2) as isize {
                cut = limit as isize - 1;
            }
            let cut = (cut as usize).min(chars.len());
            let mut out: String = chars[..cut].iter().collect();
            out.push('…');
            return out;
        }
        return line;
    }
    String::new()
}

/// Limits a full doc to `limit` bytes without cutting a rune.
fn cap_doc(doc: &str, limit: usize) -> String {
    let doc = doc.trim();
    if doc.len() <= limit {
        return doc.to_string();
    }
    let mut chars: Vec<char> = doc.chars().collect();
    while chars.iter().map(|c| c.len_utf8()).sum::<usize>() > limit {
        let keep = chars.len().saturating_sub(20);
        chars.truncate(keep);
    }
    let mut out: String = chars.into_iter().collect();
    out.push('…');
    out
}

/// The standard modules, `prelude` first and the rest by path.
pub(crate) fn modules() -> &'static [ApiModule] {
    static SORTED: OnceLock<Vec<ApiModule>> = OnceLock::new();
    SORTED.get_or_init(|| {
        let mut all = standard_library().to_vec();
        all.sort_by(|a, b| {
            (a.path != "prelude")
                .cmp(&(b.path != "prelude"))
                .then_with(|| a.path.cmp(&b.path))
        });
        all
    })
}

/// The short names of every standard module, prelude first.
pub fn module_names() -> Vec<String> {
    modules()
        .iter()
        .map(|m| short_name(&m.path).to_string())
        .collect()
}

/// The index stays under this many bytes (the guide-pages test budget is 3500): agents read it
/// whole, so it narrows its lines as modules are added instead of growing past the budget.
const INDEX_BUDGET: usize = 3400;

/// Lists each module with a few of its names.
pub fn index() -> String {
    let header = "Standard modules (prelude needs no import).\n`ms search_symbol <module>` lists one, `ms search_symbol <module>.<Name>` shows a declaration, `ms search_symbol <words>` searches.\n\n";
    let mut width = 84;
    loop {
        let body = index_lines(width);
        if header.len() + body.len() <= INDEX_BUDGET || width <= 24 {
            return format!("{header}{body}");
        }
        width -= 4;
    }
}

/// One line per module: the name, then declarations while the line stays within `width`.
fn index_lines(width: usize) -> String {
    let mut b = String::new();
    for m in modules() {
        let mut line = format!("{:<12}", short_name(&m.path));
        let mut shown = 0;
        for d in &m.declarations {
            let next = format!("{line} {},", d.name);
            if next.len() > width && shown > 0 {
                break;
            }
            line = next;
            shown += 1;
        }
        if line.ends_with(',') {
            line.pop();
        }
        let rest = m.declarations.len() - shown;
        if rest > 0 {
            line += &format!(" +{rest}");
        }
        b += &line;
        b.push('\n');
    }
    b
}

/// Renders `ms search_symbol <path>`: a module (`json`), a declaration
/// (`json.parse`), or one member (`prelude.List.sorted`). A leading `@std/`
/// and `.ms` are accepted.
pub fn page(path: &str) -> Result<String, String> {
    let parts = split_path(path);
    let Some(module) = find_module(&parts[0]) else {
        return Err(format!(
            "no standard module {:?}; modules: {}",
            parts[0],
            module_names().join(", ")
        ));
    };
    if parts.len() == 1 {
        return Ok(module_page(module));
    }
    let Some(found) = module
        .declarations
        .iter()
        .find(|d| bare(&d.name) == parts[1])
    else {
        return Err(format!(
            "{} has no declaration {:?}; see `ms search_symbol {}` (or `ms search_symbol {}`)",
            short_name(&module.path),
            parts[1],
            short_name(&module.path),
            parts[1]
        ));
    };
    if parts.len() == 2 {
        return Ok(declaration_page(module, found));
    }
    member_page(module, found, &parts[2])
}

fn split_path(path: &str) -> Vec<String> {
    let mut path = path.trim().to_string();
    if let Some(rest) = path.strip_prefix("@std/") {
        path = rest.to_string();
        if let Some((name, tail)) = path.split_once(".ms") {
            path = format!("{name}{tail}");
        }
    }
    path.splitn(3, '.').map(str::to_string).collect()
}

fn find_module(name: &str) -> Option<&'static ApiModule> {
    modules()
        .iter()
        .find(|m| short_name(&m.path) == name || package_name(&m.path) == name)
}

fn import_line(m: &ApiModule) -> String {
    if m.path == "prelude" {
        "available in every module; no import".to_string()
    } else {
        format!("import Name from {:?}", m.path)
    }
}

fn module_page(m: &ApiModule) -> String {
    let mut b = format!("{}: {}\n", m.path, import_line(m));
    for (i, d) in m.declarations.iter().enumerate() {
        if i == MODULE_LINES {
            b += &format!(
                "... {} more; narrow with `ms search_symbol <words>`\n",
                m.declarations.len() - MODULE_LINES
            );
            break;
        }
        if d.kind == "fn" && !d.declaration.is_empty() {
            b += &one_line(&d.declaration, LINE_WIDTH);
            b.push('\n');
            continue;
        }
        b += &format!("{} {}", d.kind, bare(&d.name));
        let doc = first_line(&d.doc, 90);
        if !doc.is_empty() {
            b += &format!(" # {doc}");
        }
        b.push('\n');
    }
    b += &format!("Details: ms search_symbol {}.<Name>\n", short_name(&m.path));
    clip_text(&b, PAGE_BUDGET)
}

fn declaration_page(m: &ApiModule, d: &ApiDeclaration) -> String {
    let mut b = format!("{} {} ({})\n", d.kind, d.name, m.path);
    if m.path != "prelude" {
        b += &format!("import {} from {:?}\n", bare(&d.name), m.path);
    }
    let doc = cap_doc(&d.doc, 500);
    if !doc.is_empty() {
        b += &doc;
        b.push('\n');
    }
    if d.members.is_empty() {
        if !d.declaration.is_empty() {
            b += &clip_lines(d.declaration.trim_end_matches('\n'), 12);
            b.push('\n');
        }
        return clip_text(&b, PAGE_BUDGET);
    }
    b += &format!("members ({}):\n", d.members.len());
    for (i, member) in d.members.iter().enumerate() {
        let line = format!("  {}\n", one_line(&member.signature, LINE_WIDTH));
        if b.len() + line.len() > PAGE_BUDGET - 160 {
            b += &format!(
                "  ... {} more; use `ms search_symbol {}.{}.<member>`\n",
                d.members.len() - i,
                short_name(&m.path),
                bare(&d.name)
            );
            break;
        }
        b += &line;
    }
    b += &format!(
        "Details: ms search_symbol {}.{}.<member>\n",
        short_name(&m.path),
        bare(&d.name)
    );
    b
}

fn member_page(m: &ApiModule, d: &ApiDeclaration, name: &str) -> Result<String, String> {
    let mut b = String::new();
    let mut count = 0;
    for member in &d.members {
        if bare(&member.name) != name {
            continue;
        }
        count += 1;
        if count > 3 {
            break;
        }
        b += &format!(
            "{}.{} ({})\n{}\n",
            d.name,
            member.name,
            m.path,
            clip_lines(member.signature.trim_end_matches('\n'), 6)
        );
        let doc = cap_doc(&member.doc, 800);
        if !doc.is_empty() {
            b += &doc;
            b.push('\n');
        }
    }
    if count == 0 {
        return Err(format!(
            "{} has no member {:?}; see `ms search_symbol {}.{}`",
            d.name,
            name,
            short_name(&m.path),
            bare(&d.name)
        ));
    }
    Ok(clip_text(&b, PAGE_BUDGET))
}

fn clip_lines(text: &str, limit: usize) -> String {
    let lines: Vec<&str> = text.split('\n').collect();
    if lines.len() <= limit {
        return text.to_string();
    }
    let mut kept: Vec<&str> = lines[..limit].to_vec();
    kept.push("...");
    kept.join("\n")
}

/// Keeps the head and tail of long text, where errors and summaries usually sit.
pub(crate) fn clip_text(s: &str, limit: usize) -> String {
    if s.len() <= limit {
        return s.to_string();
    }
    // The omission marker counts against the limit.
    let room = limit.saturating_sub(48);
    let (head, tail) = (room * 2 / 3, room / 3);
    let bytes = s.as_bytes();
    let mut out = Vec::new();
    out.extend_from_slice(&bytes[..head]);
    out.extend_from_slice(
        format!("\n[... {} bytes omitted ...]\n", s.len() - head - tail).as_bytes(),
    );
    out.extend_from_slice(&bytes[s.len() - tail..]);
    String::from_utf8_lossy(&out).into_owned()
}
