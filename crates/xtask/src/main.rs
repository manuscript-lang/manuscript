//! Repository build steps, run as `cargo xtask <step>`.
//!
//! `runtime` builds `ms-native` (the runtime plus every `ms-std-*` crate) once and leaves the stripped
//! archive at `target/ms-native/libms_native.a`, where `ms-cli`'s build script embeds it.
//! `runtime --alloc-profile` also builds `libms_native_allocs.a`, the same runtime with allocation
//! sampling for `ms profile --allocs`; release packaging asks for it, pull request CI does not.
//! `runtime --stats` builds `libms_native_stats.a`, the counting runtime of the leak checks.
//! `runtime --sched-stress` builds `libms_native_stress.a`, the runtime with the scheduler stress mode,
//! which only `make stress-sched` embeds (in a separate `ms`).

#[path = "../../../runtime/build_c.rs"]
mod build_c;

use build_c::{CRuntime, archiver, build_c_runtime, c_compiler, run_c_tests};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

fn main() -> ExitCode {
    match std::env::args().nth(1).as_deref() {
        Some("runtime") => {
            let flag = std::env::args().nth(2);
            match runtime(
                flag.as_deref() == Some("--alloc-profile"),
                flag.as_deref() == Some("--sched-stress"),
                flag.as_deref() == Some("--stats"),
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
        Some("c-test") => match c_tests() {
            Ok(report) => {
                println!("{report}");
                ExitCode::SUCCESS
            }
            Err(message) => {
                eprintln!("xtask c-test: {message}");
                ExitCode::FAILURE
            }
        },
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
                "usage: cargo xtask runtime [--alloc-profile | --sched-stress | --stats] | cargo xtask c-test | cargo xtask symbols [--check]"
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
    // No Rust crate declares natives once the last `ms-std-*` crate is gone, so no test writes the file.
    let text = match std::fs::read_to_string(&recorded) {
        Ok(text) => text,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(e) => return Err(format!("{}: {e}", recorded.display())),
    };
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
    if text.contains('*') || text.contains("fn(") {
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
    // Role aliases of the runtime ABI (crates/ms-rt-abi): pointers and a presence byte.
    for alias in [
        "ElemDesc",
        "KeyDesc",
        "ValDesc",
        "ValueDesc",
        "CmpFn",
        "MsCompareFn",
        "RunDrop",
        "MsDropRun",
        "RunCopy",
        "MsSlotCopyRun",
        "JsonCtorFn",
        "JsonViewFn",
        "ErrSlot",
        "CleanupFn",
        "MsCleanupFn",
        "Entry",
        "MsAbiEntry",
        "MainFn",
        "MsMainFn",
        "MsGuardFn",
        "MsExitHook",
        "ExitHook",
        "MsGrowFn",
    ] {
        if word(alias) {
            return "ptr".into();
        }
    }
    if word("HasRaw") {
        return "u8".into();
    }
    for (rust, c) in [
        ("i64", "int64_t"),
        ("u64", "uint64_t"),
        ("i32", "int32_t"),
        ("i32", "int"),
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
            // `ms_*_v1` is the versioned C ABI of user extern shims (ms_rt/cabi.h), declared in ms_abi.h.
            if name.starts_with("ms_sys_") || name.ends_with("_v1") {
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
            let rust_params: Vec<String> = split_top_level(rust_params)
                .into_iter()
                .filter(|p| !p.trim().is_empty())
                .map(|p| abi_kind(p.split_once(':').map_or(p, |(_, t)| t)))
                .collect();
            let rust_ret = if rust_ret == "()" || rust_ret == "!" {
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
        if !["base", "runtime", "safe", "chars", "array"].contains(&module)
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
/// Splits a parameter list at the commas outside angle brackets (`FrameBuf<StrVal, 8>` is one parameter).
fn split_top_level(params: &str) -> Vec<&str> {
    let (mut parts, mut depth, mut start) = (Vec::new(), 0usize, 0);
    for (i, c) in params.char_indices() {
        match c {
            '<' | '(' => depth += 1,
            // The `>` of a `->` return arrow closes nothing.
            '>' if !params[..i].ends_with('-') => depth = depth.saturating_sub(1),
            ')' => depth = depth.saturating_sub(1),
            ',' if depth == 0 => {
                parts.push(&params[start..i]);
                start = i + 1;
            }
            _ => {}
        }
    }
    parts.push(&params[start..]);
    parts
}

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
        let ret = ret.replace("MS_NORETURN", "").replace("MS_NODISCARD", "");
        let ret = if head.contains('*') {
            "ptr".to_string()
        } else if ret.contains("MS_NORETURN") {
            "!".to_string()
        } else {
            abi_kind(&ret)
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

/// Builds the C unit tests for this host's runtime target and runs them: the Windows leg of `make c-test`.
fn c_tests() -> Result<String, String> {
    let manifest = std::env::var_os("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")));
    let root = manifest.join("../..");
    let arch = std::env::consts::ARCH;
    let triple = match std::env::consts::OS {
        "linux" => Some(format!("{arch}-unknown-linux-gnu")),
        "windows" => Some(format!("{arch}-pc-windows-gnullvm")),
        _ => None,
    };
    run_c_tests(
        &root,
        &root.join("target/ms-native/c-tests"),
        triple.as_deref(),
    )
}

/// Builds `ms-native` in release mode, whatever the profile of `ms` itself, and returns the archive.
/// On Linux it also leaves `libms_native_musl.a` beside it, the runtime of `ms build --static`.
fn runtime(alloc_profile: bool, sched_stress: bool, stats: bool) -> Result<PathBuf, String> {
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
        vec![(target.clone(), triple.clone(), "libms_native.a", "")];
    if stats {
        // The counting runtime of the leak checks: the allocator counts live blocks (MS_ALLOC_STATS) and the
        // runtime prints them at exit.
        jobs.push((
            out.join("build-stats"),
            triple.clone(),
            "libms_native_stats.a",
            "ms-rt/stats",
        ));
    }
    if alloc_profile {
        // The feature changes the runtime, so sharing a directory would rebuild it whenever the
        // two archives alternate.
        jobs.push((
            out.join("build-allocs"),
            triple.clone(),
            "libms_native_allocs.a",
            "alloc-profile",
        ));
    }
    if sched_stress {
        // The scheduler stress mode, for `make stress-sched`; never part of a shipped `ms`.
        jobs.push((
            out.join("build-stress"),
            triple.clone(),
            "libms_native_stress.a",
            "sched-stress",
        ));
    }
    if std::env::consts::OS == "linux" {
        jobs.push((
            out.join("build-musl"),
            Some(format!("{arch}-unknown-linux-musl")),
            "libms_native_musl.a",
            "",
        ));
    }
    // The C half does not depend on the Rust features, so each triple's CMake build runs once and its
    // objects go into every archive of that triple (CMake started beside a running build also fails on
    // Windows with `AssignProcessToJobObject: (50) The request is not supported`, so they run one by one).
    // The counting runtime (`stats`) is the one C build that differs: its allocator counts live blocks.
    let mut plans: Vec<(Option<String>, bool, Result<CRuntime, String>)> = Vec::new();
    for (dir, triple, _, features) in &jobs {
        let stats = features.contains("stats");
        if !plans.iter().any(|(t, s, _)| t == triple && *s == stats) {
            plans.push((
                triple.clone(),
                stats,
                build_c_runtime(&root, dir, triple.as_deref(), stats, true),
            ));
        }
    }
    let plan_of = |triple: &Option<String>, stats: bool| {
        plans
            .iter()
            .find(|(t, s, _)| t == triple && *s == stats)
            .expect("a plan for every job's triple")
            .2
            .as_ref()
    };
    let mut built = std::thread::scope(|scope| {
        let handles: Vec<_> = jobs
            .iter()
            .map(|(dir, triple, name, features)| {
                let (root, out) = (&root, &out);
                let plan = plan_of(triple, features.contains("stats"));
                scope.spawn(move || match plan {
                    Ok(plan) => {
                        build_archive(root, out, dir, triple.as_deref(), name, features, plan)
                    }
                    Err(message) => Err(message.clone()),
                })
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
    plan: &CRuntime,
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
    if plan.has_reactor() {
        // `ms-rt` then takes the reactor's poller; `add_c_runtime` supplies `runtime/io` and libuv.
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
    add_c_runtime(root, triple, plan, &archive)?;
    strip_debug(&archive);
    Ok(archive)
}

/// Adds the C objects the CMake build made for `triple`, and every member of the libraries they use, to `archive`.
fn add_c_runtime(
    root: &Path,
    triple: Option<&str>,
    plan: &CRuntime,
    archive: &Path,
) -> Result<(), String> {
    let files = &plan.objects;
    if files.is_empty() {
        return Ok(());
    }
    let ar = archiver(root, triple);
    let mut command = Command::new(&ar);
    let mut response = None;
    command.arg("rcs").arg(archive);
    if cfg!(windows) {
        // The folded library members overflow Windows' 32 KiB command line; llvm-ar reads a response file.
        let list = archive.with_extension("rsp");
        let names: Vec<String> = files
            .iter()
            .map(|f| f.to_string_lossy().replace('\\', "/"))
            .collect();
        std::fs::write(&list, names.join("\n"))
            .map_err(|e| format!("write {}: {e}", list.display()))?;
        command.arg(format!("@{}", list.display()));
        response = Some(list);
    } else {
        command.args(files);
    }
    let status = command
        .status()
        .map_err(|e| format!("run {}: {e}", ar.display()))?;
    if let Some(list) = response {
        let _ = std::fs::remove_file(list);
    }
    if !status.success() {
        return Err(format!(
            "adding the C objects to {} failed",
            archive.display()
        ));
    }
    Ok(())
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
