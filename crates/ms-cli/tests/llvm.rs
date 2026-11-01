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
    assert_eq!(llvm.0, Some(67), "{}", llvm.1);
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
    let dir = std::env::temp_dir().join(format!("ms-llvm-sites-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let source = dir.join("sites.ms");
    std::fs::write(
        &source,
        include_str!("llvm/llvm-native-calls-keep-distinct-fault-sites.ms"),
    )
    .unwrap();
    let run = |backend| {
        let output = Command::new(env!("CARGO_BIN_EXE_ms"))
            .env("MS_BACKEND", backend)
            .args(["test"])
            .arg(&source)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stderr.is_empty(), "{:?}", output.stderr);
        String::from_utf8(output.stdout).unwrap()
    };
    let cranelift = run("cranelift");
    let llvm = run("llvm");
    assert_eq!(llvm, cranelift);
    let _ = std::fs::remove_dir_all(&dir);
    assert!(llvm.contains("sites.ms:3 in test first"), "{llvm}");
    assert!(llvm.contains("sites.ms:7 in test second"), "{llvm}");
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

/// A list literal of 20000 runtime elements is one straight-line function. LLVM's SLP vectorizer
/// and machine scheduler are quadratic in that length and took over two minutes on it; both are
/// off for huge functions, so the build takes seconds.
#[test]
fn llvm_builds_a_huge_straight_line_function_in_bounded_time() {
    if !cfg!(any(target_os = "linux", target_os = "macos")) || !ms_clif::llvm_available() {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-llvm-huge-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let items: Vec<String> = (0..20_000).map(|i| format!("n + {i}")).collect();
    let source =
        include_str!("llvm/huge_literal.ms").replace("[n + 0]", &format!("[{}]", items.join(", ")));
    std::fs::write(dir.join("huge.ms"), source).unwrap();
    let started = std::time::Instant::now();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .env("MS_BACKEND", "llvm")
        .current_dir(&dir)
        .args(["build", "huge.ms", "-o", "huge"])
        .output()
        .unwrap();
    let elapsed = started.elapsed();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let run = Command::new(dir.join("huge")).output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(String::from_utf8_lossy(&run.stdout), "199990000\n");
    assert!(
        elapsed < std::time::Duration::from_secs(60),
        "build took {elapsed:?}"
    );
}
