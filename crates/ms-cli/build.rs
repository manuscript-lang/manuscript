//! Embed the release version from `.msversion` and the native
//! static library (`ms-native`: the runtime plus every `ms-std-*` crate) that compiled programs link.

use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let path = manifest.join("../../.msversion");
    println!("cargo:rerun-if-changed={}", path.display());
    let version = std::fs::read_to_string(&path).unwrap_or_else(|_| "0.0.0".to_string());
    println!("cargo:rustc-env=MS_VERSION={}", version.trim());
    embed_native(&manifest.join(".."));
}

/// Build `ms-native` once per workspace (release, whatever the profile of `ms` itself) and copy the
/// archive into `OUT_DIR` for `include_bytes!`. `MS_NATIVE_LIB` names a prebuilt archive instead.
fn embed_native(crates: &Path) {
    println!("cargo:rerun-if-env-changed=MS_NATIVE_LIB");
    println!(
        "cargo:rerun-if-changed={}",
        crates.join("../Cargo.lock").display()
    );
    for entry in std::fs::read_dir(crates)
        .expect("crates directory")
        .flatten()
    {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name == "ms-native"
            || name == "ms-rt"
            || name == "ms-rt-abi"
            || name.starts_with("ms-std-")
        {
            println!("cargo:rerun-if-changed={}", entry.path().display());
        }
    }
    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let archive = match std::env::var_os("MS_NATIVE_LIB") {
        Some(prebuilt) => PathBuf::from(prebuilt),
        None => strip_debug(&out, build_native(&out, crates)),
    };
    let bytes =
        std::fs::read(&archive).unwrap_or_else(|e| panic!("read {}: {e}", archive.display()));
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

fn build_native(out: &Path, crates: &Path) -> PathBuf {
    // `target/<profile>/build/ms-cli-<hash>/out` -> share one `target/ms-native` between profiles.
    let target = out
        .ancestors()
        .nth(4)
        .filter(|_| out.ancestors().nth(2).and_then(|p| p.file_name()) == Some("build".as_ref()))
        .unwrap_or(out)
        .join("ms-native");
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    let mut command = Command::new(cargo);
    command
        .args(["build", "--release", "-p", "ms-native", "--manifest-path"])
        .arg(crates.join("../Cargo.toml"))
        .env("CARGO_TARGET_DIR", &target)
        // The runtime ships without debug info; symbol names are enough for the profiler.
        .env("CARGO_PROFILE_RELEASE_DEBUG", "0")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .env_remove("RUSTFLAGS");
    let status = command.status().expect("run cargo to build ms-native");
    assert!(status.success(), "building ms-native failed");
    // The MSVC toolchain names a staticlib `ms_native.lib`; every other target uses `libms_native.a`.
    let msvc = std::env::var("CARGO_CFG_TARGET_ENV").is_ok_and(|env| env == "msvc");
    target.join(if msvc {
        "release/ms_native.lib"
    } else {
        "release/libms_native.a"
    })
}

/// Drops the debug sections the toolchain's precompiled std, core and alloc objects carry (about 4 MB
/// of every linked program). A copy is stripped, so the shared `ms-native` build stays intact. Without
/// a strip tool the archive is used as built.
fn strip_debug(out: &Path, archive: PathBuf) -> PathBuf {
    let stripped = out.join("libms_native.stripped");
    if std::fs::copy(&archive, &stripped).is_err() {
        return archive;
    }
    let flag = if cfg!(target_os = "macos") {
        "-S"
    } else {
        "--strip-debug"
    };
    // GNU `strip` first on Linux: `llvm-strip --strip-debug` rewrites the GCC-built objects of `ring`
    // (`.group` sections) into files GNU ld refuses ("file format not recognized"), so every program
    // that linked TLS or crypto failed wherever LLVM binutils were installed.
    let tools = if cfg!(target_os = "linux") {
        ["strip", "llvm-strip"]
    } else {
        ["llvm-strip", "strip"]
    };
    for tool in tools {
        if Command::new(tool)
            .arg(flag)
            .arg(&stripped)
            .status()
            .is_ok_and(|status| status.success())
        {
            return stripped;
        }
        // A failed tool may have left a partial file: start the next one from the original.
        if std::fs::copy(&archive, &stripped).is_err() {
            return archive;
        }
    }
    archive
}

fn fnv1a(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf29ce484222325, |hash, byte| {
        (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3)
    })
}
