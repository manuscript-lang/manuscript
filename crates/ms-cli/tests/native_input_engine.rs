//! Publication protects the Engine-selected runtime and an object whose symbol is called.

mod common;

// Links the runtime symbols referenced by the standard-library crates.
use ms_rt as _;

use std::cell::Cell;
use std::io::Read as _;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

use ms_build::{Lower, Module};
use ms_cli::backend::Io;
use ms_cli::engine::Engine;

const LINK_CALLEE: &str = "module \"native-input\"\nfn @native_input_value() -> int export {\nb0:\n  %v: int = iconst 23\n  ret %v\n}\n";
const LINK_CALLER: &str = "module \"native-input\"\nentry @main\nextern @native_input_value() -> int\nfn @main() -> int {\nb0:\n  %v: int = call.rt @native_input_value()\n  ret %v\n}\n";
const EXIT_SEVEN: &str = "module \"native-input\"\nentry @main\nfn @main() -> int {\nb0:\n  %v: int = iconst 7\n  ret %v\n}\n";

struct Counted {
    mir: &'static str,
    calls: Cell<usize>,
}

impl Lower for Counted {
    fn lower(&self, _: &ms_check::Program, _: &str) -> Result<Module, String> {
        self.calls.set(self.calls.get() + 1);
        ms_mir::parse::parse_module(self.mir).map_err(|e| e.to_string())
    }
}

fn archive() -> &'static [u8] {
    static BYTES: OnceLock<Vec<u8>> = OnceLock::new();
    BYTES.get_or_init(|| {
        let mut bytes = Vec::new();
        flate2::read::GzDecoder::new(
            include_bytes!(concat!(env!("OUT_DIR"), "/libms_native.a.gz")).as_slice(),
        )
        .read_to_end(&mut bytes)
        .unwrap();
        bytes
    })
}

fn fixture(name: &str) -> (PathBuf, PathBuf) {
    let dir = common::scratch(name);
    let source = dir.join("main.ms");
    std::fs::write(&source, "export fn main() Int:\n    return 0\n").unwrap();
    (dir, source)
}

fn build(
    backend: &Engine<Counted>,
    source: &Path,
    output: &Path,
    link: Option<&Path>,
) -> (i32, String, String) {
    let mut args = vec![
        "build",
        source.to_str().unwrap(),
        "--build-type",
        "Debug",
        "--json",
        "-o",
        output.to_str().unwrap(),
    ];
    if let Some(link) = link {
        args.extend(["--link", link.to_str().unwrap()]);
    }
    let args: Vec<_> = args.into_iter().map(String::from).collect();
    let (mut stdout, mut stderr) = (Vec::new(), Vec::new());
    let mut stdin: &[u8] = &[];
    let status = ms_cli::run(
        ms_syntax::Names::global(),
        &args,
        backend,
        &mut Io {
            stdin: &mut stdin,
            stdout: &mut stdout,
            stderr: &mut stderr,
        },
    );
    (
        status,
        String::from_utf8(stdout).unwrap(),
        String::from_utf8(stderr).unwrap(),
    )
}

fn success((status, stdout, stderr): (i32, String, String)) {
    assert_eq!(status, 0, "{stdout}{stderr}");
}

fn collision((status, stdout, stderr): (i32, String, String), metadata: bool) {
    assert_ne!(status, 0, "{stdout}{stderr}");
    let artifact = if metadata {
        "build metadata"
    } else {
        "executable"
    };
    assert!(
        stderr.contains(&format!("{artifact} would overwrite")),
        "{stdout}{stderr}"
    );
    let document = ms_json::parse(&stdout).unwrap();
    assert_eq!(document.get("completed").unwrap().as_bool(), Some(false));
}

fn preserves_selected_input(link: bool, metadata: bool) {
    for warm in [false, true] {
        let (dir, source) = fixture(&format!("selected-native-{link}-{metadata}-{warm}"));
        let inputs = dir.join("inputs");
        let safe = dir.join("safe");
        std::fs::create_dir(&inputs).unwrap();
        std::fs::create_dir(&safe).unwrap();
        let native = inputs.join(if metadata {
            "program.ms-build.json"
        } else {
            "program"
        });
        let original = if link {
            let module = ms_mir::parse::parse_module(LINK_CALLEE).unwrap();
            ms_mir::verify::verify_module(&module).unwrap();
            ms_clif::compile(&module, &ms_clif::Options::default()).unwrap()
        } else {
            archive().to_vec()
        };
        std::fs::write(&native, &original).unwrap();
        let other = inputs.join(if metadata {
            "program"
        } else {
            "program.ms-build.json"
        });
        std::fs::write(&other, b"previous artifact").unwrap();
        let backend = Engine::new(Counted {
            mir: if link { LINK_CALLER } else { EXIT_SEVEN },
            calls: Cell::new(0),
        });
        let backend = if link {
            backend
        } else {
            backend.with_runtime(&native)
        };
        let link_input = link.then_some(native.as_path());
        // Even the cold collision has a distinct-output control proving this input links and runs.
        let control = safe.join("control");
        success(build(&backend, &source, &control, link_input));
        assert_eq!(
            Command::new(&control).status().unwrap().code(),
            Some(if link { 23 } else { 7 })
        );
        if link {
            let (status, stdout, stderr) =
                build(&backend, &source, &safe.join("missing-symbol"), None);
            assert_ne!(
                status, 0,
                "the caller must require its --link symbol: {stdout}{stderr}"
            );
            assert!(stderr.contains("native_input_value"), "{stdout}{stderr}");
        }
        let output = if warm {
            let alias = dir.join("publish");
            common::symlink_dir(&safe, &alias).unwrap();
            let output = alias.join("program");
            success(build(&backend, &source, &output, link_input));
            let before = backend.lowering.calls.get();
            success(build(&backend, &source, &output, link_input));
            assert_eq!(
                backend.lowering.calls.get(),
                before,
                "control must restore its cache without lowering"
            );
            std::fs::remove_dir(&alias)
                .or_else(|_| std::fs::remove_file(&alias))
                .unwrap();
            common::symlink_dir(&inputs, &alias).unwrap();
            output
        } else {
            inputs.join("program")
        };
        collision(build(&backend, &source, &output, link_input), metadata);
        assert_eq!(std::fs::read(&native).unwrap(), original);
        assert_eq!(std::fs::read(&other).unwrap(), b"previous artifact");
    }
}

