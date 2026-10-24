//! Fuzzy standard-library search.

use crate::guide::api::standard_library;
use crate::guide::pages::{clip_text, first_line, short_name, std_path};
use std::collections::HashSet;
use std::sync::OnceLock;

/// One searchable standard-library declaration or member.
struct Entry {
    module: String,
    name: String,
    kind: String,
    signature: String,
    doc: String,
    words: Vec<String>,
    doc_words: Vec<String>,
    module_words: Vec<String>,
}

fn standard_index() -> &'static [Entry] {
    static INDEX: OnceLock<Vec<Entry>> = OnceLock::new();
    INDEX.get_or_init(|| {
        let mut index = Vec::new();
        for module in standard_library() {
            let short = short_name(&module.path);
            for d in &module.declarations {
                let signature = d.declaration.trim();
                let signature = if signature.is_empty() {
                    d.ty.as_str()
                } else {
                    signature
                };
                index.push(new_entry(
                    &module.path,
                    short,
                    &d.name,
                    &d.kind,
                    &first_block(signature),
                    &d.doc,
                ));
                for m in &d.members {
                    index.push(new_entry(
                        &module.path,
                        short,
                        &format!("{}.{}", d.name, m.name),
                        &m.kind,
                        &m.signature,
                        &m.doc,
                    ));
                }
            }
        }
        index
    })
}

/// Keeps the leading paragraph and at most 3 lines, so a native type with
/// dozens of members cannot flood a result.
fn first_block(s: &str) -> String {
    let s = s.split("\n\n").next().unwrap_or(s);
    let lines: Vec<&str> = s.trim_end_matches('\n').split('\n').collect();
    if lines.len() > 3 {
        let mut kept = lines[..3].to_vec();
        kept.push("    ...");
        return kept.join("\n");
    }
    lines.join("\n")
}

fn new_entry(path: &str, short: &str, name: &str, kind: &str, signature: &str, doc: &str) -> Entry {
    Entry {
        module: path.to_string(),
        name: name.to_string(),
        kind: kind.to_string(),
        signature: signature.to_string(),
        doc: doc.to_string(),
        words: split_words(name),
        doc_words: split_words(doc),
        module_words: split_words(short),
    }
}

/// Lowercases text and splits on punctuation, underscores and camelCase.
fn split_words(s: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut current = String::new();
    let mut flush = |current: &mut String| {
        if !current.is_empty() {
            words.push(current.to_lowercase());
            current.clear();
        }
    };
    let runes: Vec<char> = s.chars().collect();
    for (i, &r) in runes.iter().enumerate() {
        if r.is_alphabetic() || r.is_numeric() {
            if r.is_uppercase() && i > 0 && runes[i - 1].is_lowercase() {
                flush(&mut current);
            }
            current.push(r);
        } else {
            flush(&mut current);
        }
    }
    flush(&mut current);
    words
}

const STOP_WORDS: [&str; 14] = [
    "a", "an", "the", "of", "to", "in", "for", "with", "by", "from", "and", "or", "how", "do",
];

/// Drops filler so "sort by key" matches on "sort" and "key".
fn significant_words(query: &str) -> Vec<String> {
    let all = split_words(query);
    let kept: Vec<String> = all
        .iter()
        .filter(|w| !STOP_WORDS.contains(&w.as_str()) && w.as_str() != "i")
        .cloned()
        .collect();
    if kept.is_empty() { all } else { kept }
}

/// One ranked lookup result.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Match {
    /// Module path (`@std/json.ms` or `prelude`).
    pub module: String,
    /// Declaration or `Declaration.member` name.
    pub name: String,
    /// Declaration or member kind.
    pub kind: String,
    /// Signature excerpt.
    pub signature: String,
    /// One-line description.
    pub doc: String,
    /// The `ms search_symbol` path, such as `json.parse`.
    pub path: String,
    /// Ranking score; higher is better.
    pub score: i64,
}

/// Separates name and module matches from matches in documentation prose.
const STRONG_SCORE: i64 = 25;

/// Ranks standard declarations and members against a loose query. Every query
/// word must match somewhere, tolerating prefixes, subsequences and small
/// typos, so "read file", "jsn parse" and "fs.read" all find APIs.
pub fn search(query: &str, limit: usize) -> Vec<Match> {
    let tokens = significant_words(query);
    if tokens.is_empty() {
        return Vec::new();
    }
    let limit = if limit == 0 { 5 } else { limit };
    // Prefer entries matching every word; when none do, fall back to the
    // entries matching the most words so "read stdin lines" still finds help.
    let mut matches: Vec<Match> = Vec::new();
    let mut best = 0;
    for e in standard_index() {
        let (mut total, mut matched, mut strong) = (0i64, 0usize, 0usize);
        for token in &tokens {
            let score = score_token(token, e);
            if score > 0 {
                total += score;
                matched += 1;
                if score >= STRONG_SCORE {
                    strong += 1;
                }
            }
        }
        // A partial match must hinge on a name or module word, never on prose alone.
        if matched == 0 || matched < best || (matched < tokens.len() && strong == 0) {
            continue;
        }
        if matched > best {
            best = matched;
            matches.clear();
        }
        // Shorter names read as more central, so break ties toward them.
        total = total * 10 + name_coverage(&tokens, e) - e.name.len().min(9) as i64;
        matches.push(Match {
            module: e.module.clone(),
            name: e.name.clone(),
            kind: e.kind.clone(),
            signature: e.signature.clone(),
            doc: first_line(&e.doc, 120),
            path: std_path(&e.module, &e.name),
            score: total,
        });
    }
    matches.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            // The prelude spelling needs no import, so it wins a tie with a module re-export.
            .then_with(|| (a.module != "prelude").cmp(&(b.module != "prelude")))
            .then_with(|| {
                format!("{}.{}", a.module, a.name).cmp(&format!("{}.{}", b.module, b.name))
            })
    });
    let mut matches = drop_duplicates(matches);
    matches.truncate(limit);
    matches
}

