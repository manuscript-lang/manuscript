//! Regression for expected-failure regexes that select no tests.
#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

fn executable(path: &Path, text: &str) {
    std::fs::write(path, text).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn expected_failure_requires_a_selected_failing_test() {
    let root = std::env::temp_dir().join(format!("ms-e2e-runner-{}", std::process::id()));
    for directory in ["scripts", "target/debug", "tests/e2e", "mock-bin"] {
        std::fs::create_dir_all(root.join(directory)).unwrap();
    }
    std::fs::write(
        root.join("scripts/e2e.sh"),
        include_str!("../../../scripts/e2e.sh"),
    )
    .unwrap();
    let fixture = "tests/e2e/testdata/stdlib/fixture.ms";
    std::fs::write(
        root.join("tests/e2e/expect-fail.txt"),
        format!("{fixture}\t^fixture.ms::fails\n"),
    )
    .unwrap();
    executable(&root.join("mock-bin/cargo"), "#!/bin/sh\nexit 0\n");
    executable(&root.join("mock-bin/uname"), "#!/bin/sh\necho Linux\n");
    executable(
        &root.join("target/debug/ms"),
        r#"#!/bin/sh
case "$*" in
    *--list*)
        if [ "$E2E_CASE" = no_match ]; then echo 'no tests match selection'; exit 1; fi
        echo 'fixture.ms::fails'; exit 0 ;;
    *--exclude*) exit 0 ;;
    *--match*) [ "$E2E_CASE" = passes ]; exit $? ;;
esac
exit 2
"#,
    );
    let inherited = std::env::var_os("PATH").unwrap();
    let path = std::env::join_paths(
        std::iter::once(root.join("mock-bin")).chain(std::env::split_paths(&inherited)),
    )
    .unwrap();
    for (case, succeeds, diagnostic) in [
        ("no_match", false, "does not select runnable tests"),
        ("fails", true, "e2e: 1 fixtures, 0 failed"),
        ("passes", false, "is listed as failing but passes"),
    ] {
        let output = Command::new("sh")
            .arg(root.join("scripts/e2e.sh"))
            .arg(fixture)
            .env("PATH", &path)
            .env("E2E_CASE", case)
            .output()
            .unwrap();
        let text = format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(output.status.success(), succeeds, "{case}: {text}");
        assert!(text.contains(diagnostic), "{case}: {text}");
    }
    std::fs::remove_dir_all(root).unwrap();
}
