//! Repository build steps, run as `cargo xtask <step>`.
//!
//! `runtime` builds `ms-native` (the runtime plus every `ms-std-*` crate) once and leaves the stripped
//! archive at `target/ms-native/libms_native.a`, where `ms-cli`'s build script embeds it.
//! `runtime --alloc-profile` also builds `libms_native_allocs.a`, the same runtime with allocation
//! sampling for `ms profile --allocs`; release packaging asks for it, pull request CI does not.
//! `runtime --sched-stress` builds `libms_native_stress.a`, the runtime with the scheduler stress mode,
//! which only `make stress-sched` embeds (in a separate `ms`).

use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

fn main() -> ExitCode {
    match std::env::args().nth(1).as_deref() {
        Some("runtime") => {
            let flag = std::env::args().nth(2);
            match runtime(
                flag.as_deref() == Some("--alloc-profile"),
                flag.as_deref() == Some("--sched-stress"),
            ) {
                Ok(archive) => {
                    println!("{}", archive.display());
                    ExitCode::SUCCESS
                }
                Err(message) => {
                    eprintln!("xtask runtime: {message}");
                    ExitCode::FAILURE
                }
            }
        }
        Some("symbols") => {
            let check = std::env::args().nth(2).as_deref() == Some("--check");
            match symbols(check) {
                Ok(message) => {
                    println!("{message}");
                    ExitCode::SUCCESS
                }
                Err(message) => {
                    eprintln!("xtask symbols: {message}");
                    ExitCode::FAILURE
                }
            }
        }
        _ => {
            eprintln!(
                "usage: cargo xtask runtime [--alloc-profile | --sched-stress] | cargo xtask symbols [--check]"
            );
            ExitCode::from(2)
        }
    }
}

/// Regenerates `crates/ms-lower/rt_symbols.txt`, the C signature of every exported runtime function
/// that lowering marshals calls from (`ms-lower/build.rs` turns it into a lookup table). `--check`
/// compares instead of writing.
///
/// Two sources, so no signature is written by hand: the tests that `ms_rt::native!` generates for
/// each shim (they record the raw ABI types with `type_name`, so a type change shows up here), and a
/// scan of the plain `extern "C"` functions, whose signatures are already ABI types.
fn symbols(check: bool) -> Result<String, String> {
    let manifest = std::env::var_os("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")));
    let root = manifest.join("../..");
    let recorded = root.join("target/ms-native/signatures.txt");
    std::fs::create_dir_all(recorded.parent().expect("parent")).map_err(|e| e.to_string())?;
    let _ = std::fs::remove_file(&recorded);
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    // Only the runtime crates: `ms-cli`'s build script insists on a fresh runtime archive, which
    // would need the table this step writes.
    let mut crates = vec!["ms-rt".to_string()];
    for entry in std::fs::read_dir(root.join("crates")).map_err(|e| e.to_string())? {
        let name = entry
            .map_err(|e| e.to_string())?
            .file_name()
            .to_string_lossy()
            .into_owned();
        if name.starts_with("ms-std-") {
            crates.push(name);
        }
    }
    crates.sort();
    let status = Command::new(cargo)
        .current_dir(&root)
        .env("MS_SIG_OUT", &recorded)
        .args(["test", "--lib", "--locked"])
        .args(crates.iter().flat_map(|c| ["-p", c.as_str()]))
        .args(["--", "ms_signature"])
        .status()
        .map_err(|e| format!("cargo test: {e}"))?;
    if !status.success() {
        return Err("collecting the native signatures failed".into());
    }
    let mut table = std::collections::BTreeMap::new();
    let text =
        std::fs::read_to_string(&recorded).map_err(|e| format!("{}: {e}", recorded.display()))?;
    for line in text.lines().filter(|l| !l.is_empty()) {
        let name = line.split('(').next().unwrap_or(line).to_string();
        if let Some(old) = table.insert(name.clone(), line.to_string())
            && old != line
        {
            return Err(format!(
                "{name} is declared twice with different signatures"
            ));
        }
    }
    let mut files = Vec::new();
    for entry in std::fs::read_dir(root.join("crates")).map_err(|e| e.to_string())? {
        let dir = entry.map_err(|e| e.to_string())?.path();
        let is_runtime = dir
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| n == "ms-rt" || n.starts_with("ms-std-"));
        if is_runtime {
            rust_files(&dir.join("src"), &mut files);
        }
    }
    files.sort();
    let mut flags: std::collections::BTreeMap<String, Vec<String>> = Default::default();
    // `//! ms: domain <words>`: how the failures of the file's functions name their domain.
    let mut file_domains: Vec<(String, String)> = Vec::new();
    for file in files {
        let source =
            std::fs::read_to_string(&file).map_err(|e| format!("{}: {e}", file.display()))?;
        if let Some(domain) = source
            .lines()
            .find_map(|l| l.trim().strip_prefix("//! ms: domain "))
        {
            file_domains.push((source.clone(), domain.trim().to_string()));
        }
        for (name, found) in scan_flags(&source).map_err(|e| format!("{}: {e}", file.display()))? {
            flags.entry(name).or_default().extend(found);
        }
        for (name, line) in scan_exports(&source) {
            if let Some(old) = table.insert(name.clone(), line.clone())
                && old != line
            {
                return Err(format!(
                    "{name} has two signatures: `{old}` and `{line}` ({})",
                    file.display()
                ));
            }
        }
    }
    for (name, line, found) in header_signatures(&root)? {
        if let Some(old) = table.insert(name.clone(), line.clone())
            && old != line
        {
            return Err(format!(
                "{name} has two signatures: `{old}` (Rust) and `{line}` (a runtime/include/ms_rt header)"
            ));
        }
        flags.entry(name).or_default().extend(found);
    }
    let mut out = String::from(
        "# Generated by `cargo xtask symbols`; do not edit. One line per exported runtime function:\n\
         # `name(param: type, ..) -> ret`, the C signature lowering marshals runtime calls from, then the\n\
         # flags the source declares with a `// ms: leaf pure fresh` comment above the function:\n\
         # `@leaf` never reaches a cancellation point, `@pure` only reads memory and cannot fault,\n\
         # `@fresh` returns a value that borrows none of its arguments, `@keeps:<param>` stores that\n\
         # function value, `@takes:<param>` takes ownership of that value, `@spawns` starts a task\n\
         # running program code, `@takes_self` has a `<name>_take` twin that reuses its first\n\
         # argument when it dies at the call, `@op=<mnemonic>` is exactly that MIR instruction on\n\
         # its arguments, `@domain=<words>` names its failures' domain, and `@view_of=<sym>`,\n\
         # `@shared_view_of=<sym>`, `@first_of=<sym>`, `@iter_of=<sym>` declare the function as the\n\
         # borrowing twin of `<sym>` (a lent result, the first element, a one-at-a-time walk).\n",
    );
    for name in table.keys() {
        let declared = flags
            .get(name)
            .is_some_and(|f| f.iter().any(|f| f.starts_with("domain=")));
        if declared {
            continue;
        }
        if let Some((_, domain)) = file_domains.iter().find(|(s, _)| defines(s, name)) {
            flags
                .entry(name.clone())
                .or_default()
                .push(format!("domain={domain}"));
        }
    }
    for (name, found) in &flags {
        if !table.contains_key(name) {
            return Err(format!(
                "`// ms:` flags on {name}, which is not a runtime function"
            ));
        }
        let _ = found;
    }
    for (name, line) in &table {
        out.push_str(line);
        if let Some(found) = flags.get(name) {
            let mut found = found.clone();
            found.sort();
            found.dedup();
            for flag in found {
                out.push_str(" @");
                out.push_str(&flag);
            }
        }
        out.push('\n');
    }
    check_c_abi(&root, &table)?;
    let path = root.join("crates/ms-lower/rt_symbols.txt");
    if check {
        let have = std::fs::read_to_string(&path).unwrap_or_default();
        if have != out {
            return Err(format!(
                "{} is stale; run `cargo xtask symbols`",
                path.display()
            ));
        }
        return Ok(format!(
            "{} is current ({} symbols)",
            path.display(),
            table.len()
        ));
    }
    std::fs::write(&path, out).map_err(|e| e.to_string())?;
    Ok(format!(
        "wrote {} ({} symbols)",
        path.display(),
        table.len()
    ))
}