#[test]
fn executable_preserves_called_link_object_on_cold_and_warm_builds() {
    preserves_selected_input(true, false);
}

#[test]
fn metadata_preserves_called_link_object_on_cold_and_warm_builds() {
    preserves_selected_input(true, true);
}

#[test]
fn executable_preserves_engine_selected_runtime_on_cold_and_warm_builds() {
    preserves_selected_input(false, false);
}

#[test]
fn metadata_preserves_engine_selected_runtime_on_cold_and_warm_builds() {
    preserves_selected_input(false, true);
}

fn embedded_build(source: &Path, output: &Path, cache: &Path) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .env("XDG_CACHE_HOME", cache)
        .env("MS_CACHE", "on")
        .env("MS_TIMINGS", "1")
        .env_remove("MS_RT_LIB")
        .env_remove("MS_RT_HOT")
        .args([
            "build",
            source.to_str().unwrap(),
            "--build-type",
            "Debug",
            "--json",
            "-o",
        ])
        .arg(output)
        .output()
        .unwrap()
}

fn preserves_embedded_runtime(metadata: bool) {
    for warm in [false, true] {
        let (dir, source) = fixture(&format!("embedded-native-{metadata}-{warm}"));
        let cache = dir.join("cache");
        let native = cache
            .join("ms/native")
            .join(env!("MS_NATIVE_ID"))
            .join("libms_native.a");
        std::fs::create_dir_all(native.parent().unwrap()).unwrap();
        let inputs = if metadata {
            dir.join("inputs")
        } else {
            native.parent().unwrap().to_path_buf()
        };
        let safe = dir.join("safe");
        std::fs::create_dir_all(&inputs).unwrap();
        std::fs::create_dir(&safe).unwrap();
        let basename = if metadata {
            "program"
        } else {
            "libms_native.a"
        };
        // The embedded basename cannot be metadata's suffix. A valid extraction-cache symlink
        // makes its selected archive resolve to that metadata entry, without altering extraction.
        let target = if metadata {
            inputs.join("program.ms-build.json")
        } else {
            native.clone()
        };
        std::fs::write(&target, archive()).unwrap();
        if metadata {
            common::symlink_file(&target, &native).unwrap();
        }
        let other = inputs.join(if metadata {
            "program"
        } else {
            "libms_native.a.ms-build.json"
        });
        std::fs::write(&other, b"previous artifact").unwrap();
        let output = if warm {
            let alias = dir.join("publish");
            common::symlink_dir(&safe, &alias).unwrap();
            let output = alias.join(basename);
            let first = embedded_build(&source, &output, &cache);
            assert!(
                first.status.success(),
                "{}",
                String::from_utf8_lossy(&first.stderr)
            );
            assert_eq!(Command::new(&output).status().unwrap().code(), Some(0));
            let hit = embedded_build(&source, &output, &cache);
            assert!(
                hit.status.success(),
                "{}",
                String::from_utf8_lossy(&hit.stderr)
            );
            assert!(
                !String::from_utf8_lossy(&hit.stderr).contains("ms-timings:"),
                "control must restore its cache"
            );
            std::fs::remove_dir(&alias)
                .or_else(|_| std::fs::remove_file(&alias))
                .unwrap();
            common::symlink_dir(&inputs, &alias).unwrap();
            output
        } else {
            inputs.join(basename)
        };
        let result = embedded_build(&source, &output, &cache);
        collision(
            (
                result.status.code().unwrap(),
                String::from_utf8(result.stdout).unwrap(),
                String::from_utf8(result.stderr).unwrap(),
            ),
            metadata,
        );
        assert_eq!(std::fs::read(&target).unwrap(), archive());
        assert_eq!(std::fs::read(&native).unwrap(), archive());
        assert_eq!(
            std::fs::symlink_metadata(&native)
                .unwrap()
                .file_type()
                .is_symlink(),
            metadata
        );
        assert_eq!(std::fs::read(&other).unwrap(), b"previous artifact");
    }
}

#[test]
fn executable_preserves_embedded_runtime_on_cold_and_warm_builds() {
    preserves_embedded_runtime(false);
}

#[test]
fn metadata_preserves_embedded_runtime_on_cold_and_warm_builds() {
    preserves_embedded_runtime(true);
}
