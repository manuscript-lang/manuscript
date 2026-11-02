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

/// A Debug build keeps every element of one `list.lit` live at once, and the Cranelift register
/// allocator is quadratic in that: 40000 elements took 20s. A long literal of plain values is
/// built in chunks, in order, and builds in about a second.
#[test]
fn debug_builds_a_long_list_literal_in_bounded_time() {
    let dir = std::env::temp_dir().join(format!("ms-long-literal-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let items: Vec<String> = (0..40_000)
        .map(|i| format!("n + {}", i * 7 % 1000))
        .collect();
    let source =
        include_str!("llvm/long_literal.ms").replace("[n + 0]", &format!("[{}]", items.join(", ")));
    std::fs::write(dir.join("long.ms"), source).unwrap();
    let started = std::time::Instant::now();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .args(["build", "long.ms", "--build-type", "Debug", "-o", "long"])
        .output()
        .unwrap();
    let elapsed = started.elapsed();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let run = Command::new(dir.join("long")).output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let expected = (0..40_000i64).fold(0, |t, i| (t * 31 + i * 7 % 1000) % 1_000_003);
    assert_eq!(
        String::from_utf8_lossy(&run.stdout),
        format!("{expected} 40000\n")
    );
    assert!(
        elapsed < std::time::Duration::from_secs(12),
        "build took {elapsed:?}"
    );
}

/// A long literal of constants is static data whatever the element type: each type stores its
/// own width, and negative, float and boolean constants read back unchanged.
#[test]
fn long_constant_literals_keep_their_element_types() {
    let dir = std::env::temp_dir().join(format!("ms-const-lists-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let list = |f: &dyn Fn(i64) -> String| (0..100i64).map(f).collect::<Vec<_>>().join(", ");
    let source = include_str!("llvm/const_lists.ms")
        .replace(
            "[100]",
            &format!("[{}]", list(&|i| (i * 1_000_000_007 - 5).to_string())),
        )
        .replace(
            "[101]",
            &format!("[{}]", list(&|i| format!("-{}", i % 100))),
        )
        .replace("[102]", &format!("[{}]", list(&|i| (i * 2).to_string())))
        .replace("[3.5]", &format!("[{}]", list(&|i| format!("-{i}.5"))))
        .replace("[4.5]", &format!("[{}]", list(&|i| format!("{i}.25"))))
        .replace(
            "[true]",
            &format!("[{}]", list(&|i| (i % 3 == 0).to_string())),
        );
    std::fs::write(dir.join("c.ms"), source).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .args(["build", "c.ms", "-o", "c"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let run = Command::new(dir.join("c")).output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let ti: i64 = (0..100i64).map(|i| i * 1_000_000_007 - 5).sum();
    let tb: i64 = (0..100i64).map(|i| -(i % 100)).sum();
    let tc: i64 = (0..100i64).map(|i| i * 2).sum();
    assert_eq!(
        String::from_utf8_lossy(&run.stdout),
        format!(
            "{ti} {tb} {tc} -5000 {} 34 {} -1 true\n",
            (0..100i64).map(|i| i as f64 + 0.25).sum::<f64>(),
            99i64 * 1_000_000_007 - 5
        )
    );
}

/// Constant literals of 20000 and 40000 elements are static data: both backends build them in
/// bounded time.
#[test]
fn constant_literals_of_any_length_build_in_bounded_time() {
    let dir = std::env::temp_dir().join(format!("ms-const-long-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let items: Vec<String> = (0..40_000).map(|i| (i * 7 % 1000).to_string()).collect();
    let source = include_str!("llvm/long_literal.ms")
        .replace("[n + 0]", &format!("[{}]", items.join(", ")))
        .replace("    let n = arguments().length()\n", "")
        .replace("import arguments from \"@std/os/process.ms\"\n", "");
    std::fs::write(dir.join("k.ms"), source).unwrap();
    for backend in ["cranelift", "llvm"] {
        if backend == "llvm" && !cfg!(any(target_os = "linux", target_os = "macos")) {
            continue;
        }
        if backend == "llvm" && !ms_clif::llvm_available() {
            continue;
        }
        let started = std::time::Instant::now();
        let built = Command::new(env!("CARGO_BIN_EXE_ms"))
            .env("MS_BACKEND", backend)
            .current_dir(&dir)
            .args(["build", "k.ms", "-o", "k"])
            .output()
            .unwrap();
        assert!(
            built.status.success(),
            "{}",
            String::from_utf8_lossy(&built.stderr)
        );
        assert!(
            started.elapsed() < std::time::Duration::from_secs(20),
            "{backend} build took {:?}",
            started.elapsed()
        );
        let run = Command::new(dir.join("k")).output().unwrap();
        let expected = (0..40_000i64).fold(0, |t, i| (t * 31 + i * 7 % 1000) % 1_000_003);
        assert_eq!(
            String::from_utf8_lossy(&run.stdout),
            format!("{expected} 40000\n")
        );
    }
    let _ = std::fs::remove_dir_all(&dir);
}
