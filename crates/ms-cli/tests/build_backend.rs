//! Sidecars describe the code generator that actually produced the artifact,
//! including warm restores after the LLVM tools stop being available.
use crate::common;

use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::OnceLock;

fn tools() -> Option<&'static Path> {
    static TOOLS: OnceLock<Option<PathBuf>> = OnceLock::new();
    TOOLS
        .get_or_init(|| {
            ms_clif::link::llvm_tools(&ms_cli::engine::build_options_from_env()).unwrap()
        })
        .as_deref()
}

fn command(root: &Path, profile: &str, cranelift: bool) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_ms"));
    command
        .env_remove("MS_RT_LIB")
        .env_remove("MS_BACKEND")
        .env("MS_CACHE", "on")
        .env("MS_TIMINGS", "1")
        .args(["build"])
        .arg(root.join("main.ms"))
        .args(["--build-type", profile, "-o"])
        .arg(root.join(format!("program{}", std::env::consts::EXE_SUFFIX)));
    if cranelift || tools().is_none() {
        command.env("MS_BACKEND", "cranelift");
    } else {
        command.env("MS_LLVM_TOOLS", root.join("tools"));
    }
    command
}

fn success(result: Output) -> String {
    let stderr = String::from_utf8_lossy(&result.stderr).into_owned();
    assert!(result.status.success(), "{:?}: {stderr}", result.status);
    stderr
}

fn check(root: &Path, profile: &str, llvm: bool) -> Vec<u8> {
    let output = root.join(format!("program{}", std::env::consts::EXE_SUFFIX));
    assert_eq!(Command::new(&output).status().unwrap().code(), Some(5));
    let metadata = PathBuf::from(format!("{}.ms-build.json", output.display()));
    let document = ms_json::parse(std::fs::read(metadata).unwrap()).unwrap();
    assert_eq!(
        document.get("backend").unwrap().as_str().unwrap(),
        if llvm { "llvm" } else { "cranelift" }
    );
    assert_eq!(document.get("build_type").unwrap().as_str(), Some(profile));
    assert_eq!(document.get("format").unwrap().as_i64(), Some(1));
    std::fs::read(output).unwrap()
}

#[test]
fn sidecar_backend_matches_native_codegen_on_cold_warm_and_verified_builds() {
    for (name, profile, cranelift) in [
        ("debug", "Debug", false),
        ("release-cranelift", "Release", true),
        ("release", "Release", false),
        ("size", "MinSizeRel", false),
    ] {
        let root = common::scratch(&format!("backend-{name}"));
        std::fs::write(root.join("main.ms"), include_str!("build_backend/main.ms")).unwrap();
        if let Some(tools) = tools() {
            common::symlink_dir(tools, &root.join("tools")).unwrap();
        }
        let llvm = profile != "Debug" && !cranelift && tools().is_some();
        assert!(
            success(command(&root, profile, cranelift).output().unwrap())
                .contains("ms-timings: codegen")
        );
        let cold = check(&root, profile, llvm);
        let output = root.join(format!("program{}", std::env::consts::EXE_SUFFIX));
        std::fs::remove_file(&output).unwrap();
        std::fs::write(
            format!("{}.ms-build.json", output.display()),
            b"stale metadata",
        )
        .unwrap();
        // No codegen should be attempted on a warm hit, even when its configured tools vanish.
        if tools().is_some() {
            std::fs::remove_file(root.join("tools"))
                .or_else(|_| std::fs::remove_dir(root.join("tools")))
                .unwrap();
        }
        assert!(
            !success(command(&root, profile, cranelift).output().unwrap()).contains("ms-timings:")
        );
        assert_eq!(check(&root, profile, llvm), cold);
        if let Some(tools) = tools() {
            common::symlink_dir(tools, &root.join("tools")).unwrap();
        }
        success(
            command(&root, profile, cranelift)
                .env("MS_CACHE", "verify")
                .output()
                .unwrap(),
        );
        assert_eq!(check(&root, profile, llvm), cold);
        // Compilation failure must preserve the last successful executable and sidecar.
        let metadata = PathBuf::from(format!("{}.ms-build.json", output.display()));
        let prior_metadata = std::fs::read(&metadata).unwrap();
        std::fs::write(
            root.join("main.ms"),
            include_str!("build_backend/invalid.ms"),
        )
        .unwrap();
        assert!(
            !command(&root, profile, cranelift)
                .output()
                .unwrap()
                .status
                .success()
        );
        assert_eq!(std::fs::read(metadata).unwrap(), prior_metadata);
        assert_eq!(std::fs::read(output).unwrap(), cold);
        std::fs::remove_dir_all(root).unwrap();
    }
}

