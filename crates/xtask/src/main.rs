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
        _ => {
            eprintln!("usage: cargo xtask runtime");
            ExitCode::from(2)
        }
    }
}

/// Builds `ms-native` in release mode, whatever the profile of `ms` itself, and returns the archive.
fn runtime() -> Result<PathBuf, String> {
    // Cargo can reuse this executable from another checkout when target directories are shared.
    // Its runtime environment names the active package; the compiled path may name the old one.
    let manifest = std::env::var_os("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")));
    let root = manifest.join("../..");
    let out = root.join("target/ms-native");
    let target = out.join("build");
    // Linux programs are static musl executables and Windows programs mingw-w64 (gnullvm) ones, all
    // linked by the bundled lld, so the runtime is built for that target. `ring`'s C sources need a C
    // compiler (llvm-mingw's clang on Windows): building the runtime needs one, using `ms` does not.
    let arch = std::env::consts::ARCH;
    let triple = match std::env::consts::OS {
        "linux" => Some(format!("{arch}-unknown-linux-musl")),
        "windows" => Some(format!("{arch}-pc-windows-gnullvm")),
        _ => None,
    };
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    let mut command = Command::new(cargo);
    command
        .args([
            "build",
            "--release",
            "--locked",
            "-p",
            "ms-native",
            "--manifest-path",
        ])
        .arg(root.join("Cargo.toml"))
        .env("CARGO_TARGET_DIR", &target)
        // The runtime ships without debug info; symbol names are enough for the profiler.
        .env("CARGO_PROFILE_RELEASE_DEBUG", "0")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .env_remove("RUSTFLAGS");
    if let Some(triple) = &triple {
        let cc = format!("CC_{}", triple.replace('-', "_"));
        if std::env::var_os(&cc).is_none() {
            command.env(cc, c_compiler(&root, triple, arch));
        }
        command.args(["--target", triple]);
    }
    let status = command.status().map_err(|e| format!("run cargo: {e}"))?;
    if !status.success() {
        return Err("building ms-native failed".to_string());
    }
    let release = match &triple {
        Some(triple) => target.join(triple).join("release"),
        None => target.join("release"),
    };
    let built = release.join("libms_native.a");
    let archive = out.join("libms_native.a");
    std::fs::copy(&built, &archive).map_err(|e| format!("copy {}: {e}", built.display()))?;
    strip_debug(&archive);
    hot_ir(&root, &out, &target, triple.as_deref())?;
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
