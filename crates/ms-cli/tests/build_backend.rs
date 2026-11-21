//! Sidecars describe the code generator that actually produced the artifact,
//! on cold and repeated builds.
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

fn command(root: &Path, profile: &str) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_ms"));
    command
        .env_remove("MS_RT_LIB")
        .env_remove("MS_BACKEND")
        .env("MS_TIMINGS", "1")
        .args(["build"])
        .arg(root.join("main.ms"))
        .args(["--build-type", profile, "-o"])
        .arg(root.join(format!("program{}", std::env::consts::EXE_SUFFIX)));
    command.env("MS_LLVM_TOOLS", root.join("tools"));
    command
}

fn success(result: Output) -> String {
    let stderr = String::from_utf8_lossy(&result.stderr).into_owned();
    assert!(result.status.success(), "{:?}: {stderr}", result.status);
    stderr
}

fn check(root: &Path, profile: &str) -> Vec<u8> {
    let output = root.join(format!("program{}", std::env::consts::EXE_SUFFIX));
    assert_eq!(Command::new(&output).status().unwrap().code(), Some(5));
    let metadata = PathBuf::from(format!("{}.ms-build.json", output.display()));
    let document = ms_json::parse(std::fs::read(metadata).unwrap()).unwrap();
    assert_eq!(document.get("backend").unwrap().as_str(), Some("llvm"));
    assert_eq!(document.get("build_type").unwrap().as_str(), Some(profile));
    assert_eq!(document.get("format").unwrap().as_i64(), Some(1));
    std::fs::read(output).unwrap()
}

#[test]
fn sidecar_backend_matches_native_codegen_on_cold_and_repeated_builds() {
    for (name, profile) in [
        ("debug", "Debug"),
        ("release", "Release"),
        ("size", "MinSizeRel"),
    ] {
        let root = common::scratch(&format!("backend-{name}"));
        std::fs::write(root.join("main.ms"), include_str!("build_backend/main.ms")).unwrap();
        if let Some(tools) = tools() {
            common::symlink_dir(tools, &root.join("tools")).unwrap();
        }
        assert!(success(command(&root, profile).output().unwrap()).contains("ms-timings: codegen"));
        let cold = check(&root, profile);
        let output = root.join(format!("program{}", std::env::consts::EXE_SUFFIX));
        std::fs::remove_file(&output).unwrap();
        std::fs::write(
            format!("{}.ms-build.json", output.display()),
            b"stale metadata",
        )
        .unwrap();
        assert!(success(command(&root, profile).output().unwrap()).contains("ms-timings: codegen"));
        assert_eq!(check(&root, profile), cold);
        // Compilation failure must preserve the last successful executable and sidecar.
        let metadata = PathBuf::from(format!("{}.ms-build.json", output.display()));
        let prior_metadata = std::fs::read(&metadata).unwrap();
        std::fs::write(
            root.join("main.ms"),
            include_str!("build_backend/invalid.ms"),
        )
        .unwrap();
        assert!(!command(&root, profile).output().unwrap().status.success());
        assert_eq!(std::fs::read(metadata).unwrap(), prior_metadata);
        assert_eq!(std::fs::read(output).unwrap(), cold);
        std::fs::remove_dir_all(root).unwrap();
    }
}
