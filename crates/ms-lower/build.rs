//! Turns the generated runtime signature table (`rt_symbols.txt`, written by `cargo xtask symbols`)
//! into a sorted table, so lowering looks a symbol up by binary search and a malformed entry fails
//! the build.

use std::fmt::Write as _;
use std::path::PathBuf;

/// A listed function: name, parameters (name and type) and return type.
type Entry = (String, Vec<(String, String)>, String);

/// Splits `list` at its top-level commas (a function-pointer type holds commas).
fn split_params(list: &str) -> Vec<&str> {
    let mut parts = Vec::new();
    let (mut depth, mut start) = (0i32, 0usize);
    let bytes = list.as_bytes();
    for (i, c) in list.char_indices() {
        match c {
            '(' | '[' | '<' => depth += 1,
            ')' | ']' => depth -= 1,
            '>' if i == 0 || bytes[i - 1] != b'-' => depth -= 1,
            ',' if depth == 0 => {
                parts.push(&list[start..i]);
                start = i + 1;
            }
            _ => {}
        }
    }
    parts.push(&list[start..]);
    parts
}

fn main() {
    let table_path = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("rt_symbols.txt");
    println!("cargo:rerun-if-changed={}", table_path.display());
    let text = std::fs::read_to_string(&table_path).expect("read rt_symbols.txt");
    let mut table: Vec<Entry> = Vec::new();
    for (n, line) in text.lines().enumerate() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((name, rest)) = line.split_once('(') else {
            panic!("rt_symbols.txt:{}: not a function entry: {line}", n + 1);
        };
        let Some(close) = rest.rfind(')').filter(|_| !rest.ends_with("->")) else {
            panic!("rt_symbols.txt:{}: unclosed parameter list: {line}", n + 1);
        };
        // The closing parenthesis of the parameters is the last one before a trailing ` -> ret`.
        let close = match rest.rfind(") -> ") {
            Some(at) => at,
            None => close,
        };
        let params = split_params(&rest[..close])
            .into_iter()
            .map(str::trim)
            .filter(|p| !p.is_empty())
            .filter_map(|p| p.split_once(':'))
            .map(|(name, ty)| (name.trim().to_string(), ty.trim().to_string()))
            .collect();
        let ret = rest[close + 1..]
            .trim()
            .strip_prefix("->")
            .map(|r| r.trim().to_string())
            .unwrap_or_default();
        table.push((name.trim().to_string(), params, ret));
    }
    table.sort_by(|a, b| a.0.cmp(&b.0));
    table.dedup_by(|later, first| later.0 == first.0);
    let mut out = String::from("&[\n");
    for (name, params, ret) in &table {
        let params: Vec<String> = params
            .iter()
            .map(|(n, t)| format!("({n:?}, {t:?})"))
            .collect();
        writeln!(out, "    ({name:?}, &[{}], {ret:?}),", params.join(", ")).unwrap();
    }
    out.push_str("]\n");
    let dest = PathBuf::from(std::env::var("OUT_DIR").expect("out dir")).join("rt_symbols.rs");
    std::fs::write(dest, out).expect("write symbol table");
}
