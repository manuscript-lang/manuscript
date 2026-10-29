//! `opaque type` hides fields and cases outside the declaring file.
use std::process::{Command, Output};

fn ms(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .output()
        .unwrap()
}

fn fixture(name: &str) -> String {
    format!("{}/tests/opaque/{name}.ms", env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn opaque_values_use_the_module_api_and_print_only_the_type_name() {
    for build_type in ["Debug", "Release"] {
        let out = ms(&["run", &fixture("ok"), "--build-type", build_type]);
        // "Approved" three times (interpolation, to_string, generic) plus "approved:u1".
        assert_eq!(out.status.code(), Some(35), "{build_type}");
    }
}

#[test]
fn opaque_types_reject_outside_use() {
    let cases = [
        ("construct", "cannot be constructed here"),
        ("field", "field nonce is hidden"),
        ("assign", "field nonce is hidden"),
        ("pattern", "fields cannot be destructured here"),
        ("cases", "cases cannot be matched here"),
        ("case_build", "case Safe cannot be built here"),
        ("method", "inherent methods belong in the module"),
        ("iface", "takes no new methods or interfaces here"),
        ("parse", "Approved does not satisfy Data; it is opaque"),
        ("stringify", "Approved does not satisfy Data; it is opaque"),
        ("generic", "T does not satisfy Data"),
    ];
    for (name, message) in cases {
        let out = ms(&["check", &fixture(name)]);
        let stderr = String::from_utf8_lossy(&out.stderr);
        assert!(!out.status.success(), "{name} should be rejected");
        assert!(stderr.contains(message), "{name}: {stderr}");
    }
}

#[test]
fn opaque_formats_and_round_trips() {
    let out = ms(&["fmt", "--check", &fixture("gate")]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
}
