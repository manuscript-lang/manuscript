//! The ownership-count gate must fail when its fixture fails, even when cleanup is complete.

mod common;

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

/// The repo root without Windows' `\\?\` verbatim prefix: it becomes cargo's cwd and target
/// directory, and the `ar` that `ring`'s build script runs cannot open verbatim paths.
fn repo_root() -> PathBuf {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap();
    match root.to_str().and_then(|s| s.strip_prefix(r"\\?\")) {
        Some(plain) if !plain.starts_with("UNC") => PathBuf::from(plain),
        _ => root,
    }
}

fn count_check(fixture: &str, compiler: &Path) -> Output {
    let root = repo_root();
    let stats = std::env::var_os("LEAK_TARGET_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("target/leak-stats"));
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(root)
        .args([
            "run",
            "tools/count-check.ms",
            "--build-type",
            "Debug",
            "--",
            fixture,
        ])
        .env("MS", compiler)
        .env("LEAK_TARGET_DIR", stats)
        .output()
        .unwrap()
}

#[test]
fn count_gate_rejects_failed_children_even_with_zero_live_blocks() {
    let compiler = Path::new(env!("CARGO_BIN_EXE_ms"));
    let failed = count_check("crates/ms-cli/tests/count_check/nonzero.ms", compiler);
    let out = String::from_utf8_lossy(&failed.stdout);
    let err = String::from_utf8_lossy(&failed.stderr);
    assert_eq!(failed.status.code(), Some(1), "{out}{err}");
    for profile in ["debug", "release"] {
        assert!(out.contains(&format!("({profile}) exited 7")), "{out}{err}");
    }
    // This is an actual entry+stats runtime. Complete cleanup must not hide the failure status.
    assert!(out.contains("ms-rt live blocks at exit: 0"), "{out}{err}");

    let passed = count_check("crates/ms-cli/tests/count_check/success.ms", compiler);
    let out = String::from_utf8_lossy(&passed.stdout);
    let err = String::from_utf8_lossy(&passed.stderr);
    assert!(passed.status.success(), "{out}{err}");
    assert!(
        out.contains("checked 2 expectations, 0 failing"),
        "{out}{err}"
    );

    let rejected = count_check("crates/ms-cli/tests/count_check/rejected.ms", compiler);
    let out = String::from_utf8_lossy(&rejected.stdout);
    let err = String::from_utf8_lossy(&rejected.stderr);
    assert_eq!(rejected.status.code(), Some(1), "{out}{err}");
    assert!(out.contains("exited 1"), "{out}{err}");
    assert!(out.contains("type:"), "{out}{err}");
    assert!(!out.contains("leak:"), "{out}{err}");

    let scratch = common::scratch("missing-compiler");
    let unavailable = count_check(
        "crates/ms-cli/tests/count_check/success.ms",
        &scratch.join("missing-ms"),
    );
    let out = String::from_utf8_lossy(&unavailable.stdout);
    let err = String::from_utf8_lossy(&unavailable.stderr);
    assert_eq!(unavailable.status.code(), Some(1), "{out}{err}");
    assert!(out.contains("could not run"), "{out}{err}");
    assert!(!out.contains("leak:"), "{out}{err}");
}
