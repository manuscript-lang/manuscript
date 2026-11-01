//! Linking with the pinned `lld` (downloaded once into the cache), so no C toolchain is needed. Linux produces a
//! dynamic executable over the system glibc, or with `--static` a static one over musl's startup files and libc;
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
    use sha2::{Digest, Sha256};
    if url.is_empty() {
        return Ok(None);
    }
    let root = cache_root().join("ms").join(name);
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
    let stage = root.join(format!(".fetch-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&stage);
    std::fs::create_dir_all(&stage).map_err(|e| failed("create the cache for", &e))?;
    let result = (|| {
        // Only for a person at a terminal: programs and tests read this stream as output.
        if std::io::IsTerminal::is_terminal(&std::io::stderr()) {
            eprintln!("ms: fetching {name} (once)");
        }
        let archive = super::fetch::get(url).map_err(|e| failed("download", &e))?;
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
    let mut command = Command::new(lld_path()?);
    #[cfg(target_os = "linux")]
    linux_arguments(&mut command, &dir, object, inputs, out, strip, musl)?;
    #[cfg(target_os = "windows")]
    windows_arguments(&mut command, &dir, object, inputs, out, strip);
    #[cfg(target_os = "macos")]
    let stubs = macos_arguments(&mut command, &dir, object, inputs, out, strip)?;
    let o = command
        .output()
        .map_err(|e| Error(format!("cannot run the bundled linker: {e}")))?;
    #[cfg(target_os = "macos")]
    let _ = std::fs::remove_dir_all(stubs);
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
    Err(Error(format!(
        "linking failed ({}); the linker output follows. {advice}:\n{detail}",
        o.status
    )))
}

/// Whether Linux programs link static musl (`--static`) instead of the system glibc. Set once by the
/// command line before any build; the default is glibc.
static STATIC_MUSL: AtomicBool = AtomicBool::new(false);

/// Selects static musl (`true`) or the system glibc (`false`, the default) for Linux links.
pub fn set_static(on: bool) {
    STATIC_MUSL.store(on, Ordering::Relaxed);
}

/// Whether Linux links static musl; the runtime archive must be the musl build to match.
pub fn is_static() -> bool {
    cfg!(target_os = "linux") && STATIC_MUSL.load(Ordering::Relaxed)
}

/// The shared libraries glibc programs link, in order, with the first directory holding each. The
/// runtime needs `libc` and `libm` and unwinds through `libgcc_s`; older glibc keeps pthread, dl, rt and
/// util apart, so they join when present and `--as-needed` drops them when unused.
#[cfg(target_os = "linux")]
const GLIBC_LIBS: [&str; 7] = [
    "libgcc_s.so.1",
    "libc.so.6",
    "libm.so.6",
    "libpthread.so.0",
    "libdl.so.2",
    "librt.so.1",
    "libutil.so.1",
];

/// Where glibc keeps its runtime libraries and loader (multiarch and lib64 layouts).
#[cfg(target_os = "linux")]
fn glibc_dirs() -> Vec<PathBuf> {
    let arch = if cfg!(target_arch = "aarch64") {
        "aarch64"
    } else {
        "x86_64"
    };
    let mut dirs: Vec<PathBuf> = std::env::var_os("MS_LIBC_DIR")
        .filter(|v| !v.is_empty())
        .map(|v| std::env::split_paths(&v).collect())
        .unwrap_or_default();
    for base in ["/lib", "/usr/lib"] {
        dirs.push(format!("{base}/{arch}-linux-gnu").into());
    }
    for dir in ["/lib64", "/usr/lib64", "/lib", "/usr/lib"] {
        dirs.push(dir.into());
    }
    dirs
}

/// Finds the glibc libraries and loader on this machine, so the program runs where it was built.
#[cfg(target_os = "linux")]
fn glibc_files() -> Result<(Vec<PathBuf>, &'static str), Error> {
    let dirs = glibc_dirs();
    let find = |name: &str| dirs.iter().map(|d| d.join(name)).find(|p| p.is_file());
    let mut libs = Vec::new();
    for name in GLIBC_LIBS {
        match find(name) {
            Some(path) => libs.push(path),
            None if matches!(name, "libgcc_s.so.1" | "libc.so.6" | "libm.so.6") => {
                return Err(Error(format!(
                    "cannot find {name} to link against glibc; install glibc 2.34 or newer (and libgcc_s), set MS_LIBC_DIR to the directory holding it, or pass --static to link a static musl executable"
                )));
            }
            None => {}
        }
    }
    let loader = if cfg!(target_arch = "aarch64") {
        "/lib/ld-linux-aarch64.so.1"
    } else {
        "/lib64/ld-linux-x86-64.so.2"
    };
    Ok((libs, loader))
}

/// Drops runtime and standard-library code the program never reaches: the runtime archive is one
/// object per Rust codegen unit with a section per function, so unused pieces cost nothing.
#[cfg(target_os = "linux")]
fn linux_arguments(
    command: &mut Command,
    dir: &Path,
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
        let (libs, loader) = glibc_files()?;
        command
            .args(["--dynamic-linker", loader])
            .arg(object)
            .arg("--start-group")
            .args(inputs)
            .arg("--end-group")
            .arg("--as-needed")
            .args(libs);
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
    let sdk = dir.join(format!(".sdk-{}", std::process::id()));
    macos_stubs::write(&sdk, arch, object, inputs).inspect_err(|_| {
        let _ = std::fs::remove_dir_all(&sdk);
    })?;
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

/// Writes the bundled linker and its support files to a per-build cache entry, once.
fn extract() -> Result<PathBuf, Error> {
    let dir = cache_root().join("ms").join("linker").join(LINKER_ID);
    let present = |name: &str, bytes: &[u8]| {
        std::fs::metadata(dir.join(name)).is_ok_and(|m| m.len() == bytes.len() as u64)
    };
    if FILES.iter().all(|(name, bytes)| present(name, bytes)) {
        return Ok(dir);
    }
    let failed = |e: std::io::Error| {
        Error(format!(
            "cannot unpack the bundled linker into {}: {e}",
            dir.display()
        ))
    };
    std::fs::create_dir_all(&dir).map_err(failed)?;
    // Staged beside the destination so concurrent builds never see a partial file; the counter
    // keeps threads of one process from sharing a staged file.
    static STAGED: AtomicUsize = AtomicUsize::new(0);
    for (name, bytes) in FILES.iter().filter(|(name, bytes)| !present(name, bytes)) {
        let staged = dir.join(format!(
            ".{name}-{}-{}",
            std::process::id(),
            STAGED.fetch_add(1, Ordering::Relaxed)
        ));
        let written = std::fs::write(&staged, bytes)
            .and_then(|()| set_mode(&staged, false))
            .and_then(|()| std::fs::rename(&staged, dir.join(name)));
        // Another build may have installed (and be running) the same file; Windows refuses to
        // replace a file in use, so a complete copy already in place is as good as ours.
        if let Err(e) = written {
            let _ = std::fs::remove_file(&staged);
            if !present(name, bytes) {
                return Err(failed(e));
            }
        }
    }
    Ok(dir)
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

#[cfg(target_os = "macos")]
mod macos_stubs;
