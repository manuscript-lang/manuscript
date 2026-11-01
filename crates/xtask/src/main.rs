//! Repository build steps, run as `cargo xtask <step>`.
//!
//! `runtime` builds `ms-native` (the runtime plus every `ms-std-*` crate) once and leaves the stripped
//! archive at `target/ms-native/libms_native.a`, where `ms-cli`'s build script embeds it. It also
//! writes `target/ms-native/ms_rt_hot.ll`, the LLVM IR of the pure `ms-rt-hot` helpers that release
//! builds link into the program so they inline (see `crates/DESIGN.md`); `ms-clif`'s build script embeds it.

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
            .is_some_and(|n| n == "ms-rt" || n == "ms-rt-hot" || n.starts_with("ms-std-"));
        if is_runtime {
            rust_files(&dir.join("src"), &mut files);
        }
    }
    files.sort();
    for file in files {
        let source =
            std::fs::read_to_string(&file).map_err(|e| format!("{}: {e}", file.display()))?;
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
         # `name(param: type, ..) -> ret`, the C signature lowering marshals runtime calls from.\n",
    );
    for line in table.values() {
        out.push_str(line);
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

/// The `pub extern "C" fn msrt_*`/`msstd_*` functions written by hand in `source`, as
/// `(name, "name(params) -> ret")` with module paths dropped from the types.
fn scan_exports(source: &str) -> Vec<(String, String)> {
    let mut found = Vec::new();
    // `ms-rt-hot` takes integers only (so LLVM can inline it); a `/// C view: `name(..)`` line
    // above a function records the pointer types lowering marshals the call with.
    let views: std::collections::BTreeMap<String, String> = source
        .lines()
        .filter_map(|l| l.trim().strip_prefix("/// C view: `")?.strip_suffix('`'))
        .map(|view| {
            let view = split_params_line(view);
            (view.0, view.1)
        })
        .collect();
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
        let line = views.get(&name).cloned().unwrap_or(line);
        found.push((name, line));
    }
    found
}

/// Normalizes a `name(params) -> ret` line written by hand: `(name, line)`.
fn split_params_line(view: &str) -> (String, String) {
    let open = view.find('(').expect("C view needs a parameter list");
    let close = view.rfind(')').expect("C view needs a closing parenthesis");
    let name = view[..open].trim().to_string();
    let params = split_params(&view[open + 1..close]);
    let ret = view[close + 1..]
        .trim()
        .strip_prefix("->")
        .map(|r| strip_paths(&squash(r)));
    let mut line = format!("{name}({})", params.join(", "));
    if let Some(ret) = ret {
        line.push_str(" -> ");
        line.push_str(&ret);
    }
    (name, line)
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
    hot_ir(&root, &out, &target, triple.as_deref())?;
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

/// Compiles `ms-rt-hot` to LLVM IR for the runtime's target and writes the form `ms build` links into
/// programs to `out/ms_rt_hot.ll`.
fn hot_ir(root: &Path, out: &Path, target: &Path, triple: Option<&str>) -> Result<(), String> {
    let release = match triple {
        Some(triple) => target.join(triple).join("release"),
        None => target.join("release"),
    };
    let deps = release.join("deps");
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    let cargo_in_target = || {
        let mut command = Command::new(&cargo);
        command
            .env("CARGO_TARGET_DIR", target)
            .env("CARGO_PROFILE_RELEASE_DEBUG", "0")
            .env_remove("RUSTC_WORKSPACE_WRAPPER")
            .env_remove("CARGO_ENCODED_RUSTFLAGS")
            .env_remove("RUSTFLAGS");
        command
    };
    // Cargo skips rustc when nothing changed, so the IR from the last run stays; if it was deleted,
    // clean the package so the retry emits it again.
    let mut ir = None;
    for attempt in 0..2 {
        let mut command = cargo_in_target();
        command
            .args([
                "rustc",
                "--release",
                "--locked",
                "-p",
                "ms-rt-hot",
                "--manifest-path",
            ])
            .arg(root.join("Cargo.toml"));
        if let Some(triple) = triple {
            command.args(["--target", triple]);
        }
        command.args(["--", "--emit=llvm-ir"]);
        let status = command.status().map_err(|e| format!("run cargo: {e}"))?;
        if !status.success() {
            return Err("compiling ms-rt-hot to LLVM IR failed".to_string());
        }
        ir = hot_ir_files(&deps).into_iter().next();
        if ir.is_some() || attempt == 1 {
            break;
        }
        let mut clean = cargo_in_target();
        clean
            .args(["clean", "--release", "-p", "ms-rt-hot", "--manifest-path"])
            .arg(root.join("Cargo.toml"));
        if let Some(triple) = triple {
            clean.args(["--target", triple]);
        }
        let _ = clean.status();
    }
    let ir = ir.ok_or_else(|| format!("no ms-rt-hot IR in {}", deps.display()))?;
    let text = std::fs::read_to_string(&ir).map_err(|e| format!("read {}: {e}", ir.display()))?;
    let destination = out.join("ms_rt_hot.ll");
    std::fs::write(&destination, linkable(&text))
        .map_err(|e| format!("write {}: {e}", destination.display()))
}

fn hot_ir_files(deps: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(deps) else {
        return Vec::new();
    };
    let mut files: Vec<_> = entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.extension().is_some_and(|ext| ext == "ll")
                && path
                    .file_name()
                    .is_some_and(|name| name.to_string_lossy().starts_with("ms_rt_hot-"))
        })
        .filter_map(|path| Some((path.metadata().ok()?.modified().ok()?, path)))
        .collect();
    files.sort();
    files.into_iter().rev().map(|(_, path)| path).collect()
}