/// The signatures that `runtime/include/ms_rt/<module>.h` declares for C-defined natives, so a native can
/// exist only in C. A `/* ms-sig: name(param: type, ..) -> ret @flag .. */` comment above a prototype
/// is the table line lowering reads (same text as the Rust-derived line); `check_c_abi` compares its
/// kinds with the C prototype, so the two cannot drift. A `/* ms: domain <words> */` comment names the
/// domain of every function of the header that has no `@domain=` flag of its own.
fn header_signatures(root: &Path) -> Result<Vec<(String, String, Vec<String>)>, String> {
    let dir = root.join("runtime/include/ms_rt");
    let mut found = Vec::new();
    let mut headers: Vec<PathBuf> = std::fs::read_dir(&dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "h"))
        .collect();
    headers.sort();
    for header in headers {
        let text =
            std::fs::read_to_string(&header).map_err(|e| format!("{}: {e}", header.display()))?;
        found.extend(parse_header_signatures(&text));
    }
    Ok(found)
}

/// The `ms-sig` lines of one header as `(name, signature, flags)`; see `header_signatures`.
fn parse_header_signatures(text: &str) -> Vec<(String, String, Vec<String>)> {
    let domain = text.lines().find_map(|l| {
        l.trim()
            .strip_prefix("/* ms: domain ")
            .and_then(|r| r.strip_suffix("*/"))
            .map(|d| d.trim().to_string())
    });
    let mut found = Vec::new();
    for line in text.lines() {
        let Some(sig) = line
            .trim()
            .strip_prefix("/* ms-sig: ")
            .and_then(|r| r.strip_suffix("*/"))
        else {
            continue;
        };
        let mut parts = sig.trim().split(" @");
        let base = parts.next().unwrap_or_default().trim().to_string();
        let mut flags: Vec<String> = parts.map(|f| f.trim().to_string()).collect();
        let name = base.split('(').next().unwrap_or_default().to_string();
        if !flags.iter().any(|f| f.starts_with("domain="))
            && let Some(domain) = &domain
        {
            flags.push(format!("domain={domain}"));
        }
        found.push((name, base, flags));
    }
    found
}

/// The scalar kind of a Rust parameter type or a C declaration (`ptr` for any pointer), so the two spellings compare.
fn abi_kind(text: &str) -> String {
    let text = text.trim();
    if text.contains('*') {
        return "ptr".into();
    }
    // `repr(transparent)` ABI wrappers: the error slot is a pointer, the has-raw flag a byte.
    match text.rsplit(':').next().map_or(text, str::trim) {
        "ErrSlot" => return "ptr".into(),
        "HasRaw" => return "u8".into(),
        _ => {}
    }
    let word = |w: &str| {
        text.split(|c: char| !c.is_alphanumeric() && c != '_')
            .any(|t| t == w)
    };
    for (rust, c) in [
        ("i64", "int64_t"),
        ("u64", "uint64_t"),
        ("i32", "int32_t"),
        ("u32", "uint32_t"),
        ("u8", "uint8_t"),
        ("usize", "size_t"),
        ("f64", "double"),
        ("bool", "bool"),
    ] {
        if word(rust) || word(c) {
            return rust.into();
        }
    }
    text.into()
}