fn pin(kind: &str) -> String {
    let os = match std::env::consts::OS {
        "macos" => "darwin",
        os => os,
    };
    let arch = match std::env::consts::ARCH {
        "x86_64" => "amd64",
        "aarch64" => "arm64",
        arch => arch,
    };
    let suffix = format!("-{os}-{arch}.tar.gz");
    include_str!("../../../toolchain/lld.lock")
        .lines()
        .find_map(|line| {
            let mut fields = line.split_whitespace();
            let sha = fields.next()?;
            let name = fields.next()?;
            (name.starts_with(&format!("{kind}-")) && name.ends_with(&suffix))
                .then(|| sha[..16].to_string())
        })
        .expect("native target has a pinned tool bundle")
}

fn cache_root() -> PathBuf {
    let variable = |name| {
        std::env::var_os(name)
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
    };
    variable("LOCALAPPDATA")
        .filter(|_| cfg!(windows))
        .or_else(|| variable("XDG_CACHE_HOME"))
        .or_else(|| variable("HOME").map(|home| home.join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
}

fn discovery_state(root: &Path, available: bool) {
    let cache = root.join("discovery/ms/llvm");
    if cache.is_dir() {
        std::fs::remove_dir_all(&cache).unwrap();
    } else if cache.exists() {
        std::fs::remove_file(&cache).unwrap();
    }
    std::fs::create_dir_all(cache.parent().unwrap()).unwrap();
    if let Some(tools) = tools().filter(|_| available) {
        let directory = cache.join(pin("llvm-tools"));
        std::fs::create_dir_all(&directory).unwrap();
        for name in ["opt", "llc", "llvm-link"] {
            let name = format!("{name}{}", std::env::consts::EXE_SUFFIX);
            common::symlink_file(&tools.join(&name), &directory.join(&name)).unwrap();
        }
        std::fs::write(directory.join(".ok"), b"").unwrap();
    } else {
        // Staging fails before the downloader is called. This exercises the
        // real automatic fallback without relying on a network failure.
        std::fs::write(cache, b"controlled tool-cache obstruction").unwrap();
    }
}

#[test]
fn automatic_discovery_changes_preserve_the_cached_artifact_backend() {
    for initially_available in [true, false] {
        let root = common::scratch(&format!("backend-discovery-{initially_available}"));
        std::fs::write(root.join("main.ms"), include_str!("build_backend/main.ms")).unwrap();

        // A real default-cache build provisions the linker when necessary,
        // before the test switches to its disposable discovery fixture.
        success(
            command(&root, "Debug", true)
                .env("MS_CACHE", "off")
                .output()
                .unwrap(),
        );
        let linker = ms_cli::engine::build_options_from_env()
            .lld
            .unwrap_or_else(|| {
                cache_root()
                    .join("ms/lld")
                    .join(pin("lld"))
                    .join(format!("lld{}", std::env::consts::EXE_SUFFIX))
            });
        assert!(linker.is_file(), "{}", linker.display());
        let automatic = || {
            let mut command = command(&root, "Release", false);
            command
                .env_remove("MS_BACKEND")
                .env_remove("MS_LLVM_TOOLS")
                .env("MS_LLD", &linker)
                .env("XDG_CACHE_HOME", root.join("discovery"))
                .env("LOCALAPPDATA", root.join("discovery"));
            command
        };
        discovery_state(&root, initially_available);
        let llvm = initially_available && tools().is_some();
        let cold_stderr = success(automatic().output().unwrap());
        assert!(cold_stderr.contains("ms-timings: codegen"));
        let cold = check(&root, "Release", llvm);
        discovery_state(&root, !initially_available);
        let output = root.join(format!("program{}", std::env::consts::EXE_SUFFIX));
        std::fs::remove_file(&output).unwrap();
        std::fs::write(
            format!("{}.ms-build.json", output.display()),
            b"stale metadata",
        )
        .unwrap();
        let warm_stderr = success(automatic().output().unwrap());
        assert!(!warm_stderr.contains("ms-timings:"), "{warm_stderr}");
        assert_eq!(check(&root, "Release", llvm), cold);
        assert!(
            !warm_stderr.contains("cannot create the cache for llvm"),
            "warm metadata must not probe current discovery: {warm_stderr}"
        );
        std::fs::remove_dir_all(root).unwrap();
    }
}
