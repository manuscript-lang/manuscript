use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

/// The mingw-w64 target the bundled Windows linker links, in clang's spelling.
#[cfg(windows)]
#[allow(dead_code)]
pub fn mingw_triple() -> &'static str {
    if cfg!(target_arch = "aarch64") {
        "aarch64-w64-mingw32"
    } else {
        "x86_64-w64-mingw32"
    }
}

/// llvm-mingw's clang: `MS_MINGW`, else the tree `toolchain/fetch-mingw.sh` leaves in `target/llvm-bundle`.
#[cfg(windows)]
#[allow(dead_code)]
pub fn mingw_clang() -> std::path::PathBuf {
    let root = std::env::var_os("MS_MINGW")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../target/llvm-bundle/mingw")
        });
    root.join("bin").join(format!("{}-clang", mingw_triple()))
}

/// Compile all fixture C code with the same ABI and CRT as the bundled linker.
pub fn cc() -> Command {
    // `CC` names the host compiler (MSVC ABI on Windows); fixtures must match the mingw-w64 runtime.
    #[cfg(windows)]
    let program = mingw_clang();
    #[cfg(not(windows))]
    let program = std::env::var("CC").unwrap_or_else(|_| "cc".into());
    let mut command = Command::new(program);
    if cfg!(windows) {
        // mingw-w64 headers declare the Windows 8 and later APIs only for a newer target version.
        command.arg("-D_WIN32_WINNT=0x0A00");
    }
    if cfg!(target_os = "linux") {
        // Fixtures link musl, which has no fortified `*_chk` entry points.
        command.arg("-D_FORTIFY_SOURCE=0");
    }
    command
}

/// Links `object` with a C fixture runtime. The bundled linker has no libgcc, and on aarch64 musl's
/// `printf` needs soft-float quad helpers; the Rust runtime carries them in its compiler-builtins,
/// so fixture runtimes borrow the toolchain's copy, without its debug info (which has ranges that
/// fail `llvm-dwarfdump --verify` on the linked executable).
#[allow(
    dead_code,
    reason = "test crates sharing this module use different helpers"
)]
pub fn link_fixture(object: &Path, runtime: &Path, out: &Path) -> Result<(), ms_clif::Error> {
    static BUILTINS: OnceLock<Option<PathBuf>> = OnceLock::new();
    let builtins = BUILTINS.get_or_init(builtins);
    let mut inputs = vec![runtime];
    inputs.extend(builtins.as_deref());
    // The C fixture runtimes define no process entry, so they link static musl, whose startup file does.
    ms_clif::link::link_libc(object, &inputs, out, false, cfg!(target_os = "linux"))
}

fn builtins() -> Option<PathBuf> {
    let triple = if cfg!(target_os = "linux") {
        format!("{}-unknown-linux-musl", std::env::consts::ARCH)
    } else if cfg!(windows) {
        format!("{}-pc-windows-gnullvm", std::env::consts::ARCH)
    } else {
        return None;
    };
    let rustc = std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    let sysroot = Command::new(rustc)
        .args(["--print", "sysroot"])
        .output()
        .ok()?;
    let lib = PathBuf::from(String::from_utf8(sysroot.stdout).ok()?.trim())
        .join("lib/rustlib")
        .join(triple)
        .join("lib");
    let rlib = std::fs::read_dir(lib)
        .ok()?
        .flatten()
        .map(|entry| entry.path())
        .find(|path| {
            let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
            name.starts_with("libcompiler_builtins") && name.ends_with(".rlib")
        })?;
    // Shared by every test process; staged under a private name and renamed so none sees a partial file.
    let stripped = std::env::temp_dir().join(format!(
        "ms-fixture-{}.a",
        rlib.file_name()?.to_str()?.trim_end_matches(".rlib")
    ));
    if stripped.is_file() {
        return Some(stripped);
    }
    let staged = stripped.with_extension(format!("{}.tmp", std::process::id()));
    // llvm-mingw ships one; runner images do not always have LLVM tools on `PATH`.
    #[cfg(windows)]
    let objcopy = mingw_clang().with_file_name("llvm-objcopy");
    #[cfg(not(windows))]
    let objcopy = PathBuf::from("llvm-objcopy");
    let done = Command::new(objcopy)
        .arg("--strip-debug")
        .arg(&rlib)
        .arg(&staged)
        .status()
        .is_ok_and(|status| status.success())
        && std::fs::rename(&staged, &stripped).is_ok();
    assert!(
        done || !cfg!(windows),
        "cannot strip debug info from {}",
        rlib.display()
    );
    Some(if done { stripped } else { rlib })
}