/// `runtime/symbols/<module>.txt` lists the symbols `runtime/include/ms_rt/<module>.h` declares and C defines.
/// Every listed symbol has a prototype in its module's header with the parameters and result of its recorded
/// signature, and every function the header declares is listed (the two cannot drift).
fn check_c_abi(
    root: &Path,
    table: &std::collections::BTreeMap<String, String>,
) -> Result<(), String> {
    let read_dir = |dir: &str, ext: &str| -> Result<Vec<PathBuf>, String> {
        let mut found: Vec<PathBuf> = std::fs::read_dir(root.join(dir))
            .map_err(|e| format!("{dir}: {e}"))?
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|e| e == ext))
            .collect();
        found.sort();
        Ok(found)
    };
    let mut seen = std::collections::BTreeSet::new();
    for list in read_dir("runtime/symbols", "txt")? {
        let module = list.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        let listed = std::fs::read_to_string(&list).map_err(|e| e.to_string())?;
        let listed: std::collections::BTreeSet<&str> = listed
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .collect();
        let header_path = root.join(format!("runtime/include/ms_rt/{module}.h"));
        let header = std::fs::read_to_string(&header_path)
            .map_err(|e| format!("{}: {e}", header_path.display()))?;
        let declared = c_prototypes(&header);
        for name in &listed {
            if !seen.insert(name.to_string()) {
                return Err(format!("{name} is listed in two runtime/symbols files"));
            }
            // `ms_sys_*` is the runtime's own door to the OS (ms_rt/sys.h): not natives, so no recorded signature.
            if name.starts_with("ms_sys_") {
                continue;
            }
            let Some((params, ret)) = declared.get(*name) else {
                return Err(format!(
                    "{name} is in runtime/symbols/{module}.txt but not declared in ms_rt/{module}.h"
                ));
            };
            let Some(line) = table.get(*name) else {
                return Err(format!(
                    "{name} is in runtime/symbols/{module}.txt but not a runtime function"
                ));
            };
            let (rust_params, rust_ret) = line
                .split_once('(')
                .and_then(|(_, r)| r.rsplit_once(')'))
                .map(|(p, r)| {
                    (
                        p,
                        r.trim().strip_prefix("->").map(str::trim).unwrap_or("()"),
                    )
                })
                .ok_or_else(|| format!("{name}: unreadable signature `{line}`"))?;
            let rust_params: Vec<String> = rust_params
                .split(',')
                .filter(|p| !p.trim().is_empty())
                .map(|p| abi_kind(p.split_once(':').map_or(p, |(_, t)| t)))
                .collect();
            let rust_ret = if rust_ret == "()" {
                "void".to_string()
            } else {
                abi_kind(rust_ret)
            };
            if &rust_params != params || &rust_ret != ret {
                return Err(format!(
                    "{name}: ms_rt/{module}.h says ({}) -> {ret}, the runtime signature is ({}) -> {rust_ret}",
                    params.join(", "),
                    rust_params.join(", ")
                ));
            }
        }
        if let Some(name) = declared.keys().find(|n| !listed.contains(n.as_str())) {
            return Err(format!(
                "{name} is declared in ms_rt/{module}.h but not in runtime/symbols/{module}.txt"
            ));
        }
    }
    for header in read_dir("runtime/include/ms_rt", "h")? {
        let module = header.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        if !["base", "safe"].contains(&module)
            && !root.join(format!("runtime/symbols/{module}.txt")).exists()
        {
            return Err(format!(
                "ms_rt/{module}.h has no runtime/symbols/{module}.txt"
            ));
        }
    }
    Ok(())
}

/// The `msrt_*`/`msstd_*` prototypes of a module header as `name -> (parameter kinds, result kind)`.
fn c_prototypes(header: &str) -> std::collections::BTreeMap<String, (Vec<String>, String)> {
    let mut declared = std::collections::BTreeMap::new();
    for line in header.lines() {
        let Some((head, rest)) = line.split_once('(') else {
            continue;
        };
        let Some((params, tail)) = rest.split_once(')') else {
            continue;
        };
        let Some((ret, name)) = head
            .trim()
            .rsplit_once(|c: char| c.is_whitespace() || c == '*')
        else {
            continue;
        };
        if tail.trim() != ";" || !name.starts_with("msrt_") && !name.starts_with("msstd_") {
            continue;
        }
        let ret = if head.contains('*') {
            "ptr".to_string()
        } else {
            abi_kind(ret)
        };
        let params: Vec<String> = params
            .split(',')
            .map(str::trim)
            .filter(|p| !p.is_empty() && *p != "void")
            .map(abi_kind)
            .collect();
        declared.insert(name.to_string(), (params, ret));
    }
    declared
}

fn rust_files(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            rust_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "rs") {
            out.push(path);
        }
    }
}

/// The flags that declare a runtime function as the twin of another (`view_of=<sym>`): the entry
/// lowering calls instead of `<sym>` when the result is only read in place. See
/// `crates/ms-lower/src/rtcall.rs` (`Twin`).
const TWIN_FLAGS: [&str; 4] = ["view_of=", "shared_view_of=", "first_of=", "iter_of="];

