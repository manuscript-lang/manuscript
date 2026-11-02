//! Linker driver. Every platform runs the `lld` bundled in `ms` (Linux over glibc 2.28 stubs, or musl with `--static`, macOS over generated
//! SDK stubs, Windows over the mingw-w64 CRT), so no C toolchain or SDK is involved.

use crate::Error;
use std::path::{Path, PathBuf};

mod bundled;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod fetch;
mod lld;
pub(crate) use bundled::RUNTIME_HOT_IR;
pub use lld::{is_static, llvm_tools, set_static};

/// Links `object` and the runtime inputs (objects or static libraries), in order, into the executable `out`.
pub fn link_all(object: &Path, inputs: &[&Path], out: &Path) -> Result<(), Error> {
    link_with(object, inputs, out, false)
}

/// Like [`link_all`]; `strip` also drops the symbol table (smallest executable, no symbol names
/// for profilers or backtraces).
pub fn link_with(object: &Path, inputs: &[&Path], out: &Path, strip: bool) -> Result<(), Error> {
    link_libc(object, inputs, out, strip, is_static())
}

/// Like [`link_with`], choosing the Linux libc: static musl when `musl`, else glibc 2.28 stubs. The
/// runtime in `inputs` must be the build for that libc.
pub fn link_libc(
    object: &Path,
    inputs: &[&Path],
    out: &Path,
    strip: bool,
    musl: bool,
) -> Result<(), Error> {
    lld::link(object, inputs, out, strip, musl)?;
    place_executable(out)?;
    emit_debug_companion(object, inputs, out)
}

/// Native debug companion for an executable, where the platform uses one.
/// macOS source lines live in this dSYM bundle after object files are removed.
pub fn debug_companion_path(output: &Path) -> Option<PathBuf> {
    if !cfg!(target_os = "macos") {
        return None;
    }
    let mut path = output.as_os_str().to_owned();
    path.push(".dSYM");
    Some(path.into())
}

#[cfg(not(target_os = "macos"))]
fn emit_debug_companion(_object: &Path, _inputs: &[&Path], _out: &Path) -> Result<(), Error> {
    Ok(())
}

#[cfg(target_os = "macos")]
fn emit_debug_companion(object: &Path, inputs: &[&Path], out: &Path) -> Result<(), Error> {
    use cranelift_object::object::Object as _;
    // Any object among the inputs may carry the DWARF (LLVM's does when it compiled the functions).
    let mut has_dwarf = false;
    for path in std::iter::once(object).chain(
        inputs
            .iter()
            .copied()
            .filter(|p| p.extension().is_some_and(|e| e == "o")),
    ) {
        let bytes = std::fs::read(path).map_err(|e| Error(format!("read debug object: {e}")))?;
        let file = cranelift_object::object::File::parse(bytes.as_slice())
            .map_err(|e| Error(format!("read debug object: {e}")))?;
        has_dwarf |= file.section_by_name("__debug_info").is_some();
    }
    if !has_dwarf {
        return Ok(());
    }
    let companion = debug_companion_path(out).expect("macOS companion");
    let tool = "dsymutil";
    let o = std::process::Command::new(tool)
        .arg(out)
        .arg("-o")
        .arg(&companion)
        .output();
    // Without `dsymutil` (no Xcode tools) the executable still runs; it just has no source lines.
    let o = match o {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        other => other.map_err(|e| Error(format!("cannot run {tool}: {e}")))?,
    };
    if !o.status.success() {
        return Err(Error(format!(
            "{tool} failed: {}",
            String::from_utf8_lossy(&o.stderr)
        )));
    }
    if !companion.is_dir() {
        return Err(Error("dsymutil did not produce a debug companion".into()));
    }
    Ok(())
}

/// Windows linkers add `.exe` to an output name without it; the build keeps the name it chose.
fn place_executable(out: &Path) -> Result<(), Error> {
    if out.exists() || out.extension().is_some() {
        return Ok(());
    }
    let mut with_suffix = out.as_os_str().to_owned();
    with_suffix.push(".exe");
    if Path::new(&with_suffix).exists() {
        std::fs::rename(&with_suffix, out)
            .map_err(|e| Error(format!("cannot place the executable: {e}")))?;
    }
    Ok(())
}
