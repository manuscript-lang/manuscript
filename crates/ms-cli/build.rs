//! Embed the release version from `.msversion` and the prebuilt native static library (`ms-native`:
//! the runtime plus every `ms-std-*` crate) that compiled programs link.

use std::path::{Path, PathBuf};

fn main() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let path = manifest.join("../../.msversion");
    println!("cargo:rerun-if-changed={}", path.display());
    let version = std::fs::read_to_string(&path).unwrap_or_else(|_| "0.0.0".to_string());
    println!("cargo:rustc-env=MS_VERSION={}", version.trim());
    embed_native(&manifest.join(".."));
}

/// Embed the `ms-native` archive: `MS_NATIVE_LIB` names one, else `target/ms-native/libms_native.a`,
/// which `cargo xtask runtime` (`make runtime`) builds. The build script never compiles the runtime.
fn embed_native(crates: &Path) {
    println!("cargo:rerun-if-env-changed=MS_NATIVE_LIB");
    let archive = match std::env::var_os("MS_NATIVE_LIB") {
        Some(prebuilt) => PathBuf::from(prebuilt),
        None => crates.join("../target/ms-native/libms_native.a"),
    };
    println!("cargo:rerun-if-changed={}", archive.display());
    let bytes = std::fs::read(&archive).unwrap_or_else(|e| {
        panic!(
            "cannot read the native runtime {}: {e}\n\
             build it first with `cargo xtask runtime` (or `make runtime`), or set MS_NATIVE_LIB to a prebuilt libms_native.a",
            archive.display()
        )
    });
    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let embedded = out.join("libms_native.a");
    // Written only when the content changed, so an unchanged archive keeps downstream builds cached.
    if std::fs::read(&embedded).ok().as_deref() != Some(&bytes) {
        std::fs::write(&embedded, &bytes).expect("write embedded archive");
    }
    println!(
        "cargo:rustc-env=MS_NATIVE_ID={:016x}-{}",
        fnv1a(&bytes),
        bytes.len()
    );
}

fn fnv1a(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf29ce484222325, |hash, byte| {
        (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3)
    })
}