/// The `// ms: flag ..` comments of `source`: each names the flags of the runtime function whose
/// name is the first `msrt_*`/`msstd_*` identifier on the next code line. The flags are the
/// declared ABI facts lowering and the optimizer read (`leaf`, `pure`, `fresh`, `borrows`, `keeps:<param>`
/// for a function value the runtime stores and drops itself, `takes:<param>` for a value
/// argument the runtime takes ownership of, `domain=<word>` for how its failures
/// name their domain when it differs from the file's `//! ms: domain`, `spawns` for a function that starts a
/// task running code of the program, `borrows` for a function whose result may point into the storage of an argument passed by value (the bytes of an inline `String`), so the backends keep that argument's slot for the whole function, `takes_self` for a function with a `<name>_take` twin that reuses its first argument when it dies at the call, and `op=<mnemonic>` for a function
/// that is exactly one MIR instruction on its arguments); an unknown flag or a
/// marker with no function after it is an error.
fn scan_flags(source: &str) -> Result<Vec<(String, Vec<String>)>, String> {
    let mut found = Vec::new();
    let mut pending: Option<Vec<String>> = None;
    for (n, line) in source.lines().enumerate() {
        let t = line.trim();
        if let Some(list) = t.strip_prefix("// ms:") {
            let list: Vec<String> = list.split_whitespace().map(str::to_string).collect();
            if let Some(bad) = list.iter().find(|f| {
                ![
                    "leaf",
                    "pure",
                    "fresh",
                    "borrows",
                    "spawns",
                    "takes_self",
                    "retains",
                ]
                .contains(&f.as_str())
                    && !f.starts_with("keeps:")
                    && !f.starts_with("takes:")
                    && !f.starts_with("op=")
                    && !f.starts_with("domain=")
                    && !TWIN_FLAGS.iter().any(|t| f.starts_with(t))
            }) {
                return Err(format!("line {}: unknown flag `{bad}`", n + 1));
            }
            pending = Some(list);
            continue;
        }
        let Some(flags) = pending.take() else {
            continue;
        };
        if t.is_empty() || t.starts_with("//") || t.starts_with("#[") {
            pending = Some(flags);
            continue;
        }
        let name = t
            .split(|c: char| !(c.is_alphanumeric() || c == '_'))
            .find(|w| w.starts_with("msrt_") || w.starts_with("msstd_"))
            .ok_or_else(|| {
                format!(
                    "line {}: `// ms:` is not followed by a runtime function",
                    n + 1
                )
            })?;
        found.push((name.to_string(), flags));
    }
    Ok(found)
}

/// Whether `source` defines the runtime function `name`: by hand (`fn name(`) or through a
/// shim macro row (`name => ..`, `macro!(name, ..)`).
fn defines(source: &str, name: &str) -> bool {
    source.lines().any(|l| {
        let t = l.trim();
        t.strip_prefix(name)
            .is_some_and(|r| r.trim_start().starts_with("=>"))
            || [
                format!("fn {name}("),
                format!("fn {name}<"),
                format!("!({name},"),
            ]
            .iter()
            .any(|p| t.contains(p.as_str()))
    })
}

/// The `pub extern "C" fn msrt_*`/`msstd_*` functions written by hand in `source`, as
/// `(name, "name(params) -> ret")` with module paths dropped from the types.
fn scan_exports(source: &str) -> Vec<(String, String)> {
    let mut found = Vec::new();
    let code: String = source
        .lines()
        .filter(|l| !l.trim_start().starts_with("//"))
        .collect::<Vec<_>>()
        .join("\n");
    let mut rest = code.as_str();
    while let Some(at) = rest.find("extern \"C") {
        rest = &rest[at + 1..];
        let Some(after) = rest.split_once("fn ").map(|(_, a)| a) else {
            break;
        };
        // `extern "C" fn msrt_x(` only: skip function pointer types and extern blocks.
        let head = &rest[..rest.len() - after.len()];
        if head.len() > 24 || !head.starts_with("xtern \"C") {
            continue;
        }
        let name: String = after
            .chars()
            .take_while(|c| c.is_alphanumeric() || *c == '_')
            .collect();
        if !(name.starts_with("msrt_") || name.starts_with("msstd_")) {
            continue;
        }
        let Some(open) = after.find('(') else {
            continue;
        };
        let mut depth = 0usize;
        let mut close = None;
        for (i, c) in after[open..].char_indices() {
            match c {
                '(' | '[' | '<' => depth += 1,
                ')' | ']' => depth -= 1,
                '>' if !after[open..][..i].ends_with('-') => depth -= 1,
                _ => {}
            }
            if depth == 0 {
                close = Some(open + i);
                break;
            }
        }
        let Some(close) = close else { continue };
        let params = split_params(&after[open + 1..close]);
        let tail = &after[close + 1..];
        let end = tail.find(['{', ';']).unwrap_or(tail.len());
        let ret = tail[..end]
            .trim()
            .strip_prefix("->")
            .map(|r| strip_paths(&squash(r)));
        let mut line = format!("{name}({})", params.join(", "));
        if let Some(ret) = ret {
            line.push_str(" -> ");
            line.push_str(&ret);
        }
        found.push((name, line));
    }
    found
}

