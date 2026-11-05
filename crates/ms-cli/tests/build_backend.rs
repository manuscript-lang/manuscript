//! Sidecars describe the code generator that actually produced the artifact,
//! including warm restores after the LLVM tools stop being available.
mod common;

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
        .env("MS_RT_HOT", root.join("helper.ll"))
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
    // The custom helper returns 47 only when LLVM actually consumes its IR.
    // Cranelift links the normal runtime and returns the string's length, 5.
    assert_eq!(
        Command::new(&output).status().unwrap().code(),
        Some(if llvm { 47 } else { 5 })
    );
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
        std::fs::write(
            root.join("helper.ll"),
            include_str!("build_backend/helper.ll"),
        )
        .unwrap();
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
