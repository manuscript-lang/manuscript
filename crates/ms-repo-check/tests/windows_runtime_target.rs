//! MSYS can report an x64 shell while Cargo uses the native ARM64 Rust host.
#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::process::Command;

#[test]
fn windows_runtime_target_matches_the_native_rust_host() {
    let mut failures = Vec::new();
    for arch in ["aarch64", "x86_64"] {
        let root = std::env::temp_dir().join(format!(
            "ms-windows-runtime-target-{arch}-{}",
            std::process::id()
        ));
        for (path, bytes) in [
            (
                "scripts/leak-check.sh",
                include_bytes!("../../../scripts/leak-check.sh").as_slice(),
            ),
            (
                "mock-bin/uname",
                b"#!/bin/sh\ncase $1 in -s) echo MINGW64_NT ;; -m) echo x86_64 ;; esac\n",
            ),
            (
                "mock-bin/rustc",
                b"#!/bin/sh\nprintf 'host: %s-pc-windows-msvc\\n' \"$MOCK_RUST_ARCH\"\n",
            ),
            (
                "mock-bin/cargo",
                br#"#!/bin/sh
printf 'call\n' >> "$TARGET_TEST_LOG.calls"
printf '%s\n' "$@" > "$TARGET_TEST_LOG.args"
printf '%s\n' "${CC_aarch64_pc_windows_gnullvm-}" "${CC_x86_64_pc_windows_gnullvm-}" > "$TARGET_TEST_LOG.cc"
# Stop at the first build: no runtime or allocation-check program is built or executed.
exit 93
"#,
            ),
        ] {
            let path = root.join(path);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, bytes).unwrap();
            std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        let inherited = std::env::var_os("PATH").unwrap();
        let path = std::env::join_paths(
            std::iter::once(root.join("mock-bin")).chain(std::env::split_paths(&inherited)),
        )
        .unwrap();
        let log = root.join("cargo");
        let mingw = root.join("mingw");
        let output = Command::new("sh")
            .arg(root.join("scripts/leak-check.sh"))
            .env("PATH", path)
            .env("MOCK_RUST_ARCH", arch)
            .env("MS_MINGW", &mingw)
            .env("TARGET_TEST_LOG", &log)
            .env_remove("CC_aarch64_pc_windows_gnullvm")
            .env_remove("CC_x86_64_pc_windows_gnullvm")
            .output()
            .unwrap();
        let calls = std::fs::read_to_string(log.with_extension("calls")).unwrap_or_default();
        let args = std::fs::read_to_string(log.with_extension("args")).unwrap_or_default();
        let cc = std::fs::read_to_string(log.with_extension("cc")).unwrap_or_default();
        let expected_target = format!("{arch}-pc-windows-gnullvm");
        let expected_cc = format!("{}/bin/{arch}-w64-mingw32-clang", mingw.display());
        if output.status.code() != Some(93)
            || calls != "call\n"
            || !args
                .lines()
                .collect::<Vec<_>>()
                .windows(2)
                .any(|w| w == ["--target", &expected_target])
            || cc
                .lines()
                .filter(|line| !line.is_empty())
                .collect::<Vec<_>>()
                != [expected_cc.as_str()]
        {
            failures.push(format!(
                "{arch}: status {}; calls {calls:?}; args {args:?}; compiler {cc:?}; stderr {}",
                output.status,
                String::from_utf8_lossy(&output.stderr)
            ));
        }
        std::fs::remove_dir_all(root).unwrap();
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
