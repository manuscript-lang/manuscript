//! A type with an `impl` of an interface converts implicitly where the interface is expected.

use std::process::Command;

#[test]
fn implementing_types_convert_to_interfaces() {
    let file = format!(
        "{}/tests/interface_conversion/convert.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["run", &file])
        .output()
        .unwrap();
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(out.status.code(), Some(0), "{text}");
}
