//! Bundles what linking needs so `ms build` runs no C toolchain: the pinned static `lld` (released by
//! manuscript-lang/llvm-bundle and fetched by `scripts/fetch-lld.sh`) and, on Linux, the self-contained musl startup objects and libc
//! that Rust's musl target carries.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Files copied from the toolchain's musl `self-contained` directory.
const MUSL_FILES: [&str; 5] = ["crt1.o", "crti.o", "crtn.o", "libc.a", "libunwind.a"];

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=MS_LLD");
    println!("cargo:rerun-if-env-changed=RUSTC");
    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let bundle = out.join("linker");
    std::fs::create_dir_all(&bundle).expect("create the linker bundle directory");
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS");
    // Windows still links with the system toolchain; the bundle files are only placeholders there.
    let mut names: Vec<String> = vec!["lld".to_string()];
    if target_os == "windows" {
        std::fs::write(bundle.join("lld"), b"").expect("write placeholder");
    } else {
        copy(&lld(), &bundle.join("lld"), "lld");
    }
    if target_os == "linux" {
        // opt and llc sit beside lld when the LLVM tools were fetched; without them release builds
        // keep using Cranelift. They are embedded gzipped (together about 50 MB).
        let tools = lld().parent().map(Path::to_path_buf).unwrap_or_default();
        for tool in ["opt", "llc"] {
            let gz = format!("{tool}.gz");
            compress(&tools.join(tool), &bundle.join(&gz));
            names.push(gz);
        }
        let arch = std::env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH");
        let musl = sysroot()
            .join("lib/rustlib")
            .join(format!("{arch}-unknown-linux-musl"))
            .join("lib/self-contained");
        for name in MUSL_FILES {
            let to = bundle.join(name);
            copy(
                &musl.join(name),
                &to,
                &format!("{name} (run `rustup target add {arch}-unknown-linux-musl`)"),
            );
            strip_debug(&to);
            names.push(name.to_string());
        }
    }
    let mut id = 0xcbf29ce484222325u64;
    for name in &names {
        let bytes = std::fs::read(bundle.join(name)).expect("read bundled file");
        for byte in bytes.iter().chain(&(bytes.len() as u64).to_le_bytes()) {
            id = (id ^ u64::from(*byte)).wrapping_mul(0x100000001b3);
        }
    }
    println!("cargo:rustc-env=MS_LINKER_ID={id:016x}");
}

/// Writes `from` gzipped to `to`, or an empty file when `from` does not exist.
fn compress(from: &Path, to: &Path) {
    use std::io::Write;
    println!("cargo:rerun-if-changed={}", from.display());
    let Ok(bytes) = std::fs::read(from) else {
        std::fs::write(to, b"").expect("write placeholder");
        return;
    };
    let mut packed = Vec::new();
    let mut encoder = flate2::write::GzEncoder::new(&mut packed, flate2::Compression::new(6));
    encoder.write_all(&bytes).expect("compress");
    encoder.finish().expect("compress");
    if std::fs::read(to).ok().as_deref() != Some(&packed) {
        std::fs::write(to, packed).expect("write compressed tool");
    }
}

/// `MS_LLD`, else the one `scripts/fetch-lld.sh` leaves in `target/llvm-bundle`.
fn lld() -> PathBuf {
    if let Some(path) = std::env::var_os("MS_LLD") {
        return PathBuf::from(path);
    }
    let exe = if cfg!(windows) { "lld.exe" } else { "lld" };
    let built = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../target/llvm-bundle/install/bin")
        .join(exe);
    println!("cargo:rerun-if-changed={}", built.display());
    assert!(
        built.is_file(),
        "no lld to bundle: run `sh scripts/fetch-lld.sh` or set MS_LLD to a static lld"
    );
    built
}

fn sysroot() -> PathBuf {
    let rustc = std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    let output = Command::new(rustc)
        .args(["--print", "sysroot"])
        .output()
        .expect("run rustc --print sysroot");
    assert!(output.status.success(), "rustc --print sysroot failed");
    PathBuf::from(
        String::from_utf8(output.stdout)
            .expect("sysroot path")
            .trim(),
    )
}

fn copy(from: &Path, to: &Path, what: &str) {
    println!("cargo:rerun-if-changed={}", from.display());
    let bytes = std::fs::read(from)
        .unwrap_or_else(|e| panic!("cannot bundle {what} from {}: {e}", from.display()));
    if std::fs::read(to).ok().as_deref() != Some(&bytes) {
        std::fs::write(to, bytes).expect("write bundled file");
    }
}

/// musl's startup objects and archives carry line tables for code the program never sees in a
/// debugger; they would land in every linked executable. Without a strip tool the file is used as
/// shipped.
fn strip_debug(file: &Path) {
    let original = std::fs::read(file).expect("read bundled file");
    for tool in ["strip", "llvm-strip"] {
        let done = Command::new(tool)
            .arg("--strip-debug")
            .arg(file)
            .status()
            .is_ok_and(|status| status.success());
        if done {
            return;
        }
        // A failed tool may have left a partial file: start the next one from the original.
        std::fs::write(file, &original).expect("restore bundled file");
    }
}
