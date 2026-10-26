//! Keep the Linux C driver checked against the production runtime ABI.
#![cfg(target_os = "linux")]

use std::process::Command;
use std::{os::unix::fs::PermissionsExt, path::Path};

fn executable(root: &Path, name: &str, source: &str) {
    let path = root.join(name);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, source).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn c_benchmark_uses_the_built_archive_from_another_directory() {
    let root = std::env::temp_dir().join(format!("ms-c-benchmark-{}", std::process::id()));
    let script = root.join("checkout/crates/ms-rt/tests/bench/run.sh");
    std::fs::create_dir_all(script.parent().unwrap()).unwrap();
    std::fs::write(&script, include_bytes!("../../ms-rt/tests/bench/run.sh")).unwrap();
    // The runner is under test; Cargo and cc make the consumed archive identity observable.
    executable(
        &root,
        "bin/cargo",
        r#"#!/bin/sh
set -eu
target=$CARGO_TARGET_DIR
while [ $# -gt 0 ]; do
    if [ "$1" = --target-dir ]; then target=$2; shift; fi
    shift
done
mkdir -p "$target/release"
printf fresh > "$target/release/libms_native.a"
"#,
    );
    executable(
        &root,
        "bin/cc",
        r#"#!/bin/sh
set -eu
out=
for arg do
    if [ "$arg" = -o ]; then next=out; continue; fi
    if [ "${next-}" = out ]; then out=$arg; next=; fi
    case "$arg" in */libms_native.a) test "$(cat "$arg")" = fresh ;; esac
done
printf '#!/bin/sh\nexit 0\n' > "$out"
chmod +x "$out"
"#,
    );
    let path = std::env::join_paths(
        std::iter::once(root.join("bin"))
            .chain(std::env::split_paths(&std::env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let output = Command::new("sh")
        .arg(&script)
        .current_dir(&root)
        .env("PATH", path)
        .env("CARGO_TARGET_DIR", "target with spaces")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        root.join("checkout/target with spaces/release/libms_native.a")
            .is_file()
    );
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn c_runtime_smoke_checks_all_modes() {
    let output = Command::new("sh")
        .arg(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../ms-rt/tests/e2e/run.sh"
        ))
        .output()
        .expect("run the native C smoke harness");
    assert!(
        output.status.success(),
        "status: {}\nstdout:\n{}\nstderr:\n{}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("ms-rt e2e: ok"));
}
