//! Nonescaping closures retain mutable places, including saved path operands.
use std::process::Command;

#[test]
fn mutable_alias_captures_write_through() {
    let fixture = format!(
        "{}/tests/closure_aliases/write_through.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    for build_type in ["Debug", "Release"] {
        let out = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(["run", &fixture, "--build-type", build_type])
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        assert_eq!(
            String::from_utf8_lossy(&out.stdout),
            "1 [[1, 9, 9], [2]]\n6\n[[3], [4, 8]]\nMap(dynamic-1: [5, 1])\nPair(left: [1, 3], right: [2, 4])\n[[10, 11]]\n[[3], [4, 8], [6]]\n"
        );
    }
}

#[test]
fn mutating_alias_captures_cannot_escape() {
    let fixture = format!(
        "{}/tests/closure_aliases/rejected_escape.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["check", &fixture])
        .output()
        .unwrap();
    assert!(!out.status.success());
    assert!(
        String::from_utf8_lossy(&out.stderr)
            .contains("this closure changes captured `first`, so it cannot be returned")
    );
}
