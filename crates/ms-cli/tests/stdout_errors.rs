//! A write to a standard output that cannot take data is reported, not dropped (`flush` fails,
//! and a program that would exit 0 exits 1), on every platform: the output is a read-only file.
use std::process::{Command, Stdio};

#[test]
fn failed_standard_output_writes_are_reported() {
    let dir = std::env::temp_dir().join(format!("ms-stdout-errors-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let source = format!("{}/tests/stdout_errors/main.ms", env!("CARGO_MANIFEST_DIR"));
    let program = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["build", &source, "-o"])
        .arg(&program)
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );

    // A file opened for reading refuses every write.
    let refused = dir.join("refused.txt");
    std::fs::write(&refused, b"").unwrap();
    let output = Command::new(&program)
        .stdout(Stdio::from(std::fs::File::open(&refused).unwrap()))
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("flush failed"),
        "flush returned success: {stderr}"
    );
    assert!(
        stderr.contains("error: write to standard output"),
        "exit message missing: {stderr}"
    );
    assert_eq!(output.status.code(), Some(1), "{stderr}");

    // A working output is unchanged: the text arrives and the status is 0.
    let output = Command::new(&program).output().unwrap();
    assert_eq!(output.stdout, b"hello\n");
    assert_eq!(output.status.code(), Some(0));
    std::fs::remove_dir_all(&dir).unwrap();
}
