//! Builds the C back end (`src/compiler/`, target `ms_backend` of the CMake project) for this host and links it, so
//! `c_backend.rs` calls it in process. CMake and Ninja do the work.

use std::path::{Path, PathBuf};
use std::process::Command;

/// What linking needs embedded: musl and mingw startup files, the glibc symbol table, the pinned lld downloads.
mod link_bundle;

fn main() {
    link_bundle::bundle();
    let root = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("../..");
    for path in [
        "src/compiler/src",
        "src/compiler/include",
        "src/runtime/include",
        "cmake",
        "CMakeLists.txt",
    ] {
        println!("cargo::rerun-if-changed={}", root.join(path).display());
    }
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let dir = build_c_backend(&root, &out).expect("build the C back end");
    println!("cargo::rustc-link-search=native={}", dir.display());
    println!("cargo::rustc-link-lib=static=ms_backend");
}

/// Runs `command`, reporting a failure with its output.
fn run(command: &mut Command, what: &str) -> Result<(), String> {
    let output = command
        .output()
        .map_err(|e| format!("{what}: {e} (the C build needs cmake and ninja)"))?;
    if !output.status.success() {
        return Err(format!(
            "{what} failed:\n{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(())
}

/// Builds `libms_backend.a` (the C back end, `src/compiler/include/ms/emit_program.h`) for this host in `work/cmake`
/// and returns the folder holding it. A Windows host builds it for MSVC, the target of the Rust `ms` there.
fn build_c_backend(root: &Path, work: &Path) -> Result<PathBuf, String> {
    let build = work.join("cmake");
    let mut configure = Command::new("cmake");
    configure
        .arg("-S")
        .arg(root)
        .arg("-B")
        .arg(&build)
        .args([
            "-G",
            "Ninja",
            "-DMS_BUILD_RUNTIME=OFF",
            "-DMS_BUILD_TESTS=OFF",
            "-DMS_BUILD_COMPILER=ON",
            "-DMS_BACKEND_ONLY=ON",
            "-DCMAKE_BUILD_TYPE=",
            "-DCMAKE_C_COMPILER=clang",
        ])
        .env_remove("CFLAGS")
        .env_remove("LDFLAGS");
    if cfg!(windows) {
        configure.arg(format!(
            "-DCMAKE_C_COMPILER_TARGET={}-pc-windows-msvc",
            std::env::consts::ARCH
        ));
    }
    run(&mut configure, "cmake configure")?;
    run(
        Command::new("cmake")
            .arg("--build")
            .arg(&build)
            .args(["--target", "ms_backend"]),
        "cmake build",
    )?;
    Ok(build.join("compiler"))
}
