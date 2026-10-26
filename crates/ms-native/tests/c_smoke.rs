//! Keep the Linux C driver checked against the production runtime ABI.
#![cfg(target_os = "linux")]

use std::process::Command;

#[test]
fn c_runtime_smoke_checks_all_modes() {
    let output = Command::new("sh")
        .arg(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../ms-rt/tests/e2e/run.sh"
        ))
        .output()
        .expect("run the native C smoke harness");
    assert!(
        output.status.success(),
        "status: {}\nstdout:\n{}\nstderr:\n{}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("ms-rt e2e: ok"));
}
