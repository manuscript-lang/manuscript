//! `[imports]` in `ms.toml` limits which modules each file may import.
use std::process::{Command, Output};

fn ms(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .output()
        .unwrap()
}

fn fixture(name: &str) -> String {
    format!("{}/tests/imports/{name}", env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn disallowed_imports_are_reported_at_the_import_line() {
    let out = ms(&["check", &fixture("ms.toml")]);
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(!out.status.success(), "{stderr}");
    for message in [
        "src/leak.ms:1:1: resolution: src/leak.ms may not import @std/fs.ms; ms.toml [imports] \"src/**\" allows only \"src/**\", \"types/**\", \"@std/collections.ms\", \"@std/string.ms\", \"@std/json.ms\", so import one of those or extend the list",
        "src/sideways.ms:1:1: resolution: src/sideways.ms may not import tests/helper.ms;",
    ] {
        assert!(stderr.contains(message), "{stderr}");
    }
    // The allowed modules carry no diagnostic: main.ms through types/disk.ms to @std/fs.ms,
    // and tests/helper.ms, which may import anything.
    for file in ["src/main.ms", "types/disk.ms", "tests/helper.ms"] {
        assert!(!stderr.contains(&format!("{file}:")), "{stderr}");
    }
    assert!(stderr.contains("2 errors"), "{stderr}");
}

#[test]
fn a_single_file_is_checked_without_the_manifest() {
    // `ms check file.ms` reads no manifest, as for aliases, so the list applies only to
    // the project check above.
    let out = ms(&["check", &fixture("src/leak.ms")]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
}
