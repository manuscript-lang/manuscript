//! Symbol lookup for `ms search_symbol`: project declarations found by name,
//! each described with the hover, definition and references the server gives.

use crate::analysis::{Document, Documents, analyze};
use crate::json::Json;
use crate::nav::{self, Navigate};
use crate::text::{Position, utf16_length};
use crate::uri;
use crate::workspace::{workspace_references, workspace_symbols};

/// One project declaration found by name.
#[derive(Clone, Debug)]
pub struct SymbolMatch {
    pub name: String,
    /// `fn`, `type` or `const`.
    pub kind: &'static str,
    /// `file:line:column`.
    pub definition: String,
    /// Type and documentation, as Markdown.
    pub hover: String,
    /// `file:line:column`, declaration included.
    pub references: Vec<String>,
}

/// Declarations in the project containing `dir` whose name fuzzily matches
/// `query`: exact names rank first, then prefixes, substrings, ordered
/// subsequences and near-misses of five or more letters. At most `limit`
/// matches are described; the count returned is every match found.
pub fn search_symbols(
    dir: &str,
    query: &str,
    limit: usize,
) -> Result<(Vec<SymbolMatch>, usize), String> {
    let mut root = std::path::absolute(dir)
        .map_err(|e| e.to_string())?
        .to_string_lossy()
        .into_owned();
    if let Some(manifest) = ms_driver::project::find_manifest(&format!("{root}/x.ms")) {
        root = ms_driver::project::gopath::dir(&manifest);
    }
    let symbols = workspace_symbols(&Documents::new(), &[root], "", None).unwrap_or_default();
    let mut found: Vec<(i32, String, &'static str, String)> = Vec::new();
    for symbol in &symbols {
        let (Some(name), Some(location)) = (
            symbol.get("name").and_then(Json::as_str),
            symbol.get("location").and_then(locations_of),
        ) else {
            continue;
        };
        let rank = name_rank(name, query);
        if name.is_empty() || rank < 0 {
            continue;
        }
        let kind = match symbol.get("kind").and_then(Json::as_i64) {
            Some(5) => "type",
            Some(14) => "const",
            _ => "fn",
        };
        found.push((rank, name.to_string(), kind, location));
    }
    found.sort_by(|a, b| (a.0, &a.1).cmp(&(b.0, &b.1)));
    let total = found.len();
    let mut matches = Vec::new();
    for (_, name, kind, location) in found.into_iter().take(limit) {
        let Some((file, line, column)) = split_location(&location) else {
            continue;
        };
        let Ok(info) = query_symbol(file, line, column) else {
            continue;
        };
        matches.push(SymbolMatch {
            name,
            kind,
            definition: location,
            hover: info.0,
            references: info.1,
        });
    }
    Ok((matches, total))
}

/// The first `file:line:column` of an LSP location or location list.
fn locations_of(value: &Json) -> Option<String> {
    flatten(value).into_iter().next()
}

/// Flattens LSP location results into `file:line:column` strings.
fn flatten(value: &Json) -> Vec<String> {
    let one = |l: &Json| {
        let start = l.get("range")?.get("start")?;
        let number = |key| start.get(key)?.as_i64();
        Some(format!(
            "{}:{}:{}",
            uri::filename(l.get("uri")?.as_str().filter(|u| !u.is_empty())?),
            number("line")? + 1,
            number("character")? + 1
        ))
    };
    match value {
        Json::Arr(many) => many.iter().filter_map(one).collect(),
        other => one(other).into_iter().collect(),
    }
}

fn split_location(location: &str) -> Option<(&str, usize, usize)> {
    let (rest, column) = location.rsplit_once(':')?;
    let (file, line) = rest.rsplit_once(':')?;
    Some((file, line.parse().ok()?, column.parse().ok()?))
}

/// Hover text and references for a 1-based line and character column.
fn query_symbol(path: &str, line: usize, column: usize) -> Result<(String, Vec<String>), String> {
    let text = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let absolute = std::path::absolute(path).map_err(|e| e.to_string())?;
    let d = Document::new(uri::file_uri(&absolute.to_string_lossy()), text);
    let at = character_position(&d.text, line, column)?;
    let docs = Documents::new();
    let checked = analyze(&d, &docs);
    if checked.program.is_none() {
        return Err(format!("cannot analyze {path}; run check for diagnostics"));
    }
    let index = checked.index();
    let hover = nav::navigation(&checked, &d, at, Navigate::Hover, index);
    let hover = hover
        .get("contents")
        .and_then(|c| c.get("value"))
        .and_then(Json::as_str)
        .unwrap_or_default()
        .to_string();
    let references = workspace_references(&checked, index, &d, &docs, at, true, None);
    Ok((hover, references.iter().flat_map(flatten).collect()))
}

/// Converts a 1-based line and character column to an LSP position.
fn character_position(text: &str, line: usize, column: usize) -> Result<Position, String> {
    if line < 1 || column < 1 {
        return Err("line and column are 1-based".into());
    }
    let lines: Vec<&str> = text.split('\n').collect();
    let Some(row) = lines.get(line - 1) else {
        return Err(format!(
            "line {line} is past the end of the file ({} lines)",
            lines.len()
        ));
    };
    let row = row.strip_suffix('\r').unwrap_or(row);
    let before: String = row.chars().take(column - 1).collect();
    if column > row.chars().count() + 1 {
        return Err(format!("column {column} is past the end of line {line}"));
    }
    Ok(Position {
        line: line - 1,
        character: utf16_length(before.as_bytes()),
    })
}

/// Scores how well `name` matches `query`: 0 exact, 1 prefix, 2 substring,
/// 3 ordered subsequence, 4 near miss; -1 means no match. Case and
/// underscores are ignored, and a member matches on its own name as well as
/// its qualified one.
pub fn name_rank(name: &str, query: &str) -> i32 {
    let query = fold(query);
    let own = name.rsplit_once('.').map(|(_, last)| last);
    [Some(name), own]
        .into_iter()
        .flatten()
        .map(|candidate| loose_rank(&fold(candidate), &query))
        .filter(|rank| *rank >= 0)
        .min()
        .unwrap_or(-1)
}

fn fold(s: &str) -> String {
    s.to_lowercase().replace(['_', '.', ' '], "")
}

fn loose_rank(name: &str, query: &str) -> i32 {
    let (n, q) = (name.as_bytes(), query.as_bytes());
    if q.is_empty() {
        -1
    } else if name == query {
        0
    } else if name.starts_with(query) {
        1
    } else if name.contains(query) {
        2
    } else if q.len() >= 3 && n.first() == q.first() && is_subsequence(q, n) {
        3
    } else if q.len() >= 5
        && (edit_distance_at_most(n, q, 2)
            || n.len() > q.len() && edit_distance_at_most(&n[..q.len()], q, 2))
    {
        4
    } else {
        -1
    }
}

fn is_subsequence(needle: &[u8], haystack: &[u8]) -> bool {
    let mut wanted = needle.iter();
    let mut next = wanted.next();
    for byte in haystack {
        if next == Some(byte) {
            next = wanted.next();
        }
    }
    next.is_none()
}

/// Whether `a` and `b` differ by at most `limit` single-byte edits
/// (insert, delete, substitute, or swap adjacent).
fn edit_distance_at_most(a: &[u8], b: &[u8], limit: usize) -> bool {
    if a.len().abs_diff(b.len()) > limit {
        return false;
    }
    let mut before: Vec<usize> = vec![0; b.len() + 1];
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    for i in 1..=a.len() {
        let mut row = vec![0; b.len() + 1];
        row[0] = i;
        for j in 1..=b.len() {
            let cost = usize::from(a[i - 1] != b[j - 1]);
            row[j] = (prev[j] + 1).min(row[j - 1] + 1).min(prev[j - 1] + cost);
            if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                row[j] = row[j].min(before[j - 2] + 1);
            }
        }
        before = std::mem::replace(&mut prev, row);
    }
    prev[b.len()] <= limit
}

#[cfg(test)]
mod tests {
    use super::name_rank;

    #[test]
    fn ranks_names_loosely() {
        assert_eq!(name_rank("read_file", "readFile"), 0);
        assert_eq!(name_rank("Config.load", "load"), 0);
        assert_eq!(name_rank("read_file", "read"), 1);
        assert_eq!(name_rank("read_file", "file"), 2);
        assert_eq!(name_rank("read_file", "rdf"), 3);
        assert_eq!(name_rank("read_file", "raed_file"), 4);
        assert_eq!(name_rank("read_file", "zzz"), -1);
        assert_eq!(name_rank("read_file", ""), -1);
    }
}
