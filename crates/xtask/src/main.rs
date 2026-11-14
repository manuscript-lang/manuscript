//! Repository build steps, run as `cargo xtask <step>`.
//!
//! `runtime` builds `ms-native` (the runtime plus every `ms-std-*` crate) once and leaves the stripped
//! archive at `target/ms-native/libms_native.a`, where `ms-cli`'s build script embeds it.

use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

fn main() -> ExitCode {
    match std::env::args().nth(1).as_deref() {
        Some("runtime") => match runtime() {
            Ok(archive) => {
                println!("{}", archive.display());
                ExitCode::SUCCESS
            }
            Err(message) => {
                eprintln!("xtask runtime: {message}");
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
            eprintln!("usage: cargo xtask runtime | cargo xtask symbols [--check]");
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
    let mut out = String::from(
        "# Generated by `cargo xtask symbols`; do not edit. One line per exported runtime function:\n\
         # `name(param: type, ..) -> ret`, the C signature lowering marshals runtime calls from, then the\n\
         # flags the source declares with a `// ms: leaf pure fresh` comment above the function:\n\
         # `@leaf` never reaches a cancellation point, `@pure` only reads memory and cannot fault,\n\
         # `@fresh` returns a value that borrows none of its arguments, `@keeps:<param>` stores that\n\
         # function value, `@takes:<param>` takes ownership of that value, `@spawns` starts a task\n\
         # running program code, `@takes_self` has a `<name>_take` twin that reuses its first\n\
         # argument when it dies at the call, `@op=<mnemonic>` is exactly that MIR instruction on\n\
         # its arguments, and `@domain=<words>` names its failures' domain.\n",
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

/// The `// ms: flag ..` comments of `source`: each names the flags of the runtime function whose
/// name is the first `msrt_*`/`msstd_*` identifier on the next code line. The flags are the
/// declared ABI facts lowering and the optimizer read (`leaf`, `pure`, `fresh`, `keeps:<param>`
/// for a function value the runtime stores and drops itself, `takes:<param>` for a value
/// argument the runtime takes ownership of, `domain=<word>` for how its failures
/// name their domain when it differs from the file's `//! ms: domain`, `spawns` for a function that starts a
/// task running code of the program, `takes_self` for a function with a `<name>_take` twin that reuses its first argument when it dies at the call, and `op=<mnemonic>` for a function
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
                !["leaf", "pure", "fresh", "spawns", "takes_self"].contains(&f.as_str())
                    && !f.starts_with("keeps:")
                    && !f.starts_with("takes:")
                    && !f.starts_with("op=")
                    && !f.starts_with("domain=")
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
fn runtime() -> Result<PathBuf, String> {
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
    let archive = build_archive(&root, &out, &target, triple.as_deref(), "libms_native.a")?;
    if std::env::consts::OS == "linux" {
        let musl = format!("{arch}-unknown-linux-musl");
        build_archive(&root, &out, &target, Some(&musl), "libms_native_musl.a")?;
    }
    Ok(archive)
}

/// Builds `ms-native` for `triple` (the host when `None`) and copies its stripped archive to `out/name`.
fn build_archive(
    root: &Path,
    out: &Path,
    target: &Path,
    triple: Option<&str>,
    name: &str,
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
            "entry",
            "--manifest-path",
        ])
        .arg(root.join("Cargo.toml"))
        .env("CARGO_TARGET_DIR", target)
        // The runtime ships without debug info; symbol names are enough for the profiler.
        .env("CARGO_PROFILE_RELEASE_DEBUG", "0")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .env_remove("RUSTFLAGS");
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
    strip_debug(&archive);
    Ok(archive)
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
