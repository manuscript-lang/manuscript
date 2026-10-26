//! Test runners must execute the binaries produced by their own Cargo build.
#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::process::Command;

#[test]
fn runners_execute_the_binaries_they_build() {
    let mut failures = Vec::new();
    for (name, script, arguments, calls) in [
        (
            "conform",
            include_bytes!("../../../scripts/conform.sh").as_slice(),
            Vec::new(),
            vec!["lint", "run"],
        ),
        (
            "e2e",
            include_bytes!("../../../scripts/e2e.sh").as_slice(),
            vec!["tests/e2e/testdata/stdlib/fixture.ms"],
            vec!["test"],
        ),
        (
            "leak-check",
            include_bytes!("../../../scripts/leak-check.sh").as_slice(),
            vec!["tests/e2e/testdata/stdlib/fixture.ms"],
            vec!["run"],
        ),
    ] {
        let root = std::env::temp_dir().join(format!("ms-runner-{name}-{}", std::process::id()));
        for (path, bytes) in [
            ("scripts/runner.sh", script),
            ("tests/conformance/expect-fail.txt", b""),
            ("tests/e2e/expect-fail.txt", b""),
            ("tests/e2e/testdata/stdlib/fixture.ms", b"fixture"),
            ("target/debug/ms", b"#!/bin/sh\necho STALE >&2\nexit 42\n"),
            (
                "target/debug/ms-conform",
                b"#!/bin/sh\necho STALE >&2\nexit 42\n",
            ),
            ("target/release/ms", b"#!/bin/sh\necho STALE >&2\nexit 42\n"),
            (
                "mock-bin/uname",
                b"#!/bin/sh\ncase $1 in -s) echo Linux ;; -m) echo x86_64 ;; esac\n",
            ),
            (
                "mock-bin/cargo",
                br#"#!/bin/sh
if [ "$1" = xtask ]; then exit 0; fi
out=${CARGO_TARGET_DIR:-target}
profile=debug
while [ "$#" -gt 0 ]; do
    case "$1" in
        --target-dir) shift; out=$1 ;;
        --release) profile=release ;;
    esac
    shift
done
mkdir -p "$out/$profile"
for binary in ms ms-conform; do
    cat > "$out/$profile/$binary" <<'PROGRAM'
#!/bin/sh
printf '%s\n' "$1" >> "$RUNNER_TEST_LOG"
if [ "$1" = run ]; then echo 'ms-rt live blocks at exit: 0' >&2; fi
PROGRAM
    chmod +x "$out/$profile/$binary"
done
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
        let log = root.join("executed.txt");
        let output = Command::new("sh")
            .arg(root.join("scripts/runner.sh"))
            .args(arguments)
            .env("PATH", path)
            .env("CARGO_TARGET_DIR", root.join("custom cargo target"))
            .env("RUNNER_TEST_LOG", &log)
            .output()
            .unwrap();
        let executed = std::fs::read_to_string(log).unwrap_or_default();
        if !output.status.success() || executed.lines().collect::<Vec<_>>() != calls {
            failures.push(format!(
                "{name}: status {}; executed {executed:?}; stdout {}; stderr {}",
                output.status,
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            ));
        }
        std::fs::remove_dir_all(root).unwrap();
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
