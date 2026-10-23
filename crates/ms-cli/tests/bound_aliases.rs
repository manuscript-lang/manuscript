//! Bound mutators of aliases retain their original place across calls.
use std::process::Command;

#[test]
fn bound_alias_methods_write_through() {
    let fixture = format!(
        "{}/tests/bound_aliases/write_through.ms",
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
            "1 [[1, 9, 10], [2]]\nLists(left: [1, 3], right: [2, 4])\n[Counter(count: 9)]\nCounters(left: Counter(count: 3), right: Counter(count: 12))\n1 Map(key-1: [7, 8, 9])\nOptional.some(second) [[first]]\ncount-10 [Counter(count: 10)]\n"
        );
    }
}

#[test]
fn bound_alias_reentry_is_rejected() {
    let fixture = format!(
        "{}/tests/bound_aliases/rejected_reentry.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["check", &fixture])
        .output()
        .unwrap();
    assert!(!out.status.success());
    assert!(
        String::from_utf8_lossy(&out.stderr)
            .contains("cannot change `first.count` while `around` borrows it")
    );
}

#[test]
fn bound_alias_method_cannot_escape() {
    let fixture = format!(
        "{}/tests/bound_aliases/rejected_escape.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["check", &fixture])
        .output()
        .unwrap();
    assert!(!out.status.success());
    assert!(
        String::from_utf8_lossy(&out.stderr)
            .contains("this method value changes `first`, so it cannot be returned")
    );
}
