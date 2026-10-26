//! A closure read out of a temporary record outlives the record's drop (#1517).
use std::process::Command;

#[test]
fn record_literal_argument_to_stored_closure() {
    let fixture = format!(
        "{}/tests/record_literal_args/closure_field_call.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    for build_type in ["Debug", "Release", "MinSizeRel"] {
        let out = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(["run", &fixture, "--build-type", build_type])
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "{build_type}: {:?} {}",
            out.status,
            String::from_utf8_lossy(&out.stderr)
        );
        assert_eq!(String::from_utf8_lossy(&out.stdout), "3 [0, 3, 0, 7]\n");
    }
}
