//! Descriptor writes report actual OS failures, including automatic and repeated drains.
use std::process::Command;

#[test]
fn descriptor_write_failures_reach_source_results() {
    let file = format!(
        "{}/tests/descriptor_errors/main.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    for profile in ["Debug", "Release"] {
        let output = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(["run", &file, "--build-type", profile])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{profile}: {}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr),
        );
        assert_eq!(output.stdout, b"descriptor errors preserved\n");
    }
}
