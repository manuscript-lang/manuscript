use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

/// Compile all fixture C code with the same host ABI and CRT as the linker.
pub fn cc() -> Command {
    let program =
        std::env::var("CC").unwrap_or_else(|_| if cfg!(windows) { "clang" } else { "cc" }.into());
    let mut command = Command::new(program);
    if cfg!(target_os = "linux") {
        // The bundled linker links musl, which has no fortified `*_chk` entry points.
        command.arg("-D_FORTIFY_SOURCE=0");
    }
    if cfg!(windows) {
        command.arg(if cfg!(target_arch = "aarch64") {
            "--target=aarch64-pc-windows-msvc"
        } else {
            "--target=x86_64-pc-windows-msvc"
        });
        command.arg("-fms-runtime-lib=dll");
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
    ms_clif::link::link_all(object, &inputs, out)
}

fn builtins() -> Option<PathBuf> {
    if !cfg!(target_os = "linux") {
        return None;
    }
    let rustc = std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    let sysroot = Command::new(rustc)
        .args(["--print", "sysroot"])
        .output()
        .ok()?;
    let lib = PathBuf::from(String::from_utf8(sysroot.stdout).ok()?.trim())
        .join("lib/rustlib")
        .join(format!("{}-unknown-linux-musl", std::env::consts::ARCH))
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
    let done = Command::new("llvm-objcopy")
        .arg("--strip-debug")
        .arg(&rlib)
        .arg(&staged)
        .status()
        .is_ok_and(|status| status.success())
        && std::fs::rename(&staged, &stripped).is_ok();
    Some(if done { stripped } else { rlib })
}
