//! Native inputs survive both executable and metadata publication, including cache restores.

mod common;

use std::io::Read as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::OnceLock;

#[derive(Clone, Copy, Debug)]
enum Input {
    Link,
    Runtime,
    Helper,
}

impl Input {
    fn write(self, path: &Path) -> Vec<u8> {
        static RUNTIME: OnceLock<Vec<u8>> = OnceLock::new();
        let bytes = match self {
            Self::Link => b"!<arch>\n".to_vec(),
            Self::Runtime => RUNTIME
                .get_or_init(|| {
                    let mut bytes = Vec::new();
                    flate2::read::GzDecoder::new(
                        include_bytes!(concat!(env!("OUT_DIR"), "/libms_native.a.gz")).as_slice(),
                    )
                    .read_to_end(&mut bytes)
                    .unwrap();
                    bytes
                })
                .clone(),
            Self::Helper => include_bytes!("native_input_publication/helper.ll").to_vec(),
        };
        std::fs::write(path, &bytes).unwrap();
        bytes
    }

    fn build(self, source: &Path, native: &Path, output: &Path) -> Output {
        let mut command = Command::new(env!("CARGO_BIN_EXE_ms"));
        command
            .env("MS_CACHE", "on")
            .env("MS_TIMINGS", "1")
            .env_remove("MS_RT_LIB")
            .env_remove("MS_RT_HOT")
            .args([
                "build",
                source.to_str().unwrap(),
                "--build-type",
                if matches!(self, Self::Helper) {
                    "Release"
                } else {
                    "Debug"
                },
            ])
            .arg("--json")
            .arg("-o")
            .arg(output);
        match self {
            Self::Link => {
                command.arg("--link").arg(native);
            }
            Self::Runtime => {
                command.env("MS_RT_LIB", native);
            }
            Self::Helper => {
                command.env("MS_RT_HOT", native);
                if let Some(tools) = helper_tools() {
                    command
                        .env("MS_LLVM_TOOLS", tools)
                        .env("MS_BACKEND", "llvm");
                } else {
                    command.env("MS_BACKEND", "cranelift");
                }
            }
        }
        command.output().unwrap()
    }
}

