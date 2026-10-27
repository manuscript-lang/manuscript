//! A caller's Cargo output directory must not make packaging ship an old binary.
#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::process::Command;

#[test]
fn distribution_packages_the_binary_it_just_built() {
    let root = std::env::temp_dir().join(format!("ms-distribution-target-{}", std::process::id()));
    for (name, bytes) in [
        (
            "scripts/package-rust.sh",
            include_bytes!("../../../scripts/package-rust.sh").as_slice(),
        ),
        ("examples/hello/ms.toml", b"manifest"),
        ("examples/hello/src/main.ms", b"main"),
        ("examples/hello/test.ms", b"test"),
        ("target/release/ms", b"stale compiler"),
        (
            "mock-bin/cargo",
            // Model Cargo's output selection: --target-dir takes priority over the environment,
            // and an explicit target (flag or CARGO_BUILD_TARGET) adds a triple directory.
            br#"#!/bin/sh
if [ "$1" = xtask ]; then exit 0; fi
out=${CARGO_TARGET_DIR:-target}
triple=${CARGO_BUILD_TARGET:-}
while [ "$#" -gt 0 ]; do
    if [ "$1" = --target-dir ]; then shift; out=$1; fi
    if [ "$1" = --target ]; then shift; triple=$1; fi
    shift
done
if [ -n "$triple" ]; then out="$out/$triple"; fi
mkdir -p "$out/release"
printf 'fresh compiler' > "$out/release/ms"
"#,
        ),
    ] {
        let path = root.join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }
    std::fs::set_permissions(
        root.join("mock-bin/cargo"),
        std::fs::Permissions::from_mode(0o755),
    )
    .unwrap();
    let inherited = std::env::var_os("PATH").unwrap();
    let path = std::env::join_paths(
        std::iter::once(root.join("mock-bin")).chain(std::env::split_paths(&inherited)),
    )
    .unwrap();
    let output = Command::new("sh")
        .arg(root.join("scripts/package-rust.sh"))
        .args(["linux", "amd64"])
        .env("PATH", path)
        .env("CARGO_TARGET_DIR", root.join("custom cargo target"))
        .env("CARGO_BUILD_TARGET", "x86_64-unknown-linux-gnu")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let compiler = Command::new("tar")
        .arg("-xOzf")
        .arg(root.join("dist/manuscript-rust-linux-amd64.tar.gz"))
        .arg("manuscript-rust-linux-amd64/ms")
        .output()
        .unwrap();
    assert!(compiler.status.success());
    assert_eq!(compiler.stdout, b"fresh compiler");
    std::fs::remove_dir_all(root).unwrap();
}
