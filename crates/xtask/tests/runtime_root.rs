//! A shared Cargo target can reuse xtask's executable from another checkout.
#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::process::Command;

#[test]
fn runtime_uses_the_active_cargo_manifest_directory() {
    let root = std::env::temp_dir().join(format!("ms xtask root {}", std::process::id()));
    let manifest = root.join("crates/xtask");
    let target = root.join("target/ms-native/build");
    std::fs::create_dir_all(&manifest).unwrap();
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(root.join("Cargo.toml"), "[workspace]\n").unwrap();
    let cargo = root.join("cargo");
    std::fs::write(
        &cargo,
        // The archives build side by side, so each invocation records under its own target directory name.
        "#!/bin/sh\nname=$(basename \"$CARGO_TARGET_DIR\")\nprintf '%s\\n' \"$@\" > \"$XTASK_TEST_DIR/$name.args\"\nprintf '%s' \"$CARGO_TARGET_DIR\" > \"$XTASK_TEST_DIR/$name.target\"\nexit 1\n",
    )
    .unwrap();
    std::fs::set_permissions(&cargo, std::fs::Permissions::from_mode(0o755)).unwrap();
    let record = root.join("record");
    std::fs::create_dir_all(&record).unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_xtask"))
        .arg("runtime")
        .current_dir(&root)
        .env("CARGO", cargo)
        .env("CARGO_MANIFEST_DIR", &manifest)
        .env("XTASK_TEST_DIR", &record)
        .output()
        .unwrap();
    // Every Cargo invocation fails: neither checkout's runtime is modified by this test. The host
    // archive's build is the one checked.
    assert!(!output.status.success());
    let arguments = std::fs::read_to_string(record.join("build.args")).unwrap();
    let words: Vec<_> = arguments.lines().collect();
    let at = words
        .iter()
        .position(|word| *word == "--manifest-path")
        .unwrap();
    assert_eq!(
        std::fs::canonicalize(words[at + 1]).unwrap(),
        std::fs::canonicalize(root.join("Cargo.toml")).unwrap(),
        "runtime must be built from the active checkout"
    );
    assert_eq!(
        std::fs::canonicalize(std::fs::read_to_string(record.join("build.target")).unwrap())
            .unwrap(),
        std::fs::canonicalize(target).unwrap(),
        "runtime output must belong to the active checkout"
    );
    std::fs::remove_dir_all(root).unwrap();
}
