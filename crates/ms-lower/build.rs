//! Turns the generated runtime signature table (`rt_symbols.txt`, written by `cargo xtask symbols`)
//! into a sorted table, so lowering looks a symbol up by binary search and a malformed entry fails
//! the build.

use std::fmt::Write as _;
use std::path::PathBuf;

/// A listed function: name, parameters (name and type), return type, flag bits, kept
/// parameters, the MIR instruction it is and the domain its failures name (empty when none).
type Entry = (
    String,
    Vec<(String, String)>,
    String,
    u8,
    Vec<String>,
    String,
    String,
);

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

/// Every `.ms` file under `dir`, in a stable order.
fn ms_files(dir: &std::path::Path, out: &mut Vec<PathBuf>) {
    let mut entries: Vec<PathBuf> = std::fs::read_dir(dir)
        .expect("read stdlib dir")
        .map(|e| e.expect("dir entry").path())
        .collect();
    entries.sort();
    for path in entries {
        if path.is_dir() {
            ms_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "ms") {
            out.push(path);
        }
    }
}

/// Writes `status_rows.rs`: the error kind and words of each runtime status, declared in the
/// standard library as `// ms: status <number> <kind> <words>` beside `Error.kind`
/// (`stdlib/core.ms`), and the per-module wording `// ms: words <number> <words>` that applies to
/// every extern the declaring file holds or lists as `// ms: native <symbol>..`. A `-` in the words means the native's own text.
fn status_rows(manifest: &std::path::Path) {
    let root = manifest.join("../../stdlib");
    println!("cargo:rerun-if-changed={}", root.display());
    let mut files = Vec::new();
    ms_files(&root, &mut files);
    let mut rows: Vec<(i64, String, String)> = Vec::new();
    let mut words: Vec<(String, i64, String)> = Vec::new();
    for path in files {
        println!("cargo:rerun-if-changed={}", path.display());
        let text = std::fs::read_to_string(&path).expect("read stdlib file");
        let mut local: Vec<(i64, String)> = Vec::new();
        let mut externs: Vec<String> = Vec::new();
        for line in text.lines() {
            if let Some(rest) = line.strip_prefix("// ms: status ") {
                let mut it = rest.splitn(3, ' ');
                let n = it.next().and_then(|n| n.parse().ok());
                let (Some(n), Some(kind), Some(w)) = (n, it.next(), it.next()) else {
                    panic!("{}: malformed status row: {line}", path.display());
                };
                rows.push((n, kind.to_string(), w.to_string()));
            } else if let Some(rest) = line.strip_prefix("// ms: words ") {
                let Some((n, w)) = rest.split_once(' ') else {
                    panic!("{}: malformed words row: {line}", path.display());
                };
                let n = n.parse().expect("status number");
                local.push((n, w.to_string()));
            } else if let Some(rest) = line.strip_prefix("// ms: native ") {
                // Natives lowering binds to host-interface methods, with no `extern fn` of their own.
                externs.extend(rest.split(' ').map(str::to_string));
            } else if let Some(rest) = line.strip_prefix("export extern fn ") {
                externs.extend(rest.split('(').next().map(str::to_string));
            } else if let Some(rest) = line.strip_prefix("extern fn ") {
                externs.extend(rest.split('(').next().map(str::to_string));
            }
        }
        for sym in &externs {
            for (n, w) in &local {
                words.push((sym.clone(), *n, w.clone()));
            }
        }
    }
    rows.sort();
    words.sort();
    let mut out = String::from("static STATUS_ROWS: &[(i64, &str, &str)] = &[\n");
    for (n, k, w) in &rows {
        writeln!(out, "    ({n}, {k:?}, {w:?}),").unwrap();
    }
    out.push_str("];\nstatic STATUS_WORDS: &[(&str, i64, &str)] = &[\n");
    for (sym, n, w) in &words {
        writeln!(out, "    ({sym:?}, {n}, {w:?}),").unwrap();
    }
    out.push_str("];\n");
    let dest = PathBuf::from(std::env::var("OUT_DIR").expect("out dir")).join("status_rows.rs");
    std::fs::write(dest, out).expect("write status rows");
}