/// Rewards names whose own words the query spells out and penalizes names
/// with extra words the query never mentioned.
fn name_coverage(tokens: &[String], e: &Entry) -> i64 {
    let covered = e.words.iter().filter(|w| tokens.contains(w)).count() as i64;
    15 * covered - 10 * (e.words.len() as i64 - covered)
}

/// Removes repeats of one declaration that several modules expose.
fn drop_duplicates(matches: Vec<Match>) -> Vec<Match> {
    let mut seen = HashSet::new();
    matches
        .into_iter()
        .filter(|m| seen.insert(format!("{}\0{}", m.name, m.signature)))
        .collect()
}

fn synonyms(token: &str) -> &'static [&'static str] {
    match token {
        "sort" => &["sorted"],
        "order" => &["sorted"],
        "uppercase" => &["upper"],
        "lowercase" => &["lower"],
        "size" => &["length", "count"],
        "len" => &["length"],
        "delete" => &["remove"],
        "push" => &["append"],
        "print" => &["write", "stdout"],
        "stdin" => &["read_line"],
        "concat" => &["join", "concat"],
        "split" => &["split", "lines"],
        "env" => &["environment"],
        "random" => &["random"],
        _ => &[],
    }
}

fn score_token(token: &str, e: &Entry) -> i64 {
    let mut best = score_words(token, e);
    for alias in synonyms(token) {
        best = best.max(score_words(alias, e) * 9 / 10);
    }
    best
}

fn score_words(token: &str, e: &Entry) -> i64 {
    let mut best = 0;
    for word in &e.words {
        best = best.max(score_word(token, word, 100));
    }
    for word in &e.module_words {
        best = best.max(score_word(token, word, 60));
    }
    for word in &e.doc_words {
        if token.len() >= 4 {
            best = best.max(score_word(token, word, 12));
        }
    }
    best
}

/// Scores one query word against a candidate word; `weight` scales the field.
fn score_word(token: &str, word: &str, weight: i64) -> i64 {
    if token == word {
        weight
    } else if word.starts_with(token) && token.len() >= 2 {
        weight * 7 / 10
    } else if token.len() >= 3 && word.contains(token) {
        weight / 2
    } else if weight < 50 {
        0 // prose matches must be exact words or prefixes
    } else if token.len() >= 3
        && token.as_bytes()[0] == word.as_bytes()[0]
        && is_subsequence(token, word)
    {
        weight * 3 / 10
    } else if token.len() >= 5 && edit_distance(token, word) <= allowed_typos(token.len()) {
        weight * 4 / 10
    } else {
        0
    }
}

fn allowed_typos(length: usize) -> usize {
    if length >= 7 { 2 } else { 1 }
}

fn is_subsequence(small: &str, large: &str) -> bool {
    let (small, large) = (small.as_bytes(), large.as_bytes());
    let mut i = 0;
    for &b in large {
        if i < small.len() && small[i] == b {
            i += 1;
        }
    }
    i == small.len()
}

/// The Damerau-Levenshtein distance with adjacent transpositions.
fn edit_distance(a: &str, b: &str) -> usize {
    if a.len().abs_diff(b.len()) > 2 {
        return 3;
    }
    let (ra, rb): (Vec<char>, Vec<char>) = (a.chars().collect(), b.chars().collect());
    let mut d = vec![vec![0usize; rb.len() + 1]; ra.len() + 1];
    for (i, row) in d.iter_mut().enumerate() {
        row[0] = i;
    }
    for (j, cell) in d[0].iter_mut().enumerate() {
        *cell = j;
    }
    for i in 1..=ra.len() {
        for j in 1..=rb.len() {
            let cost = usize::from(ra[i - 1] != rb[j - 1]);
            d[i][j] = (d[i - 1][j] + 1)
                .min(d[i][j - 1] + 1)
                .min(d[i - 1][j - 1] + cost);
            if i > 1 && j > 1 && ra[i - 1] == rb[j - 2] && ra[i - 2] == rb[j - 1] {
                d[i][j] = d[i][j].min(d[i - 2][j - 2] + 1);
            }
        }
    }
    d[ra.len()][rb.len()]
}

/// Bounds search output to roughly 800 tokens.
const SEARCH_BUDGET: usize = 3000;

/// Renders matches as an `ms search_symbol` path, a signature and a one-line doc.
pub fn format_matches(query: &str, matches: &[Match]) -> String {
    if matches.is_empty() {
        return format!(
            "No standard-library match for {query:?}. Try fewer or broader words, or list modules with `ms search_symbol`."
        );
    }
    let mut b = String::new();
    for m in matches {
        b += &format!(
            "{}  ({})\n{}\n",
            m.path,
            m.module,
            indent(m.signature.trim_end_matches('\n'), "  ")
        );
        if !m.doc.is_empty() {
            b += &format!("  # {}\n", m.doc);
        }
    }
    b += &format!(
        "Details: ms search_symbol <path>, e.g. ms search_symbol {}",
        matches[0].path
    );
    clip_text(&b, SEARCH_BUDGET)
}

fn indent(text: &str, prefix: &str) -> String {
    format!("{prefix}{}", text.replace('\n', &format!("\n{prefix}")))
}