/// Splits a parameter list at its top-level commas and normalizes each `name: type`.
fn split_params(list: &str) -> Vec<String> {
    let mut params = Vec::new();
    let (mut depth, mut start) = (0i32, 0usize);
    let bytes = list.as_bytes();
    for (i, c) in list.char_indices() {
        match c {
            '(' | '[' | '<' => depth += 1,
            ')' | ']' => depth -= 1,
            '>' if i == 0 || bytes[i - 1] != b'-' => depth -= 1,
            ',' if depth == 0 => {
                params.push(&list[start..i]);
                start = i + 1;
            }
            _ => {}
        }
    }
    params.push(&list[start..]);
    params
        .into_iter()
        .map(|p| strip_paths(&squash(p)))
        .map(|p| p.strip_prefix('_').map(str::to_string).unwrap_or(p))
        .filter(|p| !p.is_empty())
        .collect()
}

fn squash(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// `*const ms_rt_abi::StrVal` as `*const StrVal`: drops every `path::` prefix.
fn strip_paths(ty: &str) -> String {
    let mut out = String::new();
    let mut word = String::new();
    let mut chars = ty.chars().peekable();
    while let Some(c) = chars.next() {
        if c.is_alphanumeric() || c == '_' {
            word.push(c);
        } else if c == ':' && chars.peek() == Some(&':') {
            chars.next();
            word.clear();
        } else {
            out.push_str(&word);
            word.clear();
            out.push(c);
        }
    }
    out.push_str(&word);
    out
}

/// Builds `ms-native` in release mode, whatever the profile of `ms` itself, and returns the archive.
/// On Linux it also leaves `libms_native_musl.a` beside it, the runtime of `ms build --static`.
fn runtime(alloc_profile: bool, sched_stress: bool) -> Result<PathBuf, String> {
    // Cargo can reuse this executable from another checkout when target directories are shared.
    // Its runtime environment names the active package; the compiled path may name the old one.
    let manifest = std::env::var_os("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")));
    let root = manifest.join("../..");
    let out = root.join("target/ms-native");
    let target = out.join("build");
    // Linux programs link the system glibc (and `--static` programs musl) and Windows programs
    // mingw-w64 (gnullvm), all with the bundled lld, so the runtime is built for that target.
    // `ring`'s C sources need a C compiler (llvm-mingw's clang on Windows, a musl-targeting one for
    // `--static`): building the runtime needs one, using `ms` does not.
    let arch = std::env::consts::ARCH;
    let triple = match std::env::consts::OS {
        "linux" => Some(format!("{arch}-unknown-linux-gnu")),
        "windows" => Some(format!("{arch}-pc-windows-gnullvm")),
        _ => None,
    };
    // The archives are independent builds in their own target directories (cargo locks a target
    // directory, so a shared one serialises them), so they build side by side: the gnu, musl,
    // allocation-profiling and stress runtimes finish in about the time of the slowest.
    let mut jobs: Vec<(PathBuf, Option<String>, &str, &str)> =
        vec![(target.clone(), triple.clone(), "libms_native.a", "entry")];
    if alloc_profile {
        // The feature changes the runtime, so sharing a directory would rebuild it whenever the
        // two archives alternate.
        jobs.push((
            out.join("build-allocs"),
            triple.clone(),
            "libms_native_allocs.a",
            "entry,alloc-profile",
        ));
    }
    if sched_stress {
        // The scheduler stress mode, for `make stress-sched`; never part of a shipped `ms`.
        jobs.push((
            out.join("build-stress"),
            triple.clone(),
            "libms_native_stress.a",
            "entry,sched-stress",
        ));
    }
    if std::env::consts::OS == "linux" {
        jobs.push((
            out.join("build-musl"),
            Some(format!("{arch}-unknown-linux-musl")),
            "libms_native_musl.a",
            "entry",
        ));
    }
    let mut built = std::thread::scope(|scope| {
        let handles: Vec<_> = jobs
            .iter()
            .map(|(dir, triple, name, features)| {
                let (root, out) = (&root, &out);
                scope
                    .spawn(move || build_archive(root, out, dir, triple.as_deref(), name, features))
            })
            .collect();
        handles
            .into_iter()
            .map(|h| {
                h.join()
                    .unwrap_or_else(|_| Err("archive build panicked".into()))
            })
            .collect::<Vec<_>>()
    });
    let archive = built.remove(0)?;
    built.into_iter().collect::<Result<Vec<_>, _>>()?;
    Ok(archive)
}

/// Builds `ms-native` for `triple` (the host when `None`) and copies its stripped archive to `out/name`.
fn build_archive(
    root: &Path,
    out: &Path,
    target: &Path,
    triple: Option<&str>,
    name: &str,
    features: &str,
) -> Result<PathBuf, String> {
    let arch = std::env::consts::ARCH;
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    let mut command = Command::new(cargo);
    command
        .args([
            "build",
            "--release",
            "--locked",
            "-p",
            "ms-native",
            "--features",
            features,
            "--manifest-path",
        ])
        .arg(root.join("Cargo.toml"))
        .env("CARGO_TARGET_DIR", target)
        // `ms-rt`'s build script compiles out the Rust definition of every symbol in `runtime/symbols/<module>.txt`.
        .env("MS_C_RUNTIME", "1")
        // The runtime ships without debug info; symbol names are enough for the profiler.
        .env("CARGO_PROFILE_RELEASE_DEBUG", "0")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .env_remove("RUSTFLAGS");
    let plan = plan_c_runtime(root, triple)?;
    if plan.has_std_source(root, "crypto.c") {
        // `ms-native` then leaves the Rust `ms-std-crypto` out: `runtime/std/crypto*.c` define every `msstd_crypto_*`.
        command.env("MS_C_CRYPTO", "1");
    }
    if plan.has_reactor(root) {
        // `ms-rt` then leaves its mio poller out; `add_c_runtime` supplies `runtime/io` and libuv.
        command.env("MS_C_REACTOR", "1");
    }
    if let Some(triple) = triple {
        // The glibc target builds with the host's C compiler.
        if !triple.ends_with("linux-gnu") {
            let cc = format!("CC_{}", triple.replace('-', "_"));
            if std::env::var_os(&cc).is_none() {
                command.env(cc, c_compiler(root, triple, arch));
            }
        }
        command.args(["--target", triple]);
    }
    let status = command.status().map_err(|e| format!("run cargo: {e}"))?;
    if !status.success() {
        return Err(format!("building {name} failed"));
    }
    let release = match triple {
        Some(triple) => target.join(triple).join("release"),
        None => target.join("release"),
    };
    let built = release.join("libms_native.a");
    let archive = out.join(name);
    std::fs::copy(&built, &archive).map_err(|e| format!("copy {}: {e}", built.display()))?;
    add_c_runtime(root, target, triple, &plan, &archive)?;
    strip_debug(&archive);
    Ok(archive)
}

