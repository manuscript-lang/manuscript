//! Bundles the musl startup objects and libc that Rust's musl target carries, which the in-process
//! Linux linker links programs against, so `ms build` needs no C toolchain.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Files copied from the toolchain's musl `self-contained` directory, in link order.
const MUSL_FILES: [&str; 5] = ["crt1.o", "crti.o", "crtn.o", "libc.a", "libunwind.a"];

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=RUSTC");
    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let bundle = out.join("linker");
    std::fs::create_dir_all(&bundle).expect("create the linker bundle directory");
    let linux = std::env::var("CARGO_CFG_TARGET_OS").is_ok_and(|os| os == "linux");
    if !linux {
        return;
    }
    let sysroot = sysroot();
    let arch = std::env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH");
    let musl = sysroot
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
    }
    let mut id = 0xcbf29ce484222325u64;
    for name in MUSL_FILES {
        let bytes = std::fs::read(bundle.join(name)).expect("read bundled file");
        for byte in bytes.iter().chain(&(bytes.len() as u64).to_le_bytes()) {
            id = (id ^ u64::from(*byte)).wrapping_mul(0x100000001b3);
        }
    }
    println!("cargo:rustc-env=MS_LINKER_ID={id:016x}");
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

/// musl's startup objects and archives carry line tables for code the program never sees in a debugger; they would
/// land in every linked executable. Without a strip tool the file is used as shipped.
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
