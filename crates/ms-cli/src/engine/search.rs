//! `ms search_symbol`: project declarations by name, then standard-library
//! symbols, or a bounded page of standard-library reference.

use std::path::Path;

use ms_guide::Match;
use ms_lsp::query::{SymbolMatch, name_rank, search_symbols};

use crate::backend::{BackendError, BackendResult, Io, SearchSymbolRequest};
use crate::json::Json;
use crate::util::emit_json;

const MAX_USES: usize = 5;
const OUTPUT_BUDGET: usize = 3500;

/// One described symbol, from the project or the standard library.
struct Described {
    name: String,
    kind: String,
    definition: String,
    symbol_type: String,
    doc: String,
    uses: Vec<String>,
    std: bool,
}

pub(super) fn search_symbol(request: &SearchSymbolRequest, io: &mut Io) -> BackendResult {
    if request.names.is_empty() {
        let _ = write!(io.stdout, "{}", ms_guide::index());
        return Ok(0);
    }
    let query = request.names.join(" ");
    let limit = request.limit;
    let (matches, total) = search_symbols(".", &request.names.concat(), limit)
        .map_err(|e| BackendError::Failed(format!("ms search_symbol: {e}")))?;
    if request.names.len() == 1
        && !request.json
        && !matches.iter().any(|m| name_rank(&m.name, &query) == 0)
        && let Ok(page) = ms_guide::page(&query)
    {
        let _ = write!(io.stdout, "{page}");
        return Ok(0);
    }
    let project_count = matches.len();
    let mut described: Vec<Described> = matches.into_iter().map(describe_project).collect();
    described.extend(library_matches(
        &query,
        request.names.len(),
        project_count,
        limit,
    ));
    if request.json {
        return Ok(emit_json(io, &document(&query, total, &described), 0));
    }
    if described.is_empty() {
        let _ = writeln!(
            io.stdout,
            "No project or standard-library symbol like {query:?}. Try a shorter name."
        );
        return Ok(0);
    }
    let mut out = String::new();
    for m in &described {
        out += &format!("{}  {}  {}\n", m.name, m.kind, m.definition);
        if !m.symbol_type.is_empty() && m.symbol_type != format!("{}: {}", m.name, m.name) {
            out += &format!("  {}\n", clip(&m.symbol_type, 200));
        }
        if !m.doc.is_empty() {
            out += &format!("  # {}\n", clip(&m.doc, 160));
        }
        if m.std {
            out += &format!("  details: ms search_symbol {}\n", m.name);
            continue;
        }
        let shown = &m.uses[..m.uses.len().min(MAX_USES)];
        out += &format!("  used ({})", m.uses.len());
        if !shown.is_empty() {
            out += &format!(": {}", shown.join(", "));
        }
        if m.uses.len() > shown.len() {
            out += ", ...";
        }
        out += "\n";
    }
    if total > project_count {
        out += &format!(
            "+{} more project matches; use a longer name or --limit\n",
            total - project_count
        );
    }
    if out.len() > OUTPUT_BUDGET {
        let mut cut = OUTPUT_BUDGET;
        while !out.is_char_boundary(cut) {
            cut -= 1;
        }
        out.truncate(cut);
        out += "\n[... output cut; use a longer name ...]\n";
    }
    let _ = write!(io.stdout, "{out}");
    Ok(0)
}

fn describe_project(m: SymbolMatch) -> Described {
    let (symbol_type, doc) = split_hover(&m.hover);
    Described {
        name: m.name,
        kind: m.kind.to_string(),
        definition: display_path(&m.definition),
        symbol_type,
        doc,
        uses: m
            .references
            .iter()
            .filter(|r| **r != m.definition)
            .map(|r| display_path(r))
            .collect(),
        std: false,
    }
}

/// Standard-library symbols follow, matched on names only and leaving room for
/// at least two even when the project fills the limit.
fn library_matches(query: &str, words: usize, project: usize, limit: usize) -> Vec<Described> {
    let concept = ms_guide::search(query, 50);
    let mut library: Vec<(i32, &Match)> = Vec::new();
    for m in &concept {
        let (path, own) = (name_rank(&m.path, query), name_rank(&m.name, query));
        let rank = if own >= 0 && (path < 0 || own < path) {
            own
        } else {
            path
        };
        if rank >= 0 {
            library.push((rank, m));
        }
    }
    if project == 0 && (words > 1 || library.is_empty()) {
        // Words rather than a name: top up with the meaning-based ranking, as for read file lines.
        let seen: Vec<&str> = library.iter().map(|(_, m)| m.path.as_str()).collect();
        let rest: Vec<(i32, &Match)> = concept
            .iter()
            .filter(|m| !seen.contains(&m.path.as_str()))
            .map(|m| (5, m))
            .collect();
        library.extend(rest);
    }
    library.sort_by_key(|(rank, _)| *rank);
    library
        .into_iter()
        .take(limit.saturating_sub(project).max(2))
        .map(|(_, m)| Described {
            name: m.path.clone(),
            kind: m.kind.clone(),
            definition: format!("std:{}", m.module),
            symbol_type: m.signature.split_whitespace().collect::<Vec<_>>().join(" "),
            doc: m.doc.clone(),
            uses: Vec::new(),
            std: true,
        })
        .collect()
}

fn document(query: &str, total: usize, described: &[Described]) -> Json {
    let matches = described.iter().map(|m| {
        let mut entry = Json::object()
            .with("name", Json::str(&m.name))
            .with("kind", Json::str(&m.kind))
            .with("definition", Json::str(&m.definition));
        if !m.symbol_type.is_empty() {
            entry = entry.with("type", Json::str(&m.symbol_type));
        }
        if !m.doc.is_empty() {
            entry = entry.with("doc", Json::str(&m.doc));
        }
        if !m.uses.is_empty() {
            entry = entry.with("uses", Json::Arr(m.uses.iter().map(Json::str).collect()));
        }
        entry.with("origin", Json::str(if m.std { "std" } else { "project" }))
    });
    Json::object()
        .with("format", Json::int(1))
        .with("query", Json::str(query))
        .with("project_total", Json::int(total as i64))
        .with("matches", Json::Arr(matches.collect()))
}

fn clip(text: &str, limit: usize) -> String {
    if text.chars().count() <= limit {
        return text.to_string();
    }
    let kept: String = text.chars().take(limit - 1).collect();
    format!("{kept}…")
}

/// Separates the language server's hover Markdown into a type line and a description.
fn split_hover(hover: &str) -> (String, String) {
    let hover = hover.trim();
    let body = hover.strip_prefix("```manuscript\n").unwrap_or(hover);
    match body.split_once("\n```") {
        Some((inner, rest)) => (inner.replace('\n', " "), first_sentence(rest)),
        None => (hover.replace('\n', " "), String::new()),
    }
}

fn first_sentence(text: &str) -> String {
    let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    match text.find(". ") {
        Some(i) => text[..=i].to_string(),
        None => text,
    }
}

/// Shortens an absolute `file:line:column` under the working directory.
fn display_path(path: &str) -> String {
    if !Path::new(path).is_absolute() {
        return path.to_string();
    }
    let Ok(wd) = std::env::current_dir() else {
        return path.to_string();
    };
    match Path::new(path).strip_prefix(&wd) {
        Ok(rel) => rel.to_string_lossy().into_owned(),
        Err(_) => path.to_string(),
    }
}