/// What `add_c_runtime` compiles and folds into one runtime archive: the C sources for the target, the flags
/// that find the libraries' headers, and the static archives of every library those sources include.
struct CRuntime {
    sources: Vec<PathBuf>,
    cflags: Vec<String>,
    /// Static archives of the libraries the sources use, to fold into the runtime archive.
    libraries: Vec<PathBuf>,
}

impl CRuntime {
    /// Whether `runtime/std/<name>` is part of the archive.
    fn has_std_source(&self, root: &Path, name: &str) -> bool {
        let wanted = root.join("runtime/std").join(name);
        self.sources.contains(&wanted)
    }

    /// Whether the libuv reactor (`runtime/io`) is part of the archive; `ms-rt` then leaves its mio poller out.
    fn has_reactor(&self, root: &Path) -> bool {
        let io = root.join("runtime/io");
        self.sources.iter().any(|s| s.starts_with(&io))
    }
}

/// The library names (as `libs.sh` knows them) whose headers `source` includes, directly or through a header
/// of its own folder.
fn libraries_of(source: &Path) -> Vec<&'static str> {
    const HEADERS: [(&str, &[&str]); 6] = [
        ("<uv.h>", &["uv"]),
        ("<llhttp.h>", &["llhttp"]),
        ("<nghttp2/", &["nghttp2"]),
        ("<openssl/", &["ssl", "crypto"]),
        ("<pcre2.h>", &["pcre2"]),
        ("<zlib.h>", &["z"]),
    ];
    let mut text = std::fs::read_to_string(source).unwrap_or_default();
    let local: Vec<String> = text
        .lines()
        .filter_map(|l| l.trim().strip_prefix("#include \""))
        .filter_map(|l| l.split('"').next())
        .map(str::to_string)
        .collect();
    for header in local {
        if let Some(dir) = source.parent() {
            text.push_str(&std::fs::read_to_string(dir.join(header)).unwrap_or_default());
        }
    }
    let mut found = Vec::new();
    for (include, names) in HEADERS {
        if text.contains(&format!("#include {include}")) {
            found.extend_from_slice(names);
        }
    }
    found
}

/// The C compiler for the musl runtime: musl's own headers decide how libuv and OpenSSL compile (`musl-tools`).
fn musl_compiler() -> PathBuf {
    std::env::var_os("MS_MUSL_CC").map_or_else(|| PathBuf::from("musl-gcc"), PathBuf::from)
}

/// Runs `libs.sh` (the one place that names library paths) for `triple`. The musl archive takes pinned builds
/// made with the musl compiler (system packages are glibc's); the others take the system packages.
fn libs_sh(root: &Path, triple: Option<&str>, args: &[&str]) -> Result<Vec<String>, String> {
    let mut command = Command::new("sh");
    if triple.is_some_and(|t| t.contains("musl")) {
        command
            .env("MS_C_LIBS", "pinned")
            .env("CC", musl_compiler());
    }
    command
        .arg(root.join("runtime/third_party/libs.sh"))
        .args(args);
    if let Some(t) = triple {
        command.env("MS_C_TRIPLE", t);
    }
    let output = command.output().map_err(|e| format!("run libs.sh: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "libs.sh {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout)
        .split_whitespace()
        .map(str::to_string)
        .collect())
}

/// Whether the C libraries are wired for `triple`. Each target joins as its build is proven (workstream W0b);
/// a source that needs a library the target lacks stays out of that archive and the Rust runtime serves it.
fn c_libs_wired(triple: Option<&str>) -> bool {
    match std::env::consts::OS {
        "linux" => triple.is_none_or(|t| t.ends_with("linux-gnu") || t.ends_with("linux-musl")),
        "macos" => true,
        _ => false,
    }
}

/// Folders of `runtime` that hold code for one platform only: the target's own is compiled, the rest are not.
fn platform_dirs(triple: Option<&str>) -> Vec<&'static str> {
    let t = triple.map(str::to_string).unwrap_or_else(|| {
        format!(
            "{}-{}",
            std::env::consts::ARCH,
            match std::env::consts::OS {
                "linux" => "unknown-linux-gnu",
                "macos" => "apple-darwin",
                _ => "pc-windows-gnullvm",
            }
        )
    });
    let mut dirs = Vec::new();
    if t.contains("linux") || t.contains("apple") {
        dirs.push("posix");
    }
    if t.contains("linux") {
        dirs.push("linux");
    }
    if t.ends_with("linux-gnu") {
        dirs.push("glibc");
    }
    if t.contains("musl") {
        dirs.push("musl");
    }
    if t.contains("apple") {
        dirs.push("darwin");
    }
    if t.contains("windows") {
        dirs.push("windows");
    }
    dirs
}

