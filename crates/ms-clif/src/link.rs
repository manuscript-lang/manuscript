//! Linker driver. Linux links with the bundled `lld` and musl (no C toolchain involved); macOS and
//! Windows run the system C compiler driver over the object and the runtime.

use crate::Error;
use std::path::{Path, PathBuf};
#[cfg(not(target_os = "linux"))]
use std::process::Command;

#[cfg(target_os = "linux")]
mod bundled;

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
    #[cfg(target_os = "linux")]
    bundled::link(object, inputs, out, strip)?;
    #[cfg(not(target_os = "linux"))]
    system_link(object, inputs, out, strip)?;
    place_executable(out)?;
    emit_debug_companion(object, out)
}

#[cfg(not(target_os = "linux"))]
fn system_link(object: &Path, inputs: &[&Path], out: &Path, strip: bool) -> Result<(), Error> {
    let (program, mut command) = driver();
    command.arg("-o").arg(out).arg(object).args(inputs);
    if strip && !cfg!(windows) {
        command.arg("-Wl,-s");
    }
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
    let o = Command::new(&tool)
        .arg(out)
        .arg("-o")
        .arg(&companion)
        .output()
        .map_err(|e| Error(format!("cannot run {tool}: {e}")))?;
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

#[cfg(not(target_os = "linux"))]
/// The C compiler driver and a command to run it: `$MS_LINKER` when set, else the first of the
/// platform's usual names on `PATH`.
fn driver() -> (String, Command) {
    let program = std::env::var("MS_LINKER").unwrap_or_else(|_| default_driver().to_string());
    let command = Command::new(&program);
    (program, command)
}

#[cfg(not(any(windows, target_os = "linux")))]
fn default_driver() -> &'static str {
    "cc"
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

#[cfg(target_os = "macos")]
fn driver_options(_program: &str) -> &'static [&'static str] {
    // Drop runtime and standard-library code the program never reaches: the archive is one
    // object per Rust codegen unit with a section per function, so unused pieces cost nothing.
    &["-g", "-Wl,-dead_strip"]
}

#[cfg(target_os = "macos")]
fn system_libraries() -> &'static [&'static str] {
    // TLS reaches the system trust store through Security.framework.
    &[
        "-lm",
        "-lpthread",
        "-ldl",
        "-framework",
        "Security",
        "-framework",
        "CoreFoundation",
    ]
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
