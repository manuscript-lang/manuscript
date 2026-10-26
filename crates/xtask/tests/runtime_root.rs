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
        "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$XTASK_TEST_ARGS\"\nprintf '%s' \"$CARGO_TARGET_DIR\" > \"$XTASK_TEST_TARGET\"\nexit 1\n",
    )
    .unwrap();
    std::fs::set_permissions(&cargo, std::fs::Permissions::from_mode(0o755)).unwrap();
    let args = root.join("arguments");
    let built_target = root.join("built-target");
    let output = Command::new(env!("CARGO_BIN_EXE_xtask"))
        .arg("runtime")
        .current_dir(&root)
        .env("CARGO", cargo)
        .env("CARGO_MANIFEST_DIR", &manifest)
        .env("XTASK_TEST_ARGS", &args)
        .env("XTASK_TEST_TARGET", &built_target)
        .output()
        .unwrap();
    // Stop at the first Cargo invocation: neither checkout's runtime is modified by this test.
    assert!(!output.status.success());
    let arguments = std::fs::read_to_string(args).unwrap();
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
        std::fs::canonicalize(std::fs::read_to_string(built_target).unwrap()).unwrap(),
        std::fs::canonicalize(target).unwrap(),
        "runtime output must belong to the active checkout"
    );
    std::fs::remove_dir_all(root).unwrap();
}
