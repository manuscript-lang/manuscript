//! The C half of the runtime build, shared by `cargo xtask runtime` (crates/xtask) and the build script of `ms-rt`
//! (crates/ms-rt/build.rs), which both include this file with `#[path]`. What to compile is decided by the CMake
//! project at the repository root (`CMakeLists.txt`, `cmake/`); this file only picks the compiler and the library
//! folder for a target, runs `cmake` with Ninja, and reads back the object list it leaves.
#![allow(dead_code)]

use std::path::{Path, PathBuf};
use std::process::Command;

/// What the CMake build leaves for one target.
pub struct CRuntime {
    /// Our objects and every member of the libraries they use, to add to the runtime archive.
    pub objects: Vec<PathBuf>,
    features: Vec<String>,
}

impl CRuntime {
    /// Whether the libuv reactor (`runtime/io`) is part of the archive; `ms-rt` then leaves its mio poller out.
    pub fn has_reactor(&self) -> bool {
        self.features.iter().any(|f| f == "reactor")
    }
}

/// The C compiler for the musl runtime: musl's own headers decide how libuv and OpenSSL compile (`musl-tools`).
pub fn musl_compiler() -> PathBuf {
    std::env::var_os("MS_MUSL_CC").map_or_else(|| PathBuf::from("musl-gcc"), PathBuf::from)
}

/// The C compiler for `triple`: llvm-mingw's clang (`MS_MINGW`, else the tree `toolchain/fetch-mingw.sh` leaves
/// in `target/llvm-bundle/mingw`) for Windows, `musl-gcc` for musl, else `clang`.
pub fn c_compiler(root: &Path, triple: &str, arch: &str) -> PathBuf {
    if triple.contains("windows") {
        let mingw = std::env::var_os("MS_MINGW")
            .map(PathBuf::from)
            .unwrap_or_else(|| root.join("target/llvm-bundle/mingw"));
        // CMake wants the full file name of the compiler, and a Windows host's file has the extension.
        let exe = if cfg!(windows) { ".exe" } else { "" };
        mingw
            .join("bin")
            .join(format!("{arch}-w64-mingw32-clang{exe}"))
    } else if triple.contains("musl") {
        musl_compiler()
    } else {
        PathBuf::from("clang")
    }
}

/// The archiver for `triple`: llvm-mingw's on Windows, else `ar`.
pub fn archiver(root: &Path, triple: Option<&str>) -> PathBuf {
    match triple {
        None if cfg!(windows) => PathBuf::from("llvm-ar"),
        Some(t) if t.contains("windows") => c_compiler(root, t, std::env::consts::ARCH)
            .with_file_name(format!("llvm-ar{}", std::env::consts::EXE_SUFFIX)),
        _ => PathBuf::from("ar"),
    }
}

