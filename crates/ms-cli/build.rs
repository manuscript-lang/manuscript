//! Embed the release version from `.msversion` and the prebuilt native static library (`ms-native`:
//! the runtime plus every `ms-std-*` crate) that compiled programs link.

use std::io::Write;
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
    let prebuilt = std::env::var_os("MS_NATIVE_LIB");
    let archive = match &prebuilt {
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
    if prebuilt.is_none() {
        reject_stale(crates, &archive);
    }
    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let embedded = out.join("libms_native.a.gz");
    // Gzipped: raw, the archive is a third of `ms`. Written only when the content changed, so an
    // unchanged archive keeps downstream builds cached.
    let mut packed = Vec::new();
    let mut encoder = flate2::write::GzEncoder::new(&mut packed, flate2::Compression::new(9));
    encoder.write_all(&bytes).expect("compress the archive");
    encoder.finish().expect("compress the archive");
    if std::fs::read(&embedded).ok().as_deref() != Some(&packed) {
        std::fs::write(&embedded, &packed).expect("write embedded archive");
    }
    println!("cargo:rustc-env=MS_NATIVE_LEN={}", bytes.len());
    println!(
        "cargo:rustc-env=MS_NATIVE_ID={:016x}-{}",
        fnv1a(&bytes),
        bytes.len()
    );
}

/// Runtime sources newer than the archive mean tests and programs would run an old runtime, so fail
/// instead of embedding it. `MS_NATIVE_LIB` opts out: its archive is not built from this tree.
fn reject_stale(crates: &Path, archive: &Path) {
    let built = std::fs::metadata(archive).and_then(|m| m.modified()).ok();
    let Some(built) = built else { return };
    let Ok(entries) = std::fs::read_dir(crates) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        let runtime =
            name == "ms-native" || name.starts_with("ms-rt") || name.starts_with("ms-std-");
        if !runtime {
            continue;
        }
        println!(
            "cargo:rerun-if-changed={}",
            entry.path().join("src").display()
        );
        println!(
            "cargo:rerun-if-changed={}",
            entry.path().join("Cargo.toml").display()
        );
        if let Some(newer) = newer_than(&entry.path(), built) {
            panic!(
                "the native runtime {} is older than {}\n\
                 rebuild it with `cargo xtask runtime` (or `make runtime`); tests and programs would otherwise run a stale runtime",
                archive.display(),
                newer.display()
            );
        }
    }
}

/// The first `Cargo.toml` or source file under `dir` modified after `built`.
fn newer_than(dir: &Path, built: std::time::SystemTime) -> Option<PathBuf> {
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let path = entry.path();
        let name = entry.file_name();
        if path.is_dir() {
            if name == "target" || name == "tests" || name == "benches" {
                continue;
            }
            if let Some(found) = newer_than(&path, built) {
                return Some(found);
            }
        } else if (path
            .extension()
            .is_some_and(|e| e == "rs" || e == "c" || e == "h")
            || name == "Cargo.toml")
            && entry
                .metadata()
                .and_then(|m| m.modified())
                .is_ok_and(|m| m > built)
        {
            return Some(path);
        }
    }
    None
}

fn fnv1a(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf29ce484222325, |hash, byte| {
        (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3)
    })
}