/// Every C source of the runtime (`runtime/{sys,core,io,net,std}`; `third_party` and `tests` are not part of it).
/// A folder named for a platform (`posix` for Linux and macOS, `linux`, `glibc`, `musl`, `darwin`, `windows`) is compiled only for it.
fn c_sources(dir: &Path, platform: &[&str], found: &mut Vec<PathBuf>) {
    const PLATFORMS: [&str; 6] = ["posix", "linux", "glibc", "musl", "darwin", "windows"];
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if path.is_dir() {
            let other = PLATFORMS.contains(&name.as_ref()) && !platform.contains(&name.as_ref());
            if name != "third_party" && name != "tests" && !other {
                c_sources(&path, platform, found);
            }
        } else if path.extension().is_some_and(|e| e == "c") {
            found.push(path);
        }
    }
}

/// Plans the C half of the runtime archive for `triple`.
fn plan_c_runtime(root: &Path, triple: Option<&str>) -> Result<CRuntime, String> {
    let runtime = root.join("runtime");
    let platform = platform_dirs(triple);
    let mut sources = Vec::new();
    for layer in ["sys", "core", "io", "net", "std"] {
        c_sources(&runtime.join(layer), &platform, &mut sources);
    }
    sources.sort();
    let wired = c_libs_wired(triple);
    // The libuv reactor replaces the mio poller, which changes every program; it is opt-in (`MS_C_REACTOR=1`)
    // until the corpus passes with it on every target (workstream W5).
    let io = runtime.join("io");
    let reactor = std::env::var_os("MS_C_REACTOR").is_some();
    sources.retain(|s| (wired || libraries_of(s).is_empty()) && (reactor || !s.starts_with(&io)));
    // The PCRE2 regex natives change the pattern dialect, so they join every target together (workstream W8):
    // opt-in with `MS_C_REGEX=1` until Windows has the libraries too. Removal: delete this filter with `ms-std-regex`.
    let regex = std::env::var_os("MS_C_REGEX").is_some();
    sources.retain(|s| {
        regex
            || !s
                .file_name()
                .is_some_and(|n| n.to_string_lossy().starts_with("regex"))
    });
    let mut names: Vec<&str> = sources.iter().flat_map(|s| libraries_of(s)).collect();
    names.sort_unstable();
    names.dedup();
    if names.is_empty() {
        return Ok(CRuntime {
            sources,
            cflags: Vec::new(),
            libraries: Vec::new(),
        });
    }
    let cflags = libs_sh(root, triple, &["cflags"])?;
    let mut args = vec!["archives"];
    args.extend(&names);
    let libraries = libs_sh(root, triple, &args)?
        .into_iter()
        .map(PathBuf::from)
        .collect();
    Ok(CRuntime {
        sources,
        cflags,
        libraries,
    })
}

/// Compiles the planned C sources for `triple` and adds the objects, and every member of the libraries they
/// use, to `archive`. The objects define the symbols the Rust runtime compiled out (`runtime/symbols/<module>.txt`);
/// the library members are what the linker takes when a program reaches them.
fn add_c_runtime(
    root: &Path,
    target: &Path,
    triple: Option<&str>,
    plan: &CRuntime,
    archive: &Path,
) -> Result<(), String> {
    let runtime = root.join("runtime");
    if plan.sources.is_empty() {
        return Ok(());
    }
    let arch = std::env::consts::ARCH;
    let host = triple.is_none_or(|t| t.ends_with("linux-gnu"));
    let cc = match triple {
        Some(t) if t.contains("windows") => c_compiler(root, t, arch),
        Some(t) if t.contains("musl") => musl_compiler(),
        _ => PathBuf::from("clang"),
    };
    let objects = target.join("c-objects");
    let _ = std::fs::remove_dir_all(&objects);
    std::fs::create_dir_all(&objects).map_err(|e| e.to_string())?;
    let mut files = Vec::new();
    for (n, source) in plan.sources.iter().enumerate() {
        let stem = source.file_stem().and_then(|s| s.to_str()).unwrap_or("x");
        let object = objects.join(format!("{n}-{stem}.o"));
        let mut command = Command::new(&cc);
        command
            .args(["-c", "-O2", "-std=c11", "-fPIC", "-fno-stack-protector"])
            // A null check stays even where an attribute says the pointer is never null.
            .args(["-fno-strict-aliasing", "-fno-delete-null-pointer-checks"])
            .args(["-Wall", "-Wextra", "-Werror"])
            .arg("-I")
            .arg(runtime.join("include"))
            .arg("-I")
            .arg(source.parent().unwrap_or(&runtime))
            .args(&plan.cflags)
            .arg("-o")
            .arg(&object)
            .arg(source);
        // glibc and macOS check libc calls whose destination size is known (documentation/contributing/c-style.md).
        // Level 2: its `__*_chk` entry points are all older than the glibc floor.
        if !triple.is_some_and(|t| t.contains("windows") || t.contains("musl")) {
            command.arg("-D_FORTIFY_SOURCE=2");
        }
        // `musl-gcc` already targets musl, and llvm-mingw's clang wrapper mingw-w64 (Rust's `gnullvm` is not a
        // clang environment); a clang for another target needs it named.
        if let Some(t) = triple.filter(|t| !host && !t.contains("musl") && !t.contains("windows")) {
            command.arg(format!("--target={t}"));
        }
        let status = command
            .status()
            .map_err(|e| format!("run {}: {e}", cc.display()))?;
        if !status.success() {
            return Err(format!("compiling {} failed", source.display()));
        }
        files.push(object);
    }
    let ar = if triple.is_some_and(|t| t.contains("windows")) {
        cc.with_file_name(format!("llvm-ar{}", std::env::consts::EXE_SUFFIX))
    } else {
        PathBuf::from("ar")
    };
    let run_ar = |args: &[&OsStr], dir: &Path| -> Result<std::process::Output, String> {
        Command::new(&ar)
            .args(args)
            .current_dir(dir)
            .output()
            .map_err(|e| format!("run {}: {e}", ar.display()))
    };
    // Each library's members are extracted under a prefix naming the library, so equal member names in two
    // libraries stay apart (`ar rcs` replaces by name). A library with equal names inside itself cannot be
    // extracted whole; that is reported, not folded wrong.
    for (n, library) in plan.libraries.iter().enumerate() {
        let dir = objects.join(format!("lib{n}"));
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        let listing = run_ar(&["t".as_ref(), library.as_os_str()], &dir)?;
        if !listing.status.success() {
            return Err(format!("listing {} failed", library.display()));
        }
        let members: Vec<String> = String::from_utf8_lossy(&listing.stdout)
            .lines()
            .filter(|m| m.ends_with(".o") || m.ends_with(".obj"))
            .map(str::to_string)
            .collect();
        let mut unique = members.clone();
        unique.sort();
        unique.dedup();
        if unique.len() != members.len() {
            return Err(format!(
                "{} has members with equal names",
                library.display()
            ));
        }
        let extracted = run_ar(&["x".as_ref(), library.as_os_str()], &dir)?;
        if !extracted.status.success() {
            return Err(format!("extracting {} failed", library.display()));
        }
        let stem = library
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("lib");
        for member in &members {
            let renamed = dir.join(format!("{stem}.{member}"));
            std::fs::rename(dir.join(member), &renamed).map_err(|e| format!("{member}: {e}"))?;
            files.push(renamed);
        }
    }
    let status = Command::new(&ar)
        .arg("rcs")
        .arg(archive)
        .args(&files)
        .status()
        .map_err(|e| format!("run {}: {e}", ar.display()))?;
    if !status.success() {
        return Err(format!(
            "adding the C objects to {} failed",
            archive.display()
        ));
    }
    Ok(())
}

