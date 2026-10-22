//! Linker driver. Linux and macOS run the `lld` bundled in `ms` (Linux over musl, macOS over
//! generated SDK stubs), so no C toolchain is involved; Windows still runs the system C compiler
//! driver over the object and the runtime.

use crate::Error;
use std::path::{Path, PathBuf};
#[cfg(windows)]
use std::process::Command;

#[cfg(unix)]
mod lld;
#[cfg(unix)]
pub(crate) use lld::{lld_path, llvm_tools};

/// Windows links with the system toolchain and has no bundled LLVM tools.
#[cfg(not(unix))]
pub(crate) fn lld_path() -> Result<PathBuf, Error> {
    Err(Error("no bundled linker on this platform".to_string()))
}

#[cfg(not(unix))]
pub(crate) fn llvm_tools() -> Result<Option<PathBuf>, Error> {
    Ok(None)
}

/// Links `object` and the runtime static library into the executable `out`.
pub fn link(object: &Path, runtime: &Path, out: &Path) -> Result<(), Error> {
    link_all(object, &[runtime], out)
}

/// Like [`link`] with several runtime inputs (objects or static libraries), in order.
pub fn link_all(object: &Path, inputs: &[&Path], out: &Path) -> Result<(), Error> {
    link_with(object, inputs, out, false)
}

/// Like [`link_all`]; `strip` also drops the symbol table (smallest executable, no symbol names
/// for profilers or backtraces).
pub fn link_with(object: &Path, inputs: &[&Path], out: &Path, strip: bool) -> Result<(), Error> {
    #[cfg(unix)]
    lld::link(object, inputs, out, strip)?;
    #[cfg(windows)]
    system_link(object, inputs, out, strip)?;
    place_executable(out)?;
    emit_debug_companion(object, out)
}

#[cfg(windows)]
fn system_link(object: &Path, inputs: &[&Path], out: &Path, strip: bool) -> Result<(), Error> {
    let (program, mut command) = driver();
    command.arg("-o").arg(out).arg(object).args(inputs);
    command.args(system_libraries());
    command.args(driver_options(&program));
    let o = command
        .output()
        .map_err(|e| Error(format!("cannot run the linker '{program}': {e}; install a C compiler driver (cc, gcc, or clang) or set MS_LINKER to its path")))?;
    if !o.status.success() {
        let stderr = String::from_utf8_lossy(&o.stderr);
        let detail = if stderr.trim().is_empty() {
            "the linker printed nothing".to_string()
        } else {
            stderr.trim_end().to_string()
        };
        return Err(Error(format!(
            "linking with '{program}' failed ({}); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:\n{detail}",
            o.status
        )));
    }
    Ok(())
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
fn emit_debug_companion(_object: &Path, _out: &Path) -> Result<(), Error> {
    Ok(())
}

#[cfg(target_os = "macos")]
fn emit_debug_companion(object: &Path, out: &Path) -> Result<(), Error> {
    use cranelift_object::object::Object as _;
    let bytes = std::fs::read(object).map_err(|e| Error(format!("read debug object: {e}")))?;
    let file = cranelift_object::object::File::parse(bytes.as_slice())
        .map_err(|e| Error(format!("read debug object: {e}")))?;
    if file.section_by_name("__debug_info").is_none() {
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

#[cfg(windows)]
/// The C compiler driver and a command to run it: `$MS_LINKER` when set, else the first of the
/// platform's usual names on `PATH`.
fn driver() -> (String, Command) {
    let program = std::env::var("MS_LINKER").unwrap_or_else(|_| default_driver().to_string());
    let command = Command::new(&program);
    (program, command)
}

/// `clang` links Windows objects through the MSVC or LLVM linker and takes the same
/// `-o`/`-l` options as the Unix drivers; `cc` is the fallback for MinGW setups.
#[cfg(windows)]
fn default_driver() -> &'static str {
    const NAMES: [&str; 3] = ["clang", "cc", "gcc"];
    NAMES
        .into_iter()
        .find(|name| on_path(name))
        .unwrap_or(NAMES[0])
}

#[cfg(windows)]
fn on_path(name: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|paths| {
        std::env::split_paths(&paths).any(|dir| dir.join(format!("{name}.exe")).is_file())
    })
}

/// Rust's runtime library asks for the dynamic C runtime (`msvcrt`); the driver would
/// otherwise add the static one and the two collide.
#[cfg(windows)]
fn driver_options(program: &str) -> &'static [&'static str] {
    if program.contains("clang") {
        if cfg!(target_arch = "aarch64") {
            &[
                "--target=aarch64-pc-windows-msvc",
                "-fms-runtime-lib=dll",
                "-fuse-ld=lld",
                "-Wl,/debug:dwarf",
                "-Wl,/opt:ref",
            ]
        } else {
            &[
                "--target=x86_64-pc-windows-msvc",
                "-fms-runtime-lib=dll",
                "-fuse-ld=lld",
                "-Wl,/debug:dwarf",
                "-Wl,/opt:ref",
            ]
        }
    } else {
        &[]
    }
}

/// What the Rust runtime library needs from Windows (the list `rustc --print
/// native-static-libs` gives for `std`, plus the certificate store and sockets).
#[cfg(windows)]
fn system_libraries() -> &'static [&'static str] {
    &[
        "-ladvapi32",
        "-lbcrypt",
        "-lcrypt32",
        "-ldbghelp",
        "-lkernel32",
        "-lntdll",
        "-lsecur32",
        "-luserenv",
        "-lws2_32",
    ]
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
