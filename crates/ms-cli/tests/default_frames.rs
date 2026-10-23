//! Omitted defaults retain their lexical frames even when lowered into a caller.
use std::process::Command;

#[test]
fn nested_default_fault_retains_each_callee_and_caller() {
    check_frames(
        "nested.ms",
        "  at nested.ms:1 in divide\n  at nested.ms:4 in outer\n  at nested.ms:8 in main\n",
    );
}

#[test]
fn imported_default_fault_retains_the_declaration_file() {
    check_frames(
        "imported.ms",
        "  at library.ms:1 in divide\n  at imported.ms:4 in main\n",
    );
}

#[test]
fn method_default_fault_names_the_receiver_type() {
    check_frames(
        "method.ms",
        "  at method.ms:8 in Number.divide\n  at method.ms:12 in main\n",
    );
}

fn check_frames(file: &str, frames: &str) {
    let fixture = format!("{}/tests/default_frames/{file}", env!("CARGO_MANIFEST_DIR"));
    for build_type in ["Debug", "Release"] {
        let out = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(["run", &fixture, "--build-type", build_type])
            .output()
            .unwrap();
        assert_eq!(out.status.code(), Some(70));
        assert_eq!(
            String::from_utf8_lossy(&out.stderr),
            format!("Int./: division by zero; right must be nonzero, found 0\n{frames}")
        );
    }
}
