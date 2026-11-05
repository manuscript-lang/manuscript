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

/// Keeps bounded lookup pages useful without presenting a truncated program.
/// Complete examples, commands and output stay together in the full reference.
fn cap_doc(doc: &str, limit: usize) -> String {
    let mut prose = String::new();
    let mut fenced = false;
    for line in doc.lines() {
        if line.trim_start().starts_with("```") {
            fenced = !fenced;
            continue;
        }
        if fenced || line.trim_start().starts_with("<!-- manuscript-example:") {
            continue;
        }
        prose.push_str(line);
        prose.push('\n');
    }
    let doc = prose.trim();
    if doc.len() <= limit {
        return doc.to_string();
    }
    let mut end = limit.saturating_sub('…'.len_utf8());
    while !doc.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}…", doc[..end].trim_end())
}

fn reference_link(module: &ApiModule) -> String {
    let path = module.path.strip_prefix("@std/").unwrap_or(&module.path);
    let path = path.strip_suffix(".ms").unwrap_or(path);
    format!(
        "Full reference and examples: https://manuscript-lang.github.io/manuscript/standard-library/reference/{path}/\n"
    )
}

/// The standard modules, `prelude` first and the rest by path.
pub(crate) fn modules(syms: ms_syntax::Names) -> &'static [ApiModule] {
    static SORTED: OnceLock<Vec<ApiModule>> = OnceLock::new();
    SORTED.get_or_init(|| {
        let mut all = standard_library(syms).to_vec();
        all.sort_by(|a, b| {
            (a.path != "prelude")
                .cmp(&(b.path != "prelude"))
                .then_with(|| a.path.cmp(&b.path))
        });
        all
    })
}

/// The short names of every standard module, prelude first.
pub fn module_names(syms: ms_syntax::Names) -> Vec<String> {
    modules(syms)
        .iter()
        .map(|m| short_name(&m.path).to_string())
        .collect()
}

/// The index stays under this many bytes (the guide-pages test budget is 3500): agents read it
/// whole, so it narrows its lines as modules are added instead of growing past the budget.
const INDEX_BUDGET: usize = 3400;

/// Lists each module with a few of its names.
pub fn index(syms: ms_syntax::Names) -> String {
    let header = "Standard modules (prelude needs no import).\n`ms search_symbol <module>` lists one, `ms search_symbol <module>.<Name>` shows a declaration, `ms search_symbol <words>` searches.\n\n";
    let mut width = 84;
    loop {
        let body = index_lines(syms, width);
        if header.len() + body.len() <= INDEX_BUDGET || width <= 24 {
            return format!("{header}{body}");
        }
        width -= 4;
    }
}

