//! Linker driver. Every platform runs the `lld` bundled in `ms` (Linux over glibc 2.28 stubs, or musl with `--static`, macOS over generated
//! SDK stubs, Windows over the mingw-w64 CRT), so no C toolchain or SDK is involved.

use crate::{BuildOptions, Error};
use std::path::{Path, PathBuf};

mod bundled;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod fetch;
mod lld;
pub use lld::{is_static, llvm_tools};

/// Links `object` and the runtime inputs (objects or static libraries), in order, into the executable `out`.
pub fn link_all(object: &Path, inputs: &[&Path], out: &Path) -> Result<(), Error> {
    link_with(object, inputs, out, false, &BuildOptions::default())
}

/// Like [`link_all`]; `strip` also drops the symbol table (smallest executable, no symbol names
/// for profilers or backtraces). `build.static_musl` links static musl instead of glibc 2.28 stubs,
/// and the runtime in `inputs` must be the build for that libc.
pub fn link_with(
    object: &Path,
    inputs: &[&Path],
    out: &Path,
    strip: bool,
    build: &BuildOptions,
) -> Result<(), Error> {
    lld::link(object, inputs, out, strip, build)
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
