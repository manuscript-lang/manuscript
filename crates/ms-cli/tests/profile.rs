//! `ms profile` end to end. Most tests use a fake build function whose "executable" is a copy of
//! one real Manuscript program (`profile/spin.ms`, built once with the CLI), so they need no
//! shell and run on every platform.

use std::path::PathBuf;
use std::sync::OnceLock;

use ms_cli::backend::{BackendResult, BuildRequest, Io};
use ms_cli::invocation::{parse_invocation, validate};

/// The compiled `profile/spin.ms`: it burns CPU in `work`, prints its arguments and exits with
/// status 3.
fn spin_program() -> &'static PathBuf {
    static PROGRAM: OnceLock<PathBuf> = OnceLock::new();
    PROGRAM.get_or_init(|| {
        let dir = std::env::temp_dir().join(format!("ms-profile-spin-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let source = format!("{}/tests/profile/spin.ms", env!("CARGO_MANIFEST_DIR"));
        let out = dir.join(if cfg!(windows) { "spin.exe" } else { "spin" });
        let built = std::process::Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(["build", "--build-type", "debug", &source, "-o"])
            .arg(&out)
            .output()
            .unwrap();
        assert!(
            built.status.success(),
            "{}{}",
            String::from_utf8_lossy(&built.stdout),
            String::from_utf8_lossy(&built.stderr)
        );
        out
    })
}

fn script_build(request: &BuildRequest, _io: &mut Io) -> BackendResult {
    std::fs::copy(spin_program(), &request.output).unwrap();
    Ok(0)
}

/// `Err` carries the status of an invocation that was rejected before the profile ran.
fn profile(args: &[String], io: &mut Io) -> Result<i32, i32> {
    let mut inv = parse_invocation(args, io)?;
    let plan = validate(&mut inv, io)?;
    Ok(ms_cli::profile::run_profile(
        &inv,
        plan.build_type,
        &script_build,
        io,
    ))
}

fn ms(args: &[&str]) -> (i32, String, String) {
    let args: Vec<String> = args.iter().map(|a| a.to_string()).collect();
    let (mut out, mut err) = (Vec::new(), Vec::new());
    let status = {
        let mut input: &[u8] = &[];
        let mut io = Io {
            stdin: &mut input,
            stdout: &mut out,
            stderr: &mut err,
        };
        profile(&args, &mut io).unwrap_or_else(|status| status)
    };
    (
        status,
        String::from_utf8_lossy(&out).into_owned(),
        String::from_utf8_lossy(&err).into_owned(),
    )
}

#[test]
fn bundle_and_exit_status() {
    let dir = std::env::temp_dir().join(format!("ms-profile-test-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = dir.join("main.ms");
    std::fs::write(&source, "fn main() Int { return 0 }\n").unwrap();
    let out = dir.join("capture");
    let (status, stdout, _) = ms(&[
        "profile",
        source.to_str().unwrap(),
        "--out-dir",
        out.to_str().unwrap(),
        "--top",
        "5",
        "--",
        "a",
        "b",
    ]);
    assert_eq!(status, 3, "the program's status is returned");
    assert!(stdout.contains("main"), "report lists functions: {stdout}");
    for file in [
        "program",
        "profile.folded",
        "profile.pb",
        "top.txt",
        "manifest.json",
    ] {
        assert!(out.join(file).exists(), "{file} missing");
    }
    let top = std::fs::read_to_string(out.join("top.txt")).unwrap();
    assert!(top.contains("work"));

    // The directory must be new.
    let (status, _, stderr) = ms(&[
        "profile",
        source.to_str().unwrap(),
        "--out-dir",
        out.to_str().unwrap(),
    ]);
    assert_eq!(status, 1);
    assert!(stderr.contains("must be new"), "{stderr}");
    let _ = std::fs::remove_dir_all(&dir);
}

/// `[runtime];main;work` allocates through the runtime: the owner is `work`, not `[runtime]`.
#[test]
fn allocations_name_the_allocating_function() {
    let dir = std::env::temp_dir().join(format!("ms-profile-allocs-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let counts = dir.join("allocs");
    std::fs::write(
        &counts,
        "main;work;[runtime] 256\nmain;io 128\n# period 128\n",
    )
    .unwrap();
    std::fs::write(
        dir.join("allocs.bytes"),
        "main;work;[runtime] 8192\nmain;io 128\n# period 128\n",
    )
    .unwrap();
    let profile = ms_cli::profile::read_allocs(counts.to_str().unwrap(), 5).unwrap();
    let report = profile.render();
    assert!(report.contains("about 384 (8320 bytes)"), "{report}");
    let work = report.lines().find(|l| l.ends_with("work")).unwrap();
    assert!(work.contains("256") && work.contains("8192"), "{work}");
    let _ = std::fs::remove_dir_all(&dir);
}

/// A real program's allocations are attributed to the Manuscript function that makes them (`words`
/// is inlined into `main`).
#[test]
fn allocs_with_the_real_runtime() {
    let dir = std::env::temp_dir().join(format!("ms-profile-real-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = dir.join("main.ms");
    std::fs::write(&source, include_str!("profile/words.ms")).unwrap();
    let plain = dir.join("plain");
    let status = std::process::Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["profile", source.to_str().unwrap(), "--out-dir"])
        .arg(&plain)
        .status()
        .unwrap();
    assert!(status.success());
    // The program's start shim is not a frame of the program: no stack is rooted at `[runtime]`.
    let folded = std::fs::read_to_string(plain.join("profile.folded")).unwrap_or_default();
    assert!(
        folded.lines().all(|l| !l.starts_with("[runtime];")),
        "{folded}"
    );
    assert!(
        !plain.join("allocs.folded").exists(),
        "allocation sampling is off unless asked for"
    );
    let out = dir.join("capture");
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_ms"))
        .args([
            "profile",
            source.to_str().unwrap(),
            "--allocs",
            "--out-dir",
            out.to_str().unwrap(),
        ])
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&output.stderr);
    let report = std::fs::read_to_string(out.join("allocs.txt")).unwrap_or_default();
    assert!(
        output.status.success()
            && report
                .lines()
                .any(|l| l.ends_with("main") && l.contains("100.00%")),
        "{stderr}\n{report}\n{}",
        std::fs::read_to_string(out.join("allocs.folded")).unwrap_or_default()
    );
    let _ = std::fs::remove_dir_all(&dir);
}
