//! Exercise the archive layout without rebuilding the compiler inside a test.
#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

fn write(root: &Path, name: &str, bytes: &[u8]) {
    let path = root.join(name);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, bytes).unwrap();
}

#[test]
fn distribution_contains_the_documented_hello_test() {
    let root = std::env::temp_dir().join(format!("ms-distribution-{}", std::process::id()));
    write(
        &root,
        "scripts/package-rust.sh",
        include_bytes!("../../../scripts/package-rust.sh"),
    );
    for (name, bytes) in [
        (
            "examples/hello/ms.toml",
            include_bytes!("../../../examples/hello/ms.toml").as_slice(),
        ),
        (
            "examples/hello/src/main.ms",
            include_bytes!("../../../examples/hello/src/main.ms").as_slice(),
        ),
        (
            "examples/hello/test.ms",
            include_bytes!("../../../examples/hello/test.ms").as_slice(),
        ),
    ] {
        write(&root, name, bytes);
    }
    // Cargo is deliberately inert: only the packaging step is under test.
    write(&root, "mock-bin/cargo", b"#!/bin/sh\nexit 0\n");
    write(&root, "target/release/ms", b"compiler fixture\n");
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
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let extracted = root.join("extracted distribution");
    std::fs::create_dir_all(&extracted).unwrap();
    let status = Command::new("tar")
        .arg("-xzf")
        .arg(root.join("dist/manuscript-rust-linux-amd64.tar.gz"))
        .arg("-C")
        .arg(&extracted)
        .status()
        .unwrap();
    assert!(status.success());
    let test = extracted.join("manuscript-rust-linux-amd64/examples/hello/test.ms");
    assert_eq!(
        std::fs::read(&test).expect("the documented hello test must be shipped"),
        include_bytes!("../../../examples/hello/test.ms")
    );
    std::fs::remove_dir_all(root).unwrap();
}
