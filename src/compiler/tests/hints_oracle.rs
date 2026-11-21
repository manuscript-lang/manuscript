//! Temporary oracle for src/compiler/src/syntax/hints.c: the pure string helpers of crates/ms-check/src/hints.rs,
//! copied verbatim, behind a line protocol. Deleted with the Rust checker.
//!   hints_oracle gen COUNT SEED   prints COUNT random cases
//!   hints_oracle                  answers the cases on stdin, one line each
#![allow(dead_code)]
use std::collections::HashSet;
use std::io::{BufRead, Write};

#[derive(Clone, Copy)]
struct Pos {
    offset: u32,
    line: u32,
    column: u32,
}
impl Pos {
    fn new(offset: u32, line: u32, column: u32) -> Pos {
        Pos { offset, line, column }
    }
}
struct DiagnosticFix {
    pos: Pos,
    end: Pos,
    replacement: String,
}

// ---- copied from crates/ms-check/src/hints.rs ----

/// Standard modules that were renamed, with the module that replaces each.
const RENAMED_MODULES: &[(&str, &str)] =
    &[("@std/concurrency/flow.ms", "@std/concurrency/resilience.ms")];

const MEMBER_SYNONYMS: &[(&str, &[&str])] = &[
    ("byte_length", &["length"]),
    ("len", &["length", "scalar_length"]),
    ("size", &["length", "scalar_length"]),
    ("count", &["length", "scalar_length"]),
    ("length", &["scalar_length"]),
    ("push", &["append", "add"]),
    ("add", &["append"]),
    ("insert", &["append", "add"]),
    ("delete", &["remove"]),
    ("decode", &["to_string"]),
    ("toString", &["to_string"]),
    ("to_text", &["to_string"]),
    ("includes", &["contains"]),
    ("has", &["contains"]),
    ("indexOf", &["index_of"]),
    ("find_index", &["index_of"]),
    ("reduce", &["fold"]),
    ("each", &["for_each"]),
    ("substring", &["slice", "view"]),
    ("substr", &["slice", "view"]),
    ("charAt", &["scalar_at"]),
    ("char_at", &["scalar_at"]),
    ("sort", &["sorted"]),
    ("trim_left", &["trim_start"]),
    ("trim_right", &["trim_end"]),
    ("to_upper", &["upper"]),
    ("to_lower", &["lower"]),
    ("to_uppercase", &["upper"]),
    ("to_lowercase", &["lower"]),
    ("toUpperCase", &["upper"]),
    ("toLowerCase", &["lower"]),
    ("trimStart", &["trim_start"]),
    ("trimEnd", &["trim_end"]),
    ("to_int", &["parse_int", "truncate_to_int"]),
    ("replace_all", &["replace"]),
    ("replace_n", &["replace", "replace_first"]),
];


/// Returns the candidate most similar to `name`, or "" when none is near
/// enough to be a plausible misspelling.
pub fn closest(name: &str, candidates: &[String]) -> String {
    let mut best = String::new();
    let mut best_key = (0usize, false);
    if name.len() < 3 {
        return best;
    }
    // A third of the name may differ, rounded down from `len + 1`: `--fix` applies the
    // suggestion, and `fail` -> `main` (two of four letters) rewrites a different function.
    // A name that extends or truncates the typed one (`testing` for `test`) keeps every
    // typed letter, so it may differ by a third rounded up.
    let limit = ((name.len() + 1) / 3).min(3);
    let prefix_limit = name.len().div_ceil(3).min(3);
    let lname = name.to_lowercase();
    for candidate in candidates {
        if candidate == name {
            continue;
        }
        let lcandidate = candidate.to_lowercase();
        let d = edit_distance(&lname, &lcandidate);
        // At equal distance a name that extends or truncates the typed one
        // ("testing" for "test") beats an unrelated one.
        let key = (
            d,
            !(lname.starts_with(&lcandidate) || lcandidate.starts_with(&lname)),
        );
        let related = !key.1;
        if d <= if related { prefix_limit } else { limit }
            && (best.is_empty()
                || key < best_key
                || (key == best_key && candidate.as_str() < best.as_str()))
        {
            best = candidate.clone();
            best_key = key;
        }
    }
    best
}

/// Levenshtein distance over scalar values.
pub fn edit_distance(a: &str, b: &str) -> usize {
    let x: Vec<char> = a.chars().collect();
    let y: Vec<char> = b.chars().collect();
    let mut previous: Vec<usize> = (0..=y.len()).collect();
    for i in 1..=x.len() {
        let mut current = vec![0usize; y.len() + 1];
        current[0] = i;
        for j in 1..=y.len() {
            let cost = usize::from(x[i - 1] != y[j - 1]);
            current[j] = (previous[j] + 1)
                .min(current[j - 1] + 1)
                .min(previous[j - 1] + cost);
        }
        previous = current;
    }
    previous[y.len()]
}

