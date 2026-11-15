#![cfg(unix)]
//! `ms profile` end to end with a fake build function: the "executable" is a
//! shell script that writes folded stacks to `$MS_PROFILE`.

// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_rt as _;
use std::os::unix::fs::PermissionsExt;

use ms_cli::backend::{BackendResult, BuildRequest, Io};
use ms_cli::invocation::{parse_invocation, validate};

fn script_build(request: &BuildRequest, _io: &mut Io) -> BackendResult {
    let script = "#!/bin/sh\nprintf '# hz=99\\nmain;work 30\\nmain;io 10\\n' > \"$MS_PROFILE\"\nif [ -n \"$MS_PROFILE_ALLOCS\" ]; then\nprintf 'main;work;[runtime] 256\\nmain;io 128\\n# period 128\\n' > \"$MS_PROFILE_ALLOCS\"\nprintf 'main;work;[runtime] 8192\\nmain;io 128\\n# period 128\\n' > \"$MS_PROFILE_ALLOCS.bytes\"\nfi\necho hello \"$@\"\nexit 3\n";
    std::fs::write(&request.output, script).unwrap();
    std::fs::set_permissions(&request.output, std::fs::Permissions::from_mode(0o755)).unwrap();
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

#[test]
fn allocations_are_opt_in_and_name_the_allocating_function() {
    let dir = std::env::temp_dir().join(format!("ms-profile-allocs-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = dir.join("main.ms");
    std::fs::write(&source, "fn main() Int { return 0 }\n").unwrap();

    let plain = dir.join("plain");
    ms(&[
        "profile",
        source.to_str().unwrap(),
        "--out-dir",
        plain.to_str().unwrap(),
    ]);
    assert!(
        !plain.join("allocs.folded").exists(),
        "off unless asked for"
    );

    let out = dir.join("capture");
    let (status, stdout, _) = ms(&[
        "profile",
        source.to_str().unwrap(),
        "--out-dir",
        out.to_str().unwrap(),
        "--allocs",
    ]);
    assert_eq!(status, 3);
    // `[runtime];main;work` allocates through the runtime: the owner is `work`, not `[runtime]`.
    let report = std::fs::read_to_string(out.join("allocs.txt")).unwrap();
    assert!(report.contains("about 384 (8320 bytes)"), "{report}");
    let work = report.lines().find(|l| l.ends_with("work")).unwrap();
    assert!(work.contains("256") && work.contains("8192"), "{work}");
    assert!(
        stdout.contains("Allocations on the main thread"),
        "{stdout}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

/// With the allocation-profiling runtime (release builds, the scheduled run) a real program's
/// allocations are attributed to the Manuscript function that makes them (`words` is inlined into `main`); without it `--allocs` says why.
#[cfg(target_os = "linux")]
#[test]
fn allocs_with_the_real_runtime() {
    let dir = std::env::temp_dir().join(format!("ms-profile-real-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = dir.join("main.ms");
    std::fs::write(&source, include_str!("profile/words.ms")).unwrap();
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
    if cfg!(ms_allocs_runtime) {
        let report = std::fs::read_to_string(out.join("allocs.txt")).unwrap_or_default();
        assert!(
            output.status.success()
                && report
                    .lines()
                    .any(|l| l.ends_with("main") && l.contains("100.00%")),
            "{stderr}\n{report}"
        );
    } else {
        assert!(
            stderr.contains("without the allocation-profiling runtime"),
            "{stderr}"
        );
    }
    let _ = std::fs::remove_dir_all(&dir);
}