/// Turns rustc's IR into a library `llvm-link` can merge into a program module whose functions
/// carry no CPU attributes: drops the target triple and data layout (the program's are used) and the
/// `target-cpu`/`target-features` attributes (LLVM refuses to inline across a mismatch), and marks every
/// function `alwaysinline`, since everything in `ms-rt-hot` is meant to be part of its caller.
fn linkable(ir: &str) -> String {
    let mut out = String::with_capacity(ir.len());
    for line in ir.lines() {
        if line.starts_with("target triple =") || line.starts_with("target datalayout =") {
            continue;
        }
        let line = if line.starts_with("attributes #") {
            let line = drop_attribute(&drop_attribute(line, "target-cpu"), "target-features");
            // A group that held only those attributes (aarch64) must not be left empty: LLVM rejects it.
            line.replace("= { }", "= { \"ms-hot\"=\"1\" }")
        } else if line.starts_with("define ")
            && let Some(group) = line.rfind(" #")
        {
            format!("{} alwaysinline{}", &line[..group], &line[group..])
        } else {
            line.to_string()
        };
        out.push_str(&line);
        out.push('\n');
    }
    out
}

/// `line` without the string attribute `"name"="value"`.
fn drop_attribute(line: &str, name: &str) -> String {
    let key = format!(" \"{name}\"=\"");
    let Some(start) = line.find(&key) else {
        return line.to_string();
    };
    let value = start + key.len();
    let Some(length) = line[value..].find('"') else {
        return line.to_string();
    };
    format!("{}{}", &line[..start], &line[value + length + 1..])
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
    use super::linkable;

    #[test]
    fn linkable_strips_cpu_attributes_and_keeps_groups_non_empty() {
        let ir = "target triple = \"aarch64-unknown-linux-musl\"\n\
                  define i64 @msrt_f(i64 %a) unnamed_addr #0 {\n\
                  attributes #0 = { nounwind \"target-cpu\"=\"generic\" }\n\
                  attributes #1 = { \"target-cpu\"=\"generic\" }\n";
        let out = linkable(ir);
        assert!(!out.contains("target-cpu") && !out.contains("target triple"));
        assert!(out.contains("define i64 @msrt_f(i64 %a) unnamed_addr alwaysinline #0 {"));
        assert!(out.contains("attributes #0 = { nounwind }"));
        assert!(!out.contains("{ }"));
    }
}
