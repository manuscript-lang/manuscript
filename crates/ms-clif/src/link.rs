//! Linker driver: runs the system C compiler driver over the object and the runtime.

use crate::Error;
use std::path::Path;
use std::process::Command;

/// Links `object` and the runtime static library into the executable `out`.
pub fn link(object: &Path, runtime: &Path, out: &Path) -> Result<(), Error> {
    link_all(object, &[runtime], out)
}

/// Like [`link`] with several runtime inputs (objects or static libraries), in order.
pub fn link_all(object: &Path, inputs: &[&Path], out: &Path) -> Result<(), Error> {
    let (program, mut command) = driver();
    command.arg("-o").arg(out).arg(object).args(inputs);
    command.args(system_libraries());
    command.args(driver_options(&program));
    let o = command
        .output()
        .map_err(|e| Error(format!("cannot run {program}: {e}")))?;
    if !o.status.success() {
        return Err(Error(format!(
            "link failed: {}",
            String::from_utf8_lossy(&o.stderr)
        )));
    }
    place_executable(out)
}

/// The C compiler driver and a command to run it: `$MS_LINKER` when set, else the first of the
/// platform's usual names on `PATH`.
fn driver() -> (String, Command) {
    let program = std::env::var("MS_LINKER").unwrap_or_else(|_| default_driver().to_string());
    let command = Command::new(&program);
    (program, command)
}

#[cfg(not(windows))]
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
            ]
        } else {
            &[
                "--target=x86_64-pc-windows-msvc",
                "-fms-runtime-lib=dll",
                "-fuse-ld=lld",
            ]
        }
    } else {
        &[]
    }
}

#[cfg(not(windows))]
fn driver_options(_program: &str) -> &'static [&'static str] {
    &[]
}

#[cfg(not(windows))]
fn system_libraries() -> &'static [&'static str] {
    &["-lm", "-lpthread", "-ldl"]
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