/// The C compiler for the runtime's C sources: `cc` where the target is Linux, else llvm-mingw's clang
/// (`MS_MINGW`, else the tree `toolchain/fetch-mingw.sh` leaves in `target/llvm-bundle/mingw`).
fn c_compiler(root: &Path, triple: &str, arch: &str) -> PathBuf {
    if !triple.contains("windows") {
        return PathBuf::from("cc");
    }
    let mingw = std::env::var_os("MS_MINGW")
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("target/llvm-bundle/mingw"));
    mingw.join("bin").join(format!("{arch}-w64-mingw32-clang"))
}

/// Drops the debug sections the toolchain's precompiled std, core and alloc objects carry (about 4 MB
/// of every linked program). Without a strip tool the archive is kept as built. Windows keeps the
/// archive whole: `llvm-strip` is the only strip tool there, and it rewrites some members (the ring
/// assembly objects) so that `ld` rejects the archive when they are linked.
fn strip_debug(archive: &Path) {
    if cfg!(windows) {
        return;
    }
    let flag = if cfg!(target_os = "macos") {
        "-S"
    } else {
        "--strip-debug"
    };
    // GNU `strip` first on Linux: `llvm-strip --strip-debug` rewrites the GCC-built objects of `ring`
    // (`.group` sections) into files GNU ld refuses ("file format not recognized"), so every program
    // that linked TLS or crypto failed wherever LLVM binutils were installed.
    let tools = if cfg!(target_os = "linux") {
        ["strip", "llvm-strip"]
    } else {
        ["llvm-strip", "strip"]
    };
    let original = archive.with_extension("unstripped");
    if std::fs::copy(archive, &original).is_err() {
        return;
    }
    for tool in tools {
        let stripped = Command::new(tool)
            .arg(flag)
            .arg(archive)
            .status()
            .is_ok_and(|status| status.success());
        if stripped {
            let _ = std::fs::remove_file(&original);
            return;
        }
        // A failed tool may have left a partial file: start the next one from the original.
        if std::fs::copy(&original, archive).is_err() {
            return;
        }
    }
    let _ = std::fs::remove_file(&original);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_signature_carries_flags_and_file_domain() {
        let header = "/* ms: domain demo */\n\
            /* ms-sig: msstd_demo_one(handle h: *const ObjCell<X>, err: ErrSlot) -> u8 @leaf */\n\
            uint8_t msstd_demo_one(void *h, void *err);\n\
            /* ms-sig: msstd_demo_two() -> i64 @domain=other */\n";
        let found = parse_header_signatures(header);
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].0, "msstd_demo_one");
        assert_eq!(
            found[0].1,
            "msstd_demo_one(handle h: *const ObjCell<X>, err: ErrSlot) -> u8"
        );
        assert_eq!(found[0].2, ["leaf", "domain=demo"]);
        assert_eq!(found[1].2, ["domain=other"]);
    }

    #[test]
    fn wrapper_types_compare_with_their_c_kinds() {
        assert_eq!(abi_kind("err: ErrSlot"), abi_kind("void *err"));
        assert_eq!(abi_kind("raw: HasRaw"), abi_kind("uint8_t raw"));
    }
}
