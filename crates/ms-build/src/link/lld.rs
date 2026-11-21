//! Linking with the pinned `lld` (downloaded once into the cache), so no C toolchain is needed. Linux produces a
//! dynamic executable over stubs of glibc 2.28 (it runs on any later glibc), or with `--static` a static one over musl's startup files and libc;
//! macOS links against generated SDK stubs; Windows
//! links an executable over the mingw-w64 CRT and import libraries, so it needs neither the MSVC
//! SDK nor a C compiler.

use crate::{BuildOptions, Error};
use std::ffi::CString;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use super::bundled::{FILES, LINKER_ID};

/// The directory holding `opt`, `llc` and `llvm-link`: `build.llvm_tools`, else the pinned release
/// fetched into the cache on first use. `None` when there is no such release for this target or it
/// could not be fetched; release builds then use Cranelift.
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub fn llvm_tools(build: &BuildOptions) -> Result<Option<PathBuf>, Error> {
    if let Some(dir) = &build.llvm_tools {
        return Ok(Some(dir.clone()));
    }
    Ok(match fetch_llvm_tools() {
        Ok(dir) => dir,
        Err(e) => {
            eprintln!("ms: {e}; release builds use Cranelift");
            None
        }
    })
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
pub fn llvm_tools(_build: &BuildOptions) -> Result<Option<PathBuf>, Error> {
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

/// The `lld` to link with: `build.lld`, else the pinned release fetched into the cache on first use.
fn lld_path(build: &BuildOptions) -> Result<PathBuf, Error> {
    if let Some(path) = &build.lld {
        return Ok(path.clone());
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

fn c_path(path: &Path) -> Result<CString, Error> {
    CString::new(path.to_string_lossy().as_bytes())
        .map_err(|_| Error(format!("{} holds a NUL", path.display())))
}

/// Links `object` and `inputs` (the runtime built for this platform) into the executable `out` with libms
/// (`compiler/src/build/link.c`), which runs the pinned `lld` over the bundled files.
pub fn link(
    object: &Path,
    inputs: &[&Path],
    out: &Path,
    strip: bool,
    build: &BuildOptions,
) -> Result<(), Error> {
    let musl = is_static(build);
    let dir = c_path(&extract()?)?;
    let lld = c_path(&lld_path(build)?)?;
    // The glibc stubs of a dynamic Linux link are assembled with `llc`.
    let llc = if cfg!(target_os = "linux") && !musl {
        let tools = llvm_tools(build)?.ok_or_else(|| {
            Error("no LLVM tools are available for this platform; set MS_LLVM_TOOLS".into())
        })?;
        Some(c_path(&tools.join("llc"))?)
    } else {
        None
    };
    crate::c_backend::build_link(
        &c_path(object)?,
        inputs
            .iter()
            .map(|path| c_path(path))
            .collect::<Result<Vec<_>, _>>()?
            .as_slice(),
        &c_path(out)?,
        &crate::c_backend::LinkFiles {
            lld: &lld,
            llc: llc.as_ref(),
            files: &dir,
            strip,
            musl,
        },
    )
    .map_err(Error)
}

/// Whether Linux links static musl; the runtime archive must be the musl build to match.
pub fn is_static(build: &BuildOptions) -> bool {
    cfg!(target_os = "linux") && build.static_musl
}

/// Writes the bundled linker and its support files to a per-build cache entry, once.
fn extract() -> Result<PathBuf, Error> {
    let dir = cache_root().join("ms").join("linker").join(LINKER_ID);
    extract_at(&dir, FILES)?;
    // The link stages generated files (the macOS SDK stubs) in it, and macOS bundles none.
    std::fs::create_dir_all(&dir).map_err(|e| {
        Error(format!(
            "cannot create the linker directory {}: {e}",
            dir.display()
        ))
    })?;
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

#[cfg(test)]
mod tests;
