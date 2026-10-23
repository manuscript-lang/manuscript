//! Release builds go through LLVM when `clang` is available (Linux). A fault keeps the same exit
//! code and source frames as the Cranelift build, including frames of inlined functions.

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
    let have_clang = Command::new("clang")
        .arg("--version")
        .output()
        .is_ok_and(|o| o.status.success());
    if !cfg!(target_os = "linux") || !have_clang {
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

/// Drop glue of nested collections stays out of line, so optimizing a deeply nested literal takes
/// time linear in its depth instead of nesting one loop per level.
#[test]
fn deeply_nested_literal_builds_quickly() {
    let depth = 400;
    let source = format!(
        "export fn main() Int:\n    let x = {}1{}\n    return x.length()\n",
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
