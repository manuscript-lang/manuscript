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
    let object = std::env::temp_dir().join(format!("ms-extern-{name}-{}.o", std::process::id()));
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
             fine []\n",
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
        ] {
            let (code, out) = run_abi(&object, build_type, mode);
            assert_eq!(code, Some(67), "{build_type} {mode}: {out}");
            assert!(out.contains(fault), "{build_type} {mode}: {out}");
        }
    }
    let _ = std::fs::remove_file(&object);
}
