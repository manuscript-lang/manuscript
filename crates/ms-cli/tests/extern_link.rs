//! `extern fn` binds a native symbol named after the function; `--link` supplies the object that
//! defines it, and the `ms_abi.h` conventions hold on both backends.

use std::path::PathBuf;
use std::process::Command;

fn text(out: &std::process::Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    )
}

fn compile_shim() -> PathBuf {
    compile("greet")
}

/// Compiles `tests/extern_link/<name>.c` against `ms_abi.h`.
fn compile(name: &str) -> PathBuf {
    let manifest = env!("CARGO_MANIFEST_DIR");
    // Unique per call: tests in one process may compile the same shim at once.
    static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let object =
        std::env::temp_dir().join(format!("ms-extern-{name}-{}-{n}.o", std::process::id()));
    // CI sets CC where the default `cc` is not the host architecture (Windows on arm64).
    let cc = std::env::var("CC").unwrap_or_else(|_| "cc".into());
    let status = Command::new(&cc)
        .args(["-c", "-O1", "-I"])
        .arg(format!("{manifest}/../ms-rt-abi/include"))
        .arg(format!("{manifest}/tests/extern_link/{name}.c"))
        .arg("-o")
        .arg(&object)
        .status()
        .expect("a C compiler ($CC or cc) builds the test shim");
    assert!(status.success());
    object
}

#[test]
fn linked_natives_follow_the_manuscript_abi() {
    let object = compile_shim();
    let file = format!("{}/tests/extern_link/main.ms", env!("CARGO_MANIFEST_DIR"));
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["run", &file, "--link"])
        .arg(&object)
        .output()
        .unwrap();
    let _ = std::fs::remove_file(&object);
    assert_eq!(
        text(&out),
        "42\n6\nfalse true\nhello, world\nhello, a considerably longer visitor name\nok 3 error divide by zero\nQUIET|error divide by zero|error overflow\ntrue true\n"
    );
}

#[test]
fn a_missing_link_input_is_named() {
    let file = format!("{}/tests/extern_link/main.ms", env!("CARGO_MANIFEST_DIR"));
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["build", &file, "--link", "/nonexistent/greet.o", "-o"])
        .arg(std::env::temp_dir().join("ms-extern-missing"))
        .output()
        .unwrap();
    assert_ne!(out.status.code(), Some(0));
    assert!(text(&out).contains("--link /nonexistent/greet.o does not name a file"));
}

/// Runs `abi.ms` linked with `abi.c` in `mode`, built at `build_type`.
fn run_abi(object: &PathBuf, build_type: &str, mode: &str) -> (Option<i32>, String) {
    let file = format!("{}/tests/extern_link/abi.ms", env!("CARGO_MANIFEST_DIR"));
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["run", &file, "--build-type", build_type, "--link"])
        .arg(object)
        .args(["--", mode])
        .output()
        .unwrap();
    (out.status.code(), text(&out))
}

#[test]
fn every_signature_type_round_trips_on_both_backends() {
    let object = compile("abi");
    for build_type in ["Debug", "Release"] {
        let (code, out) = run_abi(&object, build_type, "all");
        assert_eq!(code, Some(0), "{build_type}: {out}");
        assert_eq!(
            out,
            "127 32767 2147483647 0 0 0 0\n\
             1.5 false 4295033084\n\
             cba 5 -1\n\
             [2, -4, 2000000000] 555 [HI!, THERE!]\n\
             total 12\n\
             drops 2\n\
             ok 43 error failed at 1: not a digit error empty error unknown 7\n\
             drops 3\n\
             fine []\n\
             19\n\
             ab -3 true 2.5 2\n\
             fired 41\n\
             fired 42\n\
             drops 4\n",
            "{build_type}"
        );
        for (mode, fault) in [
            (
                "overflow",
                "ms_list_push value 300 is out of range for a List[UInt8]",
            ),
            (
                "null",
                "extern fn abi_null returned a NULL object; return the result of ms_object_new",
            ),
            (
                "status",
                "extern fn abi_bad_status returned a status that names no case of ParseError",
            ),
            ("fault", "the shim gave up"),
            (
                "callkind",
                "ms_call received MS_STRING for parameter 1 of type Int",
            ),
            ("callfault", "the shim gave up"),
        ] {
            let (code, out) = run_abi(&object, build_type, mode);
            assert_eq!(code, Some(67), "{build_type} {mode}: {out}");
            assert!(out.contains(fault), "{build_type} {mode}: {out}");
        }
    }
    let _ = std::fs::remove_file(&object);
}

/// A shim blocked in C returns when a stop hook runs, and the program then stops with 130.
/// Unix only, like the other signal tests (`shutdown.rs`); `run_stop_hooks` is covered on every
/// platform by the runtime's unit tests.
#[cfg(unix)]
#[test]
fn a_stop_hook_ends_a_blocked_shim() {
    use std::io::{BufRead, BufReader};
    use std::process::Stdio;
    let object = compile("abi");
    let file = format!("{}/tests/extern_link/abi.ms", env!("CARGO_MANIFEST_DIR"));
    let exe = object.with_extension("stop");
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["build", &file, "--link"])
        .arg(&object)
        .arg("-o")
        .arg(&exe)
        .output()
        .unwrap();
    assert!(built.status.success(), "{}", text(&built));
    let mut child = Command::new(&exe)
        .arg("stop")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    // Lines arrive through a channel so a shim that never returns fails the test, not hangs it.
    let (tx, lines) = std::sync::mpsc::channel();
    let stdout = child.stdout.take().unwrap();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            let _ = tx.send(line);
        }
    });
    let wait = std::time::Duration::from_secs(20);
    let next = |what: &str| {
        lines
            .recv_timeout(wait)
            .unwrap_or_else(|_| panic!("no {what} line within {wait:?}"))
    };
    let ready = next("ready");
    let sent = Command::new("kill")
        .args(["-INT", &child.id().to_string()])
        .status()
        .unwrap();
    assert!(sent.success());
    let after = lines.recv_timeout(wait);
    if after.is_err() {
        let _ = child.kill();
    }
    let status = child.wait().unwrap();
    assert_eq!(ready, "ready");
    assert_eq!(after.as_deref(), Ok("hooks 1"));
    assert_eq!(status.code(), Some(130));
    let _ = std::fs::remove_file(&exe);
    let _ = std::fs::remove_file(&object);
}