fn success(result: &Output) {
    assert!(
        result.status.success(),
        "{}{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
}

fn fixture(name: &str) -> (PathBuf, PathBuf) {
    let dir = common::scratch(name);
    let source = dir.join("main.ms");
    std::fs::write(&source, include_str!("native_input_publication/main.ms")).unwrap();
    (dir, source)
}

fn preserves_native_input(kind: Input, metadata: bool) {
    for warm in [false, true] {
        let (dir, source) = fixture(&format!("native-input-{kind:?}-{metadata}-{warm}"));
        let inputs = dir.join("inputs");
        let safe = dir.join("safe");
        std::fs::create_dir(&inputs).unwrap();
        std::fs::create_dir(&safe).unwrap();
        let native = inputs.join(if metadata {
            "program.ms-build.json"
        } else {
            "program"
        });
        let original = kind.write(&native);
        let other = inputs.join(if metadata {
            "program"
        } else {
            "program.ms-build.json"
        });
        std::fs::write(&other, b"previous artifact").unwrap();
        let output = if warm {
            let alias = dir.join("publish");
            common::symlink_dir(&safe, &alias).unwrap();
            let output = alias.join("program");
            success(&kind.build(&source, &native, &output));
            assert_eq!(
                Command::new(&output).status().unwrap().code(),
                Some(expected_exit(kind))
            );
            let hit = kind.build(&source, &native, &output);
            success(&hit);
            assert!(
                !String::from_utf8_lossy(&hit.stderr).contains("ms-timings:"),
                "the unchanged control must restore its cache"
            );
            // Retargeting a directory changes the publication entry, not any input stamp.
            std::fs::remove_dir(&alias)
                .or_else(|_| std::fs::remove_file(&alias))
                .unwrap();
            common::symlink_dir(&inputs, &alias).unwrap();
            output
        } else {
            inputs.join("program")
        };
        let result = kind.build(&source, &native, &output);
        assert!(!result.status.success());
        let stderr = String::from_utf8_lossy(&result.stderr);
        let artifact = if metadata {
            "build metadata"
        } else {
            "executable"
        };
        assert!(
            stderr.contains(&format!("{artifact} would overwrite")),
            "{stderr}"
        );
        assert_eq!(std::fs::read(&native).unwrap(), original);
        assert_eq!(std::fs::read(&other).unwrap(), b"previous artifact");
        let document = ms_json::parse(String::from_utf8(result.stdout).unwrap()).unwrap();
        assert_eq!(document.get("completed").unwrap().as_bool(), Some(false));
    }
}

#[test]
fn executable_preserves_link_inputs_on_cold_and_warm_builds() {
    preserves_native_input(Input::Link, false);
}

#[test]
fn metadata_preserves_link_inputs_on_cold_and_warm_builds() {
    preserves_native_input(Input::Link, true);
}

#[test]
fn executable_preserves_runtime_inputs_on_cold_and_warm_builds() {
    preserves_native_input(Input::Runtime, false);
}

#[test]
fn metadata_preserves_runtime_inputs_on_cold_and_warm_builds() {
    preserves_native_input(Input::Runtime, true);
}

#[test]
fn executable_preserves_helper_inputs_on_cold_and_warm_builds() {
    preserves_native_input(Input::Helper, false);
}

#[test]
fn metadata_preserves_helper_inputs_on_cold_and_warm_builds() {
    preserves_native_input(Input::Helper, true);
}

#[test]
fn distinct_metadata_links_to_native_inputs_remain_safe() {
    for kind in [Input::Link, Input::Runtime, Input::Helper] {
        for warm in [false, true] {
            let (dir, source) = fixture(&format!("native-metadata-link-{kind:?}-{warm}"));
            let native = dir.join("input");
            let original = kind.write(&native);
            let output = dir.join("program");
            let metadata = dir.join("program.ms-build.json");
            if warm {
                success(&kind.build(&source, &native, &output));
                std::fs::remove_file(&metadata).unwrap();
            }
            common::symlink_file(&native, &metadata).unwrap();
            success(&kind.build(&source, &native, &output));
            assert_eq!(std::fs::read(&native).unwrap(), original);
            assert!(
                !std::fs::symlink_metadata(&metadata)
                    .unwrap()
                    .file_type()
                    .is_symlink()
            );
            assert!(ms_json::parse(std::fs::read_to_string(&metadata).unwrap()).is_ok());
            assert_eq!(
                Command::new(&output).status().unwrap().code(),
                Some(expected_exit(kind))
            );
        }
    }
}

// Resolve once so the child build and its expected result use the same backend even if a
// failed initial tool fetch could succeed on a later attempt. Every platform runs the cases.
fn helper_tools() -> Option<&'static Path> {
    static TOOLS: OnceLock<Option<PathBuf>> = OnceLock::new();
    TOOLS
        .get_or_init(|| {
            ms_clif::link::llvm_tools(&ms_cli::engine::build_options_from_env()).unwrap()
        })
        .as_deref()
}

fn expected_exit(kind: Input) -> i32 {
    if matches!(kind, Input::Helper) && helper_tools().is_some() {
        47
    } else {
        5
    }
}

#[test]
fn release_helper_control_proves_backend_consumption() {
    let (dir, source) = fixture("native-helper-consumption");
    let helper = dir.join("helper.ll");
    Input::Helper.write(&helper);
    let output = dir.join("program");
    success(&Input::Helper.build(&source, &helper, &output));
    assert_eq!(
        Command::new(&output).status().unwrap().code(),
        Some(expected_exit(Input::Helper))
    );
    let baseline = Command::new(env!("CARGO_BIN_EXE_ms"))
        .env("MS_CACHE", "off")
        .env("MS_BACKEND", "cranelift")
        .env("MS_RT_HOT", &helper)
        .env_remove("MS_RT_LIB")
        .args([
            "build",
            source.to_str().unwrap(),
            "--build-type",
            "Release",
            "-o",
        ])
        .arg(&output)
        .output()
        .unwrap();
    success(&baseline);
    assert_eq!(Command::new(&output).status().unwrap().code(), Some(5));
}
