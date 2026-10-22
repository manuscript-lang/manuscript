//! Linking with the `lld` bundled in `ms`, so no C toolchain is needed. Linux produces a static
//! executable over musl's startup files and libc; macOS links against generated SDK stubs; Windows
//! links an executable over the mingw-w64 CRT and import libraries, so it needs neither the MSVC
//! SDK nor a C compiler.

use crate::Error;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

macro_rules! bundled {
    ($($name:literal),*) => {
        const FILES: &[(&str, &[u8])] = &[
            $(($name, include_bytes!(concat!(env!("OUT_DIR"), "/linker/", $name)))),*
        ];
    };
}
#[cfg(target_os = "linux")]
bundled!("lld", "crt1.o", "crti.o", "crtn.o", "libc.a", "libunwind.a");
#[cfg(target_os = "windows")]
bundled!(
    "lld.exe",
    "crt2.o",
    "libmingw32.a",
    "libmingwex.a",
    "libmoldname.a",
    "libunwind.a",
    "libucrt.a",
    "libmsvcrt.a",
    "libkernel32.a",
    "libadvapi32.a",
    "libbcrypt.a",
    "libcrypt32.a",
    "libdbghelp.a",
    "libntdll.a",
    "libsecur32.a",
    "libuserenv.a",
    "libws2_32.a",
    "libuser32.a",
    "libshell32.a"
);
#[cfg(target_os = "macos")]
bundled!("lld");

#[cfg(windows)]
const LLD: &str = "lld.exe";
#[cfg(not(windows))]
const LLD: &str = "lld";

/// Links `object` and `inputs` (the runtime built for this platform) into the executable `out`.
pub fn link(object: &Path, inputs: &[&Path], out: &Path, strip: bool) -> Result<(), Error> {
    let dir = extract()?;
    let mut command = Command::new(dir.join(LLD));
    #[cfg(target_os = "linux")]
    linux_arguments(&mut command, &dir, object, inputs, out, strip);
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
    Err(Error(format!(
        "linking failed ({}); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:\n{detail}",
        o.status
    )))
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
) {
    command
        .args([
            "-flavor",
            "gnu",
            "-static",
            "--gc-sections",
            "--eh-frame-hdr",
        ])
        .arg("-o")
        .arg(out);
    if strip {
        command.arg("--strip-all");
    }
    command
        .arg(dir.join("crt1.o"))
        .arg(dir.join("crti.o"))
        .arg(object)
        .arg("--start-group")
        .args(inputs)
        .arg(dir.join("libunwind.a"))
        .arg(dir.join("libc.a"))
        .arg("--end-group")
        .arg(dir.join("crtn.o"));
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
    let dir = cache_root()
        .join("ms")
        .join("linker")
        .join(env!("MS_LINKER_ID"));
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
            .and_then(|()| set_mode(&staged, *name == LLD))
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
fn set_mode(_path: &Path, _executable: bool) -> std::io::Result<()> {
    Ok(())
}

#[cfg(unix)]
fn set_mode(path: &Path, executable: bool) -> std::io::Result<()> {
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
