//! Turns the runtime symbol catalogue (`ms-rt/SYMBOLS.md`) into a sorted table, so lowering looks
//! a symbol up by binary search and a malformed catalogue entry fails the build.

use std::fmt::Write as _;
use std::path::PathBuf;

/// A catalogued function: name, parameters (name and type) and return type.
type Entry = (String, Vec<(String, String)>, String);

fn main() {
    let catalogue = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("../ms-rt/SYMBOLS.md");
    println!("cargo:rerun-if-changed={}", catalogue.display());
    let text = std::fs::read_to_string(&catalogue).expect("read SYMBOLS.md");
    let mut table: Vec<Entry> = Vec::new();
    let mut in_block = false;
    for (n, line) in text.lines().enumerate() {
        if line.starts_with("```") {
            in_block = !in_block;
            continue;
        }
        // `name (data)` lines list exported data, which has no signature to marshal against.
        if !in_block || line.is_empty() || line.contains(" (data)") {
            continue;
        }
        let Some((name, rest)) = line.split_once('(') else {
            panic!("SYMBOLS.md:{}: not a function entry: {line}", n + 1);
        };
        let Some(close) = rest.rfind(')') else {
            panic!("SYMBOLS.md:{}: unclosed parameter list: {line}", n + 1);
        };
        let params = rest[..close]
            .split(',')
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
    // The first entry of a name wins, as in a scan of the catalogue.
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
