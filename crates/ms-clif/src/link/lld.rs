//! Linking with the pinned `lld` (downloaded once into the cache), so no C toolchain is needed. Linux produces a
//! dynamic executable over stubs of glibc 2.28 (it runs on any later glibc), or with `--static` a static one over musl's startup files and libc;
//! macOS links against generated SDK stubs; Windows
//! links an executable over the mingw-w64 CRT and import libraries, so it needs neither the MSVC
//! SDK nor a C compiler.

use crate::Error;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use super::bundled::{FILES, LINKER_ID};

/// The directory holding `opt`, `llc` and `llvm-link`: `MS_LLVM_TOOLS`, else the pinned release fetched into
/// the cache on first use. `None` when there is no such release for this target or it could not be
/// fetched; release builds then use Cranelift.
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub fn llvm_tools() -> Result<Option<PathBuf>, Error> {
    if let Some(dir) = std::env::var_os("MS_LLVM_TOOLS").filter(|v| !v.is_empty()) {
        return Ok(Some(PathBuf::from(dir)));
    }
    // One attempt per process: a failed download is not retried for every function or program.
    static FETCHED: OnceLock<Option<PathBuf>> = OnceLock::new();
    Ok(FETCHED
        .get_or_init(|| match fetch_llvm_tools() {
            Ok(dir) => dir,
            Err(e) => {
                eprintln!("ms: {e}; release builds use Cranelift");
                None
            }
        })
        .clone())
}

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
fn fetch_llvm_tools() -> Result<Option<PathBuf>, String> {
    fetch(
        "llvm",
        super::bundled::LLVM_TOOLS_URL,
        super::bundled::LLVM_TOOLS_SHA256,
        &["opt", "llc", "llvm-link"],
    )
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
pub fn llvm_tools() -> Result<Option<PathBuf>, Error> {
    Ok(None)
}

/// Downloads the pinned `url` archive, checks its SHA-256 and unpacks `files` from its `bin/` into
/// `<cache>/ms/<name>/<sha>/`, once. Everything is staged beside the destination so concurrent
/// builds never see a partial file. `None` when the target has no published archive.
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
fn fetch(name: &str, url: &str, sha: &str, files: &[&str]) -> Result<Option<PathBuf>, String> {
    if url.is_empty() {
        return Ok(None);
    }
    let root = cache_root().join("ms").join(name);
    fetch_at(&root, name, sha, files, || super::fetch::get(url))
}

/// One cache attempt, with the download supplied separately so local tests can coordinate builders.
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
fn fetch_at(
    root: &Path,
    name: &str,
    sha: &str,
    files: &[&str],
    download: impl FnOnce() -> Result<Vec<u8>, String>,
) -> Result<Option<PathBuf>, String> {
    use sha2::{Digest, Sha256};
    let dir = root.join(&sha[..16]);
    let files: Vec<String> = files
        .iter()
        .map(|f| format!("{f}{}", if cfg!(windows) { ".exe" } else { "" }))
        .collect();
    if dir.join(".ok").is_file() && files.iter().all(|f| dir.join(f).is_file()) {
        return Ok(Some(dir));
    }
    let failed = |what: &str, e: &dyn std::fmt::Display| {
        format!("cannot {what} {name} into {}: {e}", dir.display())
    };
    let stage = staging(root, "fetch").map_err(|e| failed("create the cache for", &e))?;
    let result = (|| {
        // Only for a person at a terminal: programs and tests read this stream as output.
        if std::io::IsTerminal::is_terminal(&std::io::stderr()) {
            eprintln!("ms: fetching {name} (once)");
        }
        let archive = download().map_err(|e| failed("download", &e))?;
        let got: String = Sha256::digest(&archive)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        if got != sha {
            return Err(failed(
                "verify",
                &format!("checksum {got} does not match the pinned {sha}"),
            ));
        }
        super::fetch::unpack_tools(&archive, &files, &stage).map_err(|e| failed("unpack", &e))?;
        std::fs::create_dir_all(&dir).map_err(|e| failed("create the cache for", &e))?;
        for file in &files {
            // A concurrent build may have installed (and be running) the same file already.
            let _ = std::fs::rename(stage.join(file), dir.join(file));
            if !dir.join(file).is_file() {
                return Err(failed("install", &format!("{file} is missing")));
            }
        }
        std::fs::write(dir.join(".ok"), b"").map_err(|e| failed("finish", &e))
    })();
    let _ = std::fs::remove_dir_all(&stage);
    result.map(|()| Some(dir))
}

/// Exclusively owns one sibling staging directory. A failed or completed builder may remove only
/// this directory; concurrent threads and stale directories from a reused PID keep their contents.
fn staging(parent: &Path, prefix: &str) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(parent)?;
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    loop {
        let stage = parent.join(format!(
            ".{prefix}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        match std::fs::create_dir(&stage) {
            Ok(()) => return Ok(stage),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
}

/// The `lld` to link with: `MS_LLD`, else the pinned release fetched into the cache on first use.
fn lld_path() -> Result<PathBuf, Error> {
    if let Some(path) = std::env::var_os("MS_LLD").filter(|v| !v.is_empty()) {
        return Ok(PathBuf::from(path));
    }
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        let exe = if cfg!(windows) { "lld.exe" } else { "lld" };
        let fetched = fetch(
            "lld",
            super::bundled::LLD_URL,
            super::bundled::LLD_SHA256,
            &["lld"],
        );
        if let Some(dir) = fetched.map_err(|e| {
            Error(format!(
                "{e}; set MS_LLD to a local lld to link without downloading"
            ))
        })? {
            return Ok(dir.join(exe));
        }
    }
    Err(Error(
        "no lld is published for this platform; set MS_LLD to one".into(),
    ))
}

/// Links `object` and `inputs` (the runtime built for this platform) into the executable `out`.
pub fn link(
    object: &Path,
    inputs: &[&Path],
    out: &Path,
    strip: bool,
    musl: bool,
) -> Result<(), Error> {
    let dir = extract()?;
    let lld = lld_path()?;
    let mut command = Command::new(&lld);
    #[cfg(target_os = "linux")]
    linux_arguments(&mut command, &dir, &lld, object, inputs, out, strip, musl)?;
    #[cfg(target_os = "windows")]
    windows_arguments(&mut command, &dir, object, inputs, out, strip);
    #[cfg(target_os = "macos")]
    let stubs = macos_arguments(&mut command, &dir, object, inputs, out, strip)?;
    let result = command.output();
    #[cfg(target_os = "macos")]
    let _ = std::fs::remove_dir_all(stubs);
    let o = result.map_err(|e| Error(format!("cannot run the bundled linker: {e}")))?;
    if o.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&o.stderr);
    let detail = if stderr.trim().is_empty() {
        "the linker printed nothing".to_string()
    } else {
        stderr.trim_end().to_string()
    };
    // A symbol outside the runtime's `msrt_`/`msstd_` names is an `extern fn` nobody linked.
    let foreign = detail.lines().find_map(|line| {
        let name = line.split_once("undefined symbol: ")?.1.trim();
        (!name.starts_with("msrt_") && !name.starts_with("msstd_")).then_some(name)
    });
    let advice = match foreign {
        Some(name) => format!(
            "{name} is not part of the Manuscript runtime; if an extern fn declares it, pass the object or static library that defines it with --link <file>"
        ),
        None => "A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error".to_string(),
    };
    #[cfg(target_os = "linux")]
    let advice = if musl {
        advice
    } else {
        format!(
            "{advice}. Programs link against glibc 2.28, so an object built against a newer glibc may need symbols it lacks; pass --static to link musl instead"
        )
    };
    Err(Error(format!(
        "linking failed ({}); the linker output follows. {advice}:\n{detail}",
        o.status
    )))
}

/// Whether Linux programs link static musl (`--static`) instead of glibc. Set once by the
/// command line before any build; the default is glibc.
static STATIC_MUSL: AtomicBool = AtomicBool::new(false);

/// Selects static musl (`true`) or glibc (`false`, the default) for Linux links.
pub fn set_static(on: bool) {
    STATIC_MUSL.store(on, Ordering::Relaxed);
}

/// Whether Linux links static musl; the runtime archive must be the musl build to match.
pub fn is_static() -> bool {
    cfg!(target_os = "linux") && STATIC_MUSL.load(Ordering::Relaxed)
}

/// Drops runtime and standard-library code the program never reaches: the runtime archive is one
/// object per Rust codegen unit with a section per function, so unused pieces cost nothing.
#[cfg(target_os = "linux")]
#[allow(clippy::too_many_arguments)]
fn linux_arguments(
    command: &mut Command,
    dir: &Path,
    lld: &Path,
    object: &Path,
    inputs: &[&Path],
    out: &Path,
    strip: bool,
    musl: bool,
) -> Result<(), Error> {
    command
        .args(["-flavor", "gnu", "--gc-sections", "--eh-frame-hdr"])
        .arg("-o")
        .arg(out);
    if strip {
        command.arg("--strip-all");
    }
    if !musl {
        // The runtime archive defines `_start`, which hands `main` to glibc's `__libc_start_main`.
        // Every symbol binds at load (`-z now`), so a program never fails at a later call.
        let stubs = glibc_stubs::stubs(dir, lld)?;
        command
            .args(["--dynamic-linker", glibc_stubs::loader()])
            .args(["-z", "now", "-z", "relro"])
            .arg(object)
            .arg("--start-group")
            .args(inputs)
            .arg(dir.join("libunwind.a"))
            .arg("--end-group")
            .arg("--as-needed");
        for library in glibc_stubs::libraries() {
            command.arg(stubs.join(library));
        }
        return Ok(());
    }
    command
        .arg("-static")
        .arg(dir.join("crt1.o"))
        .arg(dir.join("crti.o"))
        .arg(object)
        .arg("--start-group")
        .args(inputs)
        .arg(dir.join("libunwind.a"))
        .arg(dir.join("libc.a"))
        .arg("--end-group")
        .arg(dir.join("crtn.o"));
    Ok(())
}

/// Links a console executable over mingw-w64's startup object and CRT, dropping unreachable sections
/// (`--gc-sections`, the `/opt:ref` of the MSVC linker) and keeping DWARF in the image. The import
/// libraries (`libkernel32.a`, ...) are the ones llvm-mingw generates from the DLL export lists.
#[cfg(target_os = "windows")]
fn windows_arguments(
    command: &mut Command,
    dir: &Path,
    object: &Path,
    inputs: &[&Path],
    out: &Path,
    strip: bool,
) {
    let machine = if cfg!(target_arch = "aarch64") {
        "arm64pe"
    } else {
        "i386pep"
    };
    command
        .args(["-flavor", "gnu", "-m", machine, "--gc-sections"])
        .args(["--subsystem", "console"])
        .arg("-o")
        .arg(out);
    if strip {
        command.arg("--strip-all");
    }
    command
        .arg(dir.join("crt2.o"))
        .arg(object)
        .arg("--start-group")
        .args(inputs);
    for lib in [
        "libmingw32.a",
        "libunwind.a",
        "libmoldname.a",
        "libmingwex.a",
        "libucrt.a",
        "libadvapi32.a",
        "libbcrypt.a",
        "libcrypt32.a",
        "libdbghelp.a",
        "libntdll.a",
        "libsecur32.a",
        "libshell32.a",
        "libuser32.a",
        "libuserenv.a",
        "libws2_32.a",
        "libkernel32.a",
    ] {
        command.arg(dir.join(lib));
    }
    command.arg("--end-group");
}

/// Returns the directory of generated stubs to remove after the link.
#[cfg(target_os = "macos")]
fn macos_arguments(
    command: &mut Command,
    dir: &Path,
    object: &Path,
    inputs: &[&Path],
    out: &Path,
    strip: bool,
) -> Result<PathBuf, Error> {
    let arch = if cfg!(target_arch = "aarch64") {
        "arm64"
    } else {
        "x86_64"
    };
    let sdk = sdk_stubs(dir, arch, object, inputs)?;
    command
        .args(["-flavor", "darwin", "-arch", arch])
        .args(["-platform_version", "macos", "12.0", "12.0"])
        .arg("-syslibroot")
        .arg(&sdk)
        .arg("-dead_strip")
        // lld turns `adrp x10, got; ...; ldr x8, [x10, got]` into `adr x8` at the adrp, clobbering
        // an x8 the code in between still uses (a list of string literals stored a shift result).
        // Workaround: remove once lld is fixed (#1748).
        .arg("-ignore_optimization_hints")
        .arg("-o")
        .arg(out);
    if strip {
        command.arg("-x");
    }
    command.arg(object).args(inputs).args([
        "-lSystem",
        "-framework",
        "Security",
        "-framework",
        "CoreFoundation",
    ]);
    Ok(sdk)
}

#[cfg(any(target_os = "macos", test))]
fn sdk_stubs(dir: &Path, arch: &str, object: &Path, inputs: &[&Path]) -> Result<PathBuf, Error> {
    let sdk = staging(dir, "sdk").map_err(|e| Error(format!("cannot stage the SDK stubs: {e}")))?;
    macos_stubs::write(&sdk, arch, object, inputs).inspect_err(|_| {
        let _ = std::fs::remove_dir_all(&sdk);
    })?;
    Ok(sdk)
}

/// Writes the bundled linker and its support files to a per-build cache entry, once.
fn extract() -> Result<PathBuf, Error> {
    let dir = cache_root().join("ms").join("linker").join(LINKER_ID);
    extract_at(&dir, FILES)?;
    Ok(dir)
}

fn extract_at(dir: &Path, files: &[(&str, &[u8])]) -> Result<(), Error> {
    let present = |name: &str, bytes: &[u8]| {
        std::fs::metadata(dir.join(name)).is_ok_and(|m| m.len() == bytes.len() as u64)
    };
    if files.iter().all(|(name, bytes)| present(name, bytes)) {
        return Ok(());
    }
    let failed = |e: std::io::Error| {
        Error(format!(
            "cannot unpack the bundled linker into {}: {e}",
            dir.display()
        ))
    };
    // The exclusively created directory owns every file we write and clean up. Stale
    // neighboring files or links must never be opened as this attempt's staging files.
    let stage = staging(dir, "embedded").map_err(failed)?;
    let result = (|| {
        for (name, bytes) in files.iter().filter(|(name, bytes)| !present(name, bytes)) {
            let staged = stage.join(name);
            let written = std::fs::write(&staged, bytes)
                .and_then(|()| set_mode(&staged, false))
                .and_then(|()| std::fs::rename(&staged, dir.join(name)));
            // Another build may have installed (and be running) the same file; Windows refuses to
            // replace a file in use, so a complete copy already in place is as good as ours.
            if let Err(e) = written
                && !present(name, bytes)
            {
                return Err(failed(e));
            }
        }
        Ok(())
    })();
    let _ = std::fs::remove_dir_all(stage);
    result
}

#[cfg(windows)]
pub(super) fn set_mode(_path: &Path, _executable: bool) -> std::io::Result<()> {
    Ok(())
}

#[cfg(unix)]
pub(super) fn set_mode(path: &Path, executable: bool) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mode = if executable { 0o755 } else { 0o644 };
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
}

/// `%LOCALAPPDATA%` on Windows; else `$XDG_CACHE_HOME`, `$HOME/.cache`, then the temporary directory.
fn cache_root() -> PathBuf {
    let set = |name| {
        std::env::var_os(name)
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
    };
    set("LOCALAPPDATA")
        .filter(|_| cfg!(windows))
        .or_else(|| set("XDG_CACHE_HOME"))
        .or_else(|| set("HOME").map(|home| home.join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
}

#[cfg(target_os = "linux")]
mod glibc_stubs;
#[cfg(any(target_os = "macos", test))]
mod macos_stubs;

#[cfg(test)]
mod tests;