fn main() {
    status_rows(&PathBuf::from(
        std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"),
    ));
    let table_path = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("rt_symbols.txt");
    println!("cargo:rerun-if-changed={}", table_path.display());
    let text = std::fs::read_to_string(&table_path).expect("read rt_symbols.txt");
    let mut table: Vec<Entry> = Vec::new();
    for (n, line) in text.lines().enumerate() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        // Declared flags trail the signature: ` @handle @leaf @pure @fresh`.
        let (line, flags) = match line.split_once(" @") {
            Some((sig, flags)) => (sig, flags.split(" @").collect::<Vec<_>>()),
            None => (line, Vec::new()),
        };
        let bit = |f: &str| -> u8 { u8::from(flags.contains(&f)) };
        // `@keeps:name` marks the parameter `name` as a function value the runtime keeps.
        let kept: Vec<&str> = flags
            .iter()
            .filter_map(|f| f.strip_prefix("keeps:"))
            .collect();
        // `@op=<mnemonic>`: the function is exactly that MIR instruction on its arguments.
        let op = flags
            .iter()
            .find_map(|f| f.strip_prefix("op="))
            .unwrap_or("")
            .to_string();
        let domain = flags
            .iter()
            .find_map(|f| f.strip_prefix("domain="))
            .unwrap_or("")
            .to_string();
        let named: Vec<&str> = flags
            .iter()
            .filter_map(|f| {
                f.strip_prefix("keeps:")
                    .or_else(|| f.strip_prefix("takes:"))
            })
            .collect();
        // A function that writes through a `*mut` argument (an out slot) does not only read
        // memory, whatever else it is declared: `memory(read)` would let LLVM drop the call.
        let pure = bit("pure") & u8::from(!line.contains("*mut"));
        let flags = bit("leaf")
            | pure << 1
            | bit("fresh") << 2
            | bit("handle") << 3
            | bit("spawns") << 4
            | bit("takes_self") << 5;
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
        let params: Vec<(String, String)> = split_params(&rest[..close])
            .into_iter()
            .map(str::trim)
            .filter(|p| !p.is_empty())
            .filter_map(|p| p.split_once(':'))
            .map(|(name, ty)| (name.trim().to_string(), ty.trim().to_string()))
            .collect();
        // A `keeps:`/`takes:` flag names one of the function's parameters.
        let param_names: Vec<&str> = params
            .iter()
            .map(|(p, _)| p.trim_start_matches("handle ").trim())
            .collect();
        for named in &named {
            if !param_names.contains(named) {
                panic!("rt_symbols.txt:{}: no parameter `{named}`: {line}", n + 1);
            }
        }
        let kept = kept.into_iter().map(str::to_string).collect();
        let ret = rest[close + 1..]
            .trim()
            .strip_prefix("->")
            .map(|r| r.trim().to_string())
            .unwrap_or_default();
        table.push((
            name.trim().to_string(),
            params,
            ret,
            flags,
            kept,
            op,
            domain,
        ));
    }
    table.sort_by(|a, b| a.0.cmp(&b.0));
    table.dedup_by(|later, first| later.0 == first.0);
    let mut out = String::from("&[\n");
    for (name, params, ret, flags, kept, op, domain) in &table {
        let params: Vec<String> = params
            .iter()
            .map(|(n, t)| {
                // A `handle` prefix on the name marks a runtime handle object parameter.
                let (n, handle) = match n.strip_prefix("handle ") {
                    Some(n) => (n.trim(), true),
                    None => (n.as_str(), false),
                };
                let closure = kept.iter().any(|k| k == n);
                format!("({n:?}, {t:?}, {handle}, {closure})")
            })
            .collect();
        writeln!(
            out,
            "    ({name:?}, &[{}], {ret:?}, {flags}, {op:?}, {domain:?}),",
            params.join(", ")
        )
        .unwrap();
    }
    out.push_str("]\n");
    let dest = PathBuf::from(std::env::var("OUT_DIR").expect("out dir")).join("rt_symbols.rs");
    std::fs::write(dest, out).expect("write symbol table");
}
