//! Publication protects the runtime actually selected by the Engine, including embedded archives.

use crate::common;

// Links the runtime symbols referenced by the standard-library crates.
use ms_rt as _;

use std::cell::Cell;
use std::io::Read as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::OnceLock;

use ms_build::{Lower, Module, Native};
use ms_cli::backend::Io;
use ms_cli::engine::Engine;

struct Fixture(PathBuf);

impl Fixture {
    fn new(name: &str) -> Self {
        let root = common::scratch(name);
        std::fs::write(
            root.join("main.ms"),
            include_str!("runtime_input_publication/main.ms"),
        )
        .unwrap();
        Self(root)
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        // Runtime archives are large; also release each failed disposable case before the next.
        let _ = std::fs::remove_dir_all(&self.0);
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

fn exits_seven(output: &Path) {
    assert_eq!(Command::new(output).status().unwrap().code(), Some(7));
}

fn success(result: &Output) {
    assert!(
        result.status.success(),
        "{}{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
}

fn rejected(status: i32, stdout: &str, stderr: &str, metadata: bool) {
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
    let document = ms_json::parse(stdout).unwrap();
    assert_eq!(document.get("completed").unwrap().as_bool(), Some(false));
}

fn embedded_build(source: &Path, output: &Path, cache: &Path) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .env("XDG_CACHE_HOME", cache)
        .env("MS_CACHE", "on")
        .env("MS_TIMINGS", "1")
        .env_remove("MS_RT_LIB")
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

fn retarget(alias: &Path, directory: &Path) {
    std::fs::remove_dir(alias)
        .or_else(|_| std::fs::remove_file(alias))
        .unwrap();
    common::symlink_dir(directory, alias).unwrap();
}

fn preserves_embedded(metadata: bool, warm: bool) {
    let fixture = Fixture::new(&format!("embedded-runtime-{metadata}-{warm}"));
    let root = &fixture.0;
    let source = root.join("main.ms");
    let cache = root.join("cache");
    let native = cache
        .join("ms/native")
        .join(env!("MS_NATIVE_ID"))
        .join("libms_native.a");
    std::fs::create_dir_all(native.parent().unwrap()).unwrap();
    let inputs = if metadata {
        root.join("inputs")
    } else {
        native.parent().unwrap().to_path_buf()
    };
    std::fs::create_dir_all(&inputs).unwrap();
    let safe = root.join("safe");
    std::fs::create_dir(&safe).unwrap();
    let basename = if metadata {
        "program"
    } else {
        "libms_native.a"
    };
    // A valid extraction-cache symlink lets the embedded runtime resolve to metadata's basename.
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
    let control = safe.join("control");
    success(&embedded_build(&source, &control, &cache));
    exits_seven(&control);
    eprintln!("embedded metadata={metadata} warm={warm}: native control exited 7");
    let output = if warm {
        let alias = root.join("publish");
        common::symlink_dir(&safe, &alias).unwrap();
        let output = alias.join(basename);
        success(&embedded_build(&source, &output, &cache));
        let hit = embedded_build(&source, &output, &cache);
        success(&hit);
        assert!(
            !String::from_utf8_lossy(&hit.stderr).contains("ms-timings:"),
            "control must restore its cache"
        );
        exits_seven(&output);
        eprintln!("embedded metadata={metadata} warm={warm}: cache hit confirmed before retarget");
        retarget(&alias, &inputs);
        output
    } else {
        inputs.join(basename)
    };
    let result = embedded_build(&source, &output, &cache);
    let after = std::fs::read(&target).unwrap();
    let changed = after != archive();
    let companion_changed = std::fs::read(&other).unwrap() != b"previous artifact";
    // Keep bounded red evidence even though Fixture removes the large archive after failure.
    eprintln!(
        "embedded metadata={metadata} warm={warm}: status={:?}, input_changed={changed}, previous_artifact_changed={companion_changed}, input_bytes={}, first_bytes={:02x?}",
        result.status.code(),
        after.len(),
        &after[..after.len().min(8)]
    );
    rejected(
        result.status.code().unwrap(),
        &String::from_utf8(result.stdout).unwrap(),
        &String::from_utf8(result.stderr).unwrap(),
        metadata,
    );
    assert!(!changed, "selected embedded runtime bytes changed");
    assert!(!companion_changed, "prior companion artifact changed");
    assert_eq!(std::fs::read(&native).unwrap(), archive());
}

#[test]
fn embedded_runtime_survives_executable_publication_on_cold_builds() {
    preserves_embedded(false, false);
}
#[test]
fn embedded_runtime_survives_executable_publication_on_warm_builds() {
    preserves_embedded(false, true);
}
#[test]
fn embedded_runtime_survives_metadata_publication_on_cold_builds() {
    preserves_embedded(true, false);
}
#[test]
fn embedded_runtime_survives_metadata_publication_on_warm_builds() {
    preserves_embedded(true, true);
}

struct Counted(Cell<usize>);
impl Lower for Counted {
    fn lower(&self, program: &ms_check::Program, entry: &str) -> Result<Module, String> {
        self.0.set(self.0.get() + 1);
        Native.lower(program, entry)
    }
}

fn engine_build(backend: &Engine<Counted>, source: &Path, output: &Path) -> (i32, String, String) {
    let args: Vec<_> = [
        "build",
        source.to_str().unwrap(),
        "--build-type",
        "Debug",
        "--json",
        "-o",
        output.to_str().unwrap(),
    ]
    .into_iter()
    .map(String::from)
    .collect();
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

fn engine_success((status, stdout, stderr): (i32, String, String)) {
    assert_eq!(status, 0, "{stdout}{stderr}");
}

fn selection_child(
    root: &Path,
    selected_target: bool,
    metadata: bool,
    warm: bool,
    missing_ignored: bool,
) {
    let source = root.join("main.ms");
    let native = root.join("selected-runtime.a");
    let inputs = root.join("inputs");
    let target = inputs.join(if metadata {
        "program.ms-build.json"
    } else {
        "program"
    });
    let selected = if selected_target { &target } else { &native };
    let backend = Engine::new(Counted(Cell::new(0))).with_runtime(selected);
    let control = root.join("safe/control");
    engine_success(engine_build(&backend, &source, &control));
    exits_seven(&control);
    let before = backend.lowering.0.get();
    engine_success(engine_build(&backend, &source, &control));
    assert_eq!(
        backend.lowering.0.get(),
        before,
        "an ignored runtime path must not disable caching"
    );
    assert!(
        std::fs::read_dir(root.join(".ms-cache/build"))
            .unwrap()
            .any(|entry| entry.unwrap().path().join("manifest").is_file()),
        "the control must record a native cache entry"
    );
    eprintln!(
        "selected_target={selected_target}, metadata={metadata}, warm={warm}, missing_ignored={missing_ignored}: repeated native control restored its cache"
    );

    eprintln!(
        "selected_target={selected_target}, metadata={metadata}, warm={warm}: native control exited 7"
    );
    let output = root.join("publish/program");
    if warm {
        engine_success(engine_build(&backend, &source, &output));
        let before = backend.lowering.0.get();
        engine_success(engine_build(&backend, &source, &output));
        assert_eq!(
            backend.lowering.0.get(),
            before,
            "control must restore its cache without lowering"
        );
        eprintln!(
            "selected_target={selected_target}, metadata={metadata}, warm={warm}: cache hit confirmed before retarget"
        );
        retarget(&root.join("publish"), &inputs);
    }
    let result = engine_build(&backend, &source, &output);
    if selected_target {
        rejected(result.0, &result.1, &result.2, metadata);
        assert!(
            std::fs::read(selected).unwrap() == archive(),
            "selected Engine runtime bytes changed"
        );
        let other = inputs.join(if metadata {
            "program"
        } else {
            "program.ms-build.json"
        });
        assert_eq!(std::fs::read(other).unwrap(), b"previous artifact");
    } else {
        engine_success(result);
        exits_seven(&output);
        assert!(
            std::fs::read(selected).unwrap() == archive(),
            "selected Engine runtime bytes changed"
        );
        if metadata {
            assert!(ms_json::parse(std::fs::read_to_string(&target).unwrap()).is_ok());
        } else {
            exits_seven(&target);
        }
    }
}

#[test]
fn engine_runtime_precedence_protects_only_the_selected_archive() {
    const CHILD: &str = "MS_TEST_RUNTIME_SELECTION_ROOT";
    if let Some(root) = std::env::var_os(CHILD) {
        let flags = std::env::var("MS_TEST_RUNTIME_SELECTION_FLAGS").unwrap();
        let values: Vec<_> = flags.split(',').map(|flag| flag == "true").collect();
        selection_child(Path::new(&root), values[0], values[1], values[2], values[3]);
        return;
    }
    let mut failures = Vec::new();
    for selected_target in [true, false] {
        for metadata in [false, true] {
            for warm in [false, true] {
                for missing_ignored in [false, true] {
                    let fixture = Fixture::new(&format!(
                        "selected-runtime-{selected_target}-{metadata}-{warm}-{missing_ignored}"
                    ));
                    let root = &fixture.0;
                    let inputs = root.join("inputs");
                    let safe = root.join("safe");
                    std::fs::create_dir(&inputs).unwrap();
                    std::fs::create_dir(&safe).unwrap();
                    let target = inputs.join(if metadata {
                        "program.ms-build.json"
                    } else {
                        "program"
                    });
                    let selected = if selected_target {
                        target.clone()
                    } else {
                        root.join("selected-runtime.a")
                    };
                    let ignored = if selected_target {
                        root.join("ignored-runtime.a")
                    } else {
                        target
                    };
                    std::fs::write(&selected, archive()).unwrap();
                    // An overridden environment runtime is not consumed, even when its bytes are invalid.
                    if !missing_ignored {
                        std::fs::write(&ignored, b"unused environment runtime").unwrap();
                    }
                    if selected_target {
                        std::fs::write(
                            inputs.join(if metadata {
                                "program"
                            } else {
                                "program.ms-build.json"
                            }),
                            b"previous artifact",
                        )
                        .unwrap();
                    }
                    common::symlink_dir(if warm { &safe } else { &inputs }, &root.join("publish"))
                        .unwrap();
                    let result = Command::new(std::env::current_exe().unwrap())
                        .args([
                            "--exact",
                            "runtime_input_publication::engine_runtime_precedence_protects_only_the_selected_archive",
                            "--nocapture",
                        ])
                        .env(CHILD, root)
                        .env(
                            "MS_TEST_RUNTIME_SELECTION_FLAGS",
                            format!("{selected_target},{metadata},{warm},{missing_ignored}"),
                        )
                        .env("MS_RT_LIB", ignored)
                        .env("MS_CACHE", "on")
                        .output()
                        .unwrap();
                    eprintln!(
                        "selected_target={selected_target}, metadata={metadata}, warm={warm}, missing_ignored={missing_ignored}: {:?}",
                        result.status.code()
                    );
                    eprint!("{}", String::from_utf8_lossy(&result.stderr));
                    if !result.status.success() {
                        failures.push(format!(
                        "selected_target={selected_target}, metadata={metadata}, warm={warm}, missing_ignored={missing_ignored}: {}{}",
                        String::from_utf8_lossy(&result.stdout),
                        String::from_utf8_lossy(&result.stderr)
                    ));
                    }
                }
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
