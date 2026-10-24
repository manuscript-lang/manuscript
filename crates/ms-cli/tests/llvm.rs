//! Bundled LLVM release builds keep the same exit code and source frames as
//! Cranelift, including frames of inlined functions. No clang installation is needed.

use std::process::Command;

fn build_and_run(backend: &str, out: &std::path::Path) -> (Option<i32>, String) {
    let source = format!(
        "{}/tests/llvm/overflow_frames.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .env("MS_BACKEND", backend)
        .args(["build", &source, "-o"])
        .arg(out)
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let run = Command::new(out).output().unwrap();
    (
        run.status.code(),
        String::from_utf8_lossy(&run.stderr).into_owned(),
    )
}

#[test]
fn llvm_release_matches_cranelift_fault_frames() {
    if !cfg!(any(target_os = "linux", target_os = "macos")) || !ms_clif::llvm_available() {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-llvm-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let cranelift = build_and_run("cranelift", &dir.join("cranelift"));
    let llvm = build_and_run("llvm", &dir.join("llvm"));
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(llvm.0, Some(70), "{}", llvm.1);
    assert_eq!(llvm, cranelift);
    assert!(
        llvm.1.contains("overflow_frames.ms:2 in add_one"),
        "{}",
        llvm.1
    );
    assert!(
        llvm.1.contains("overflow_frames.ms:8 in main"),
        "{}",
        llvm.1
    );
}

#[test]
fn llvm_native_calls_keep_distinct_fault_sites() {
    if !cfg!(any(target_os = "linux", target_os = "macos")) || !ms_clif::llvm_available() {
        return;
    }
    let source = format!(
        "{}/../../tests/conformance/fixtures/snippets/tests-e2e-testreplacenretainsnegativefaultsandframes-1.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let run = |backend| {
        let output = Command::new(env!("CARGO_BIN_EXE_ms"))
            .env("MS_BACKEND", backend)
            .args(["test", &source])
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stderr.is_empty(), "{:?}", output.stderr);
        String::from_utf8(output.stdout).unwrap()
    };
    let cranelift = run("cranelift");
    let llvm = run("llvm");
    assert_eq!(llvm, cranelift);
    assert!(llvm.contains(".ms:8 in test required negative"), "{llvm}");
    assert!(llvm.contains(".ms:15 in test empty negative"), "{llvm}");
}

/// Drop glue of nested collections stays out of line, so optimizing a deeply nested literal takes
/// time linear in its depth instead of nesting one loop per level.
#[test]
fn deeply_nested_literal_builds_quickly() {
    let depth = 400;
    let source = format!(
        "export def main() -> Int:\n    let x = {}1{}\n    return x.length()\n",
        "[".repeat(depth),
        "]".repeat(depth)
    );
    let dir = std::env::temp_dir().join(format!("ms-deep-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("deep.ms");
    std::fs::write(&file, source).unwrap();
    let start = std::time::Instant::now();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("build")
        .arg(&file)
        .arg("-o")
        .arg(dir.join("deep"))
        .output()
        .unwrap();
    let elapsed = start.elapsed();
    let _ = std::fs::remove_dir_all(&dir);
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    assert!(
        elapsed < std::time::Duration::from_secs(30),
        "release build took {elapsed:?}"
    );
}