/// `; did you mean 'x'?` for a near miss, else "".
pub fn did_you_mean(name: &str, candidates: &[String]) -> String {
    let m = closest(name, candidates);
    if m.is_empty() {
        String::new()
    } else {
        format!("; did you mean '{m}'?")
    }
}

/// Renders at most `limit` sorted names.
pub fn list(names: &[String], limit: usize) -> String {
    let mut names = unique_sorted(names);
    let mut more = "";
    if names.len() > limit {
        more = ", ...";
        names.truncate(limit);
    }
    format!("{}{}", names.join(", "), more)
}

/// Sorted, de-duplicated, non-empty names.
pub fn unique_sorted(names: &[String]) -> Vec<String> {
    let mut seen: HashSet<&str> = HashSet::default();
    let mut out: Vec<String> = Vec::new();
    for name in names {
        if !name.is_empty() && seen.insert(name.as_str()) {
            out.push(name.clone());
        }
    }
    out.sort();
    out
}

/// `Name[T1, T2]` for an arity.
pub fn type_sketch(name: &str, arity: usize) -> String {
    if arity == 0 {
        return format!("{name} with no type arguments");
    }
    let args: Vec<String> = (0..arity)
        .map(|i| format!("T{}", char::from(b'1' + i as u8)))
        .collect();
    format!("{name}[{}]", args.join(", "))
}

pub(crate) fn plural(count: usize, word: &str) -> String {
    if count == 1 {
        word.to_string()
    } else {
        format!("{word}s")
    }
}

/// The module that replaces the renamed standard module `path`.
pub fn renamed_module(path: &str) -> Option<&'static str> {
    RENAMED_MODULES
        .iter()
        .find(|(old, _)| *old == path)
        .map(|(_, new)| *new)
}

/// `fooBar` -> `foo_bar`, or "" when `name` has no uppercase letter.
fn snake_case(name: &str) -> String {
    if !name.bytes().any(|b| b.is_ascii_uppercase()) {
        return String::new();
    }
    let mut out = String::new();
    for c in name.chars() {
        if c.is_ascii_uppercase() {
            out.push('_');
        }
        out.push(c.to_ascii_lowercase());
    }
    out
}

fn synonym_hint(name: &str, available: &[String]) -> String {
    let mut found: Vec<String> = Vec::new();
    let snake = snake_case(name);
    if !snake.is_empty() && available.contains(&snake) {
        found.push(format!("'{snake}'"));
    }
    for (key, candidates) in MEMBER_SYNONYMS {
        if *key != name {
            continue;
        }
        for candidate in *candidates {
            for a in available {
                if a == candidate {
                    found.push(format!("'{candidate}'"));
                }
            }
        }
    }
    if found.is_empty() {
        String::new()
    } else {
        format!("; did you mean {}?", found.join(" or "))
    }
}

/// The builtin type other languages call by this name.
fn type_alias(name: &str) -> Option<&'static str> {
    Some(match name {
        "Integer" | "long" | "Long" | "i64" | "int64" | "number" | "Number" => "Int",
        "double" | "Double" | "f64" | "float64" => "Float",
        "str" | "Str" | "string" | "char" | "Char" | "Text" => "String",
        "boolean" | "Boolean" | "bool" => "Bool",
        "void" | "None" | "NoneType" => "Void",
        "Vec" | "Vector" | "Array" | "ArrayList" | "array" => "List",
        "Dict" | "Dictionary" | "HashMap" | "dict" | "TreeMap" => "Map",
        "HashSet" | "TreeSet" => "Set",
        _ => return None,
    })
}

/// Rewrites the quoted module path `old` that the import clause starting at `from` names, in
/// place, to `new`. `None` unless the quoted path is on the clause's first line.
pub(crate) fn rename_module_path(
    source: &str,
    from: Pos,
    old: &str,
    new: &str,
) -> Option<DiagnosticFix> {
    let start = from.offset as usize;
    let rest = source.get(start..)?;
    let line_len = rest.find('\n').unwrap_or(rest.len());
    let quoted = format!("\"{old}\"");
    let at = rest[..line_len].find(&quoted)?;
    let offset = (start + at) as u32;
    let column = from.column + at as u32;
    Some(DiagnosticFix {
        pos: Pos::new(offset, from.line, column),
        end: Pos::new(
            offset + quoted.len() as u32,
            from.line,
            column + quoted.len() as u32,
        ),
        replacement: format!("\"{new}\""),
    })
}

// ---- the line protocol ----

fn unescape(s: &str) -> String {
    s.replace("\\n", "\n")
}
fn escape(s: &str) -> String {
    s.replace('\n', "\\n")
}
fn items(s: &str) -> Vec<String> {
    if s.is_empty() { Vec::new() } else { s.split(',').map(String::from).collect() }
}

