//! `extern fn` binds a native symbol named after the function; `--link` supplies the object that
//! defines it, and the Manuscript ABI (scalars, borrowed strings in, owned strings out) holds.

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
    let manifest = env!("CARGO_MANIFEST_DIR");
    let object = std::env::temp_dir().join(format!("ms-extern-greet-{}.o", std::process::id()));
    let status = Command::new("cc")
        .args(["-c", "-O1", "-I"])
        .arg(format!("{manifest}/../ms-rt-abi/include"))
        .arg(format!("{manifest}/tests/extern_link/greet.c"))
        .arg("-o")
        .arg(&object)
        .status()
        .expect("a C compiler (cc) builds the test shim");
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
        "42\n6\nfalse true\nhello, world\nhello, a considerably longer visitor name\n"
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