/// Runs `program args...` and reports a failure with its output.
fn run(command: &mut Command, what: &str) -> Result<String, String> {
    let output = command.output().map_err(|e| {
        format!("{what}: {e} (the C build needs cmake and ninja: `sh runtime/third_party/libs.sh install`)")
    })?;
    if !output.status.success() {
        return Err(format!(
            "{what} failed:\n{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// The folder holding the C libraries (`include/`, `lib/lib*.a`) for `triple`, when they do not come from
/// pkg-config: pinned builds for musl (system packages are glibc's), MSYS2's packages for Windows.
fn libs_prefix(root: &Path, triple: &str) -> Result<Option<PathBuf>, String> {
    if triple.contains("musl") {
        let out = run(
            Command::new("sh")
                .arg(root.join("runtime/third_party/build.sh"))
                .arg(triple)
                .env("MS_C_LIBS", "pinned")
                .env("CC", musl_compiler()),
            "build.sh",
        )?;
        return Ok(Some(PathBuf::from(out)));
    }
    if triple.contains("windows") {
        let msys = std::env::var("MS_MSYS2").unwrap_or_else(|_| "C:/msys64".into());
        let env = if triple.starts_with("aarch64") {
            "clangarm64"
        } else {
            "clang64"
        };
        return Ok(Some(PathBuf::from(format!("{msys}/{env}"))));
    }
    Ok(None)
}

/// Configures and builds the C half of the runtime archive for `triple` (the host when `None`) in `work/cmake`
/// and returns the objects to add to the archive. ccache is used when it is installed (`CMakeLists.txt`).
pub fn build_c_runtime(
    root: &Path,
    work: &Path,
    triple: Option<&str>,
    stats: bool,
    process_entry: bool,
) -> Result<CRuntime, String> {
    let build = work.join("cmake");
    let arch = std::env::consts::ARCH;
    let mut configure = Command::new("cmake");
    configure
        .arg("-S")
        .arg(root)
        .arg("-B")
        .arg(&build)
        .args([
            "-G",
            "Ninja",
            "-DMS_BUILD_TESTS=OFF",
            "-DMS_BUILD_COMPILER=OFF",
            "-DCMAKE_BUILD_TYPE=",
        ])
        .arg(format!(
            "-DMS_ALLOC_STATS={}",
            if stats { "ON" } else { "OFF" }
        ))
        .arg(format!(
            "-DMS_PROCESS_ENTRY={}",
            if process_entry { "ON" } else { "OFF" }
        ))
        // The build is the same wherever it runs: the caller's flags do not reach it.
        .env_remove("CFLAGS")
        .env_remove("LDFLAGS");
    // A named archiver (llvm-mingw's) is told to CMake; a bare `ar` is found there.
    let ar = archiver(root, triple);
    if ar.is_absolute() {
        configure.arg(format!("-DCMAKE_AR={}", ar.display()));
    }
    if let Some(triple) = triple {
        configure.arg(format!("-DMS_TRIPLE={triple}"));
        configure.arg(format!(
            "-DCMAKE_C_COMPILER={}",
            c_compiler(root, triple, arch).display()
        ));
        // `musl-gcc` already targets musl and llvm-mingw's clang wrapper mingw-w64; a clang for another
        // target is told which.
        let host = triple.ends_with("linux-gnu");
        if !host && !triple.contains("musl") && !triple.contains("windows") {
            configure.arg(format!("-DCMAKE_C_COMPILER_TARGET={triple}"));
        }
        if let Some(prefix) = libs_prefix(root, triple)? {
            configure.arg("-DMS_C_LIBS=prefix");
            configure.arg(format!("-DMS_LIBS_PREFIX={}", prefix.display()));
            if triple.contains("windows") {
                // MSYS2 keeps its headers in one prefix; llvm-mingw's own come first.
                configure.arg("-DMS_LIBS_IDIRAFTER=ON");
                configure.arg("-DMS_LIBS_DEFINES=NGHTTP2_STATICLIB;PCRE2_STATIC");
            }
        }
    } else {
        configure.arg("-DCMAKE_C_COMPILER=clang");
        if cfg!(windows) {
            // A Windows host's own build (unit tests) targets MSVC.
            configure.arg(format!("-DCMAKE_C_COMPILER_TARGET={arch}-pc-windows-msvc"));
        }
    }
    run(&mut configure, "cmake configure")?;
    run(
        Command::new("cmake")
            .arg("--build")
            .arg(&build)
            .args(["--target", "ms_runtime"]),
        "cmake build",
    )?;
    let read = |name: &str| -> Result<Vec<String>, String> {
        let file = build.join(name);
        let text =
            std::fs::read_to_string(&file).map_err(|e| format!("read {}: {e}", file.display()))?;
        Ok(text.lines().map(str::to_string).collect())
    };
    Ok(CRuntime {
        objects: read("c-objects.txt")?
            .into_iter()
            .filter(|l| !l.is_empty())
            .map(PathBuf::from)
            .collect(),
        features: read("c-features.txt")?,
    })
}