/// One line per module: the name, then declarations while the line stays within `width`.
fn index_lines(syms: ms_syntax::Names, width: usize) -> String {
    let mut b = String::new();
    for m in modules(syms) {
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
pub fn page(syms: ms_syntax::Names, path: &str) -> Result<String, String> {
    let parts = split_path(path);
    let Some(module) = find_module(syms, &parts[0]) else {
        return Err(format!(
            "no standard module {:?}; modules: {}",
            parts[0],
            module_names(syms).join(", ")
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

fn find_module(syms: ms_syntax::Names, name: &str) -> Option<&'static ApiModule> {
    modules(syms)
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
            b += &format!(" // {doc}");
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
    if d.doc.contains("```") {
        b += &reference_link(m);
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
        if member.doc.contains("```") {
            b += &reference_link(m);
        }
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

#[cfg(test)]
mod bounded_docs_tests {
    use super::{cap_doc, reference_link};
    use crate::guide::api::ApiModule;

    #[test]
    fn reference_links_follow_generated_slugs() {
        for (path, slug) in [
            ("@std/data/json.ms", "data/json"),
            ("@std/core.ms", "core"),
            ("prelude", "prelude"),
        ] {
            let module = ApiModule {
                path: path.to_string(),
                declarations: Vec::new(),
            };
            assert_eq!(
                reference_link(&module),
                format!(
                    "Full reference and examples: https://manuscript-lang.github.io/manuscript/standard-library/reference/{slug}/\n"
                )
            );
        }
    }

    #[test]
    fn examples_are_linked_instead_of_cut_into_fragments() {
        let program = include_str!("../../tests/lint_promises/waited.ms");
        let doc = format!(
            "Read a result.\n\n<!-- manuscript-example: {{}} -->\n```manuscript\n{program}\n```\n\n```sh\nms run example.ms\n```\n\n```text\ndone\n```\n\nKeep the owner alive."
        );
        let short = cap_doc(&doc, 500);
        assert!(short.contains("Read a result."));
        assert!(short.contains("Keep the owner alive."));
        assert!(!short.contains("```"));
        assert!(!short.contains("manuscript-example"));
        assert!(!short.contains(program.trim()));
        assert!(!short.contains("done"));
    }

    #[test]
    fn prose_budget_respects_multibyte_text() {
        let short = cap_doc(&"é".repeat(300), 500);
        assert!(short.len() <= 500);
        assert!(short.ends_with('…'));
    }

    // Read the actual documented program, invocation and output together; no copied program fixture.
    fn producer_example() -> &'static str {
        let page = include_str!("../../../../documentation/core-language/concurrency/streams.md");
        let start = page.find("<!-- manuscript-example:").unwrap();
        let output = page[start..].find("```text\n").unwrap() + start;
        let end = page[output + 8..].find("\n```").unwrap() + output + 8 + 4;
        &page[start..end]
    }

    #[test]
    fn complete_source_comment_units_below_at_and_above_budget() {
        let source = include_str!("../../../../stdlib/core.ms");
        let start = source.find("<!-- manuscript-example:").unwrap();
        let output = source[start..].find("```text\n").unwrap() + start;
        let end = source[output + 8..].find("\n```").unwrap() + output + 8 + 4;
        let example = &source[start..end];
        assert!(example.contains("ms run print-line.ms"));
        for limit in [500, 800] {
            for size in [limit - 1, limit, limit + 1] {
                let prefix = "Review printed output. ";
                let padding = "x".repeat(size - prefix.len() - example.len() - 2);
                let doc = format!("{prefix}{padding}\n\n{example}");
                assert_eq!(doc.len(), size);
                let short = cap_doc(&doc, limit);
                assert_eq!(short, format!("{prefix}{padding}"));
                assert!(short.len() <= limit);
                assert!(!short.contains("```"));
                assert!(!short.contains("manuscript-example"));
                assert!(!short.contains("ms run print-line.ms"));
                assert!(!short.contains("total: 3"));
            }
        }
    }

    #[test]
    fn complete_example_is_atomic_around_each_summary_budget() {
        let example = producer_example();
        assert!(example.contains("try producer.wait()"));
        assert!(example.contains("ms test example.ms"));
        assert!(example.contains("PASS example.ms::sum a producer stream"));
        for limit in [500, 800] {
            // Exercise boundaries in the retained prose, with the complete example before
            // and after the cut. Fences are omitted even when they would fit a larger budget.
            for size in [limit - 1, limit, limit + 1] {
                let prose = format!(
                    "Review a producer. {}",
                    "x".repeat(size - "Review a producer. ".len())
                );
                assert_eq!(prose.len(), size);
                for doc in [
                    format!("{prose}\n\n{example}"),
                    format!("{example}\n\n{prose}"),
                ] {
                    let short = cap_doc(&doc, limit);
                    assert!(short.starts_with("Review a producer."));
                    assert!(short.len() <= limit);
                    assert_eq!(short.ends_with('…'), size > limit);
                    assert!(!short.contains("```"));
                    assert!(!short.contains("manuscript-example"));
                    assert!(!short.contains("try producer.wait()"));
                    assert!(!short.contains("ms test example.ms"));
                    assert!(!short.contains("PASS example.ms"));
                }
            }
        }
    }

    #[test]
    fn multiple_complete_examples_and_unicode_remain_atomic() {
        let example = producer_example();
        let doc = format!(
            "Review café output.\n{example}\n\nSecond example.\n{example}\n{}",
            "é🙂".repeat(200)
        );
        for limit in [500, 800] {
            let short = cap_doc(&doc, limit);
            assert!(short.starts_with("Review café output."));
            assert!(short.contains("Second example."));
            assert!(short.len() <= limit);
            assert!(!short.contains("```"));
            assert!(!short.contains("manuscript-example"));
            assert!(!short.contains("producer.wait()"));
            assert!(!short.contains("ms test"));
            assert!(!short.contains("1 tests, 0 failed"));
        }
    }

    #[test]
    fn actual_pipe_pages_keep_signatures_and_link_complete_example() {
        let syms = ms_syntax::Names::global();
        let module = super::modules(syms)
            .iter()
            .find(|m| m.path == "@std/io/io.ms")
            .unwrap();
        let mut pipe = module
            .declarations
            .iter()
            .find(|d| super::bare(&d.name) == "Pipe")
            .unwrap()
            .clone();
        let example = producer_example();
        pipe.doc = format!("Review producer ownership.\n\n{example}");
        let writer = pipe
            .members
            .iter_mut()
            .find(|m| super::bare(&m.name) == "writer")
            .unwrap();
        writer.doc = pipe.doc.clone();
        let signature = super::one_line(&writer.signature, super::LINE_WIDTH);
        let public = crate::guide::docgen::render_site_module(&ApiModule {
            path: module.path.clone(),
            declarations: vec![pipe.clone()],
        });
        assert_eq!(
            public.matches(example).count(),
            2,
            "full reference must not truncate either source comment"
        );
        for page in [
            super::declaration_page(module, &pipe),
            super::member_page(module, &pipe, "writer").unwrap(),
        ] {
            assert!(page.len() <= super::PAGE_BUDGET);
            assert!(page.contains("Review producer ownership."));
            let normalized = page.split_whitespace().collect::<Vec<_>>().join(" ");
            assert!(
                normalized.contains(&signature),
                "missing {signature:?} in {page}"
            );
            assert!(page.contains(&reference_link(module)));
            assert!(!page.contains("```"));
            assert!(!page.contains("manuscript-example"));
            assert!(!page.contains("try producer.wait()"));
            assert!(!page.contains("ms test example.ms"));
            assert!(!page.contains("PASS example.ms"));
        }
    }
}