fn answer(line: &str) -> String {
    let f: Vec<&str> = line.split('\t').collect();
    match f[0] {
        "dist" => edit_distance(f[1], f[2]).to_string(),
        "closest" => closest(f[1], &items(f[2])),
        "didyoumean" => did_you_mean(f[1], &items(f[2])),
        "list" => list(&items(f[2]), f[1].parse().unwrap()),
        "unique" => unique_sorted(&items(f[1])).join(","),
        "sketch" => type_sketch(f[1], f[2].parse().unwrap()),
        "plural" => plural(f[1].parse().unwrap(), f[2]),
        "renamed" => renamed_module(f[1]).unwrap_or("-").to_string(),
        "synonym" => synonym_hint(f[1], &items(f[2])),
        "alias" => type_alias(f[1]).unwrap_or("-").to_string(),
        "rename" => {
            let source = unescape(f[1]);
            let from = Pos::new(f[2].parse().unwrap(), f[3].parse().unwrap(), f[4].parse().unwrap());
            match rename_module_path(&source, from, f[5], f[6]) {
                None => "-".to_string(),
                Some(d) => format!(
                    "{} {} {} {} {} {} {}",
                    d.pos.offset, d.pos.line, d.pos.column, d.end.offset, d.end.line, d.end.column, d.replacement
                ),
            }
        }
        other => panic!("unknown op {other}"),
    }
}

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
}

const WORDS: &[&str] = &[
    "count", "length", "append", "add", "remove", "test", "testing", "fail", "fall", "main", "size", "sign", "sum", "lenght",
    "cuont", "sumn", "fooBar", "toString", "to_string", "indexOf", "index_of", "trimStart", "trim_start", "contains", "includes",
    "push", "sorted", "sort", "fold", "reduce", "for_each", "each", "scalar_at", "charAt", "HashMap", "Vec", "Integer", "string",
    "Dictionary", "Number", "", "ab", "abc", "abcd", "abcdef", "Count", "COUNT", "naïve", "naive", "résumé", "lenGth", "x", "iter",
];
const PATHS: &[&str] = &[
    "@std/concurrency/flow.ms", "@std/concurrency/resilience.ms", "@std/bytes.ms", "flow.ms", "", "@std/concurrency/flow.msx",
];

fn mutate(r: &mut Rng, word: &str) -> String {
    let mut c: Vec<char> = word.chars().collect();
    for _ in 0..r.below(3) {
        match r.below(5) {
            0 if !c.is_empty() => { let i = r.below(c.len()); c.remove(i); }
            1 => { let i = r.below(c.len() + 1); c.insert(i, (b'a' + r.below(26) as u8) as char); }
            2 if c.len() > 1 => { let i = r.below(c.len() - 1); c.swap(i, i + 1); }
            3 if !c.is_empty() => { let i = r.below(c.len()); c[i] = (b'a' + r.below(26) as u8) as char; }
            _ => {}
        }
    }
    c.into_iter().collect()
}

fn word(r: &mut Rng) -> String {
    let w = WORDS[r.below(WORDS.len())];
    if r.below(2) == 0 { mutate(r, w) } else { w.to_string() }
}

fn word_list(r: &mut Rng) -> String {
    let n = r.below(9);
    (0..n).map(|_| word(r)).filter(|w| !w.contains(',')).collect::<Vec<_>>().join(",")
}

fn gen(count: usize, seed: u64) {
    let mut r = Rng(seed.max(1));
    let out = std::io::stdout();
    let mut out = out.lock();
    for _ in 0..count {
        let line = match r.below(10) {
            0 => format!("dist\t{}\t{}", word(&mut r), word(&mut r)),
            1 | 2 => format!("closest\t{}\t{}", word(&mut r), word_list(&mut r)),
            3 => format!("didyoumean\t{}\t{}", word(&mut r), word_list(&mut r)),
            4 => format!("list\t{}\t{}", r.below(6), word_list(&mut r)),
            5 => format!("unique\t{}", word_list(&mut r)),
            6 => format!("sketch\t{}\t{}", word(&mut r), r.below(5)),
            7 => {
                if r.below(2) == 0 {
                    format!("plural\t{}\t{}", r.below(3), word(&mut r))
                } else {
                    format!("synonym\t{}\t{}", word(&mut r), word_list(&mut r))
                }
            }
            8 => {
                if r.below(2) == 0 {
                    format!("renamed\t{}", PATHS[r.below(PATHS.len())])
                } else {
                    format!("alias\t{}", word(&mut r))
                }
            }
            _ => {
                let old = PATHS[r.below(PATHS.len())];
                let src = format!("import a from \"{old}\"\\nimport b from \"{}\"", PATHS[r.below(PATHS.len())]);
                let start = if r.below(3) == 0 { 0 } else { 7 + r.below(4) };
                format!("rename\t{src}\t{start}\t{}\t{}\t{old}\t{}", 1 + r.below(3), 1 + start, PATHS[r.below(PATHS.len())])
            }
        };
        writeln!(out, "{line}").unwrap();
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("gen") {
        gen(args[2].parse().unwrap(), args[3].parse().unwrap());
        return;
    }
    let stdin = std::io::stdin();
    let out = std::io::stdout();
    let mut out = out.lock();
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        writeln!(out, "{}", escape(&answer(&line))).unwrap();
    }
}
