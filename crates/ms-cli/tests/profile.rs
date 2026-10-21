#![cfg(unix)]
//! `ms profile` end to end with a fake build engine: the "executable" is a
//! shell script that writes folded stacks to `$MS_PROFILE`.

// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_rt as _;
use std::os::unix::fs::PermissionsExt;

use ms_cli::backend::{Backend, BackendResult, BuildRequest, Io};

struct ScriptBuild;

impl Backend for ScriptBuild {
    fn build(&self, request: &BuildRequest, _io: &mut Io) -> BackendResult {
        let script = "#!/bin/sh\nprintf '# hz=99\\nmain;work 30\\nmain;io 10\\n' > \"$MS_PROFILE\"\necho hello \"$@\"\nexit 3\n";
        std::fs::write(&request.output, script).unwrap();
        std::fs::set_permissions(&request.output, std::fs::Permissions::from_mode(0o755)).unwrap();
        Ok(0)
    }
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
        ms_cli::run(&args, &ScriptBuild, &mut io)
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
