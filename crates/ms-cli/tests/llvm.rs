//! Release builds through the C pipeline keep the exit code and source frames of faults, including
//! frames of inlined functions. No clang installation is needed.

use std::process::Command;

fn build_and_run(out: &std::path::Path) -> (Option<i32>, String) {
    let source = format!(
        "{}/tests/llvm/overflow_frames.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .env("MS_BACKEND", "c")
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
fn llvm_release_keeps_fault_frames() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_build::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-llvm-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let llvm = build_and_run(&dir.join("llvm"));
    let sidecar = std::fs::read_to_string(dir.join("llvm.ms-build.json")).unwrap();
    assert!(sidecar.contains("\"backend\": \"llvm\""), "{sidecar}");
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(llvm.0, Some(ms_rt_abi::EXIT_ABORT), "{}", llvm.1);
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
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_build::llvm_available(&ms_cli::engine::build_options_from_env())
    {
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
    // A fault ends its file, so each faulting test runs on its own.
    let run = || {
        let mut text = String::new();
        for name in ["first", "second"] {
            let output = Command::new(env!("CARGO_BIN_EXE_ms"))
                .env("MS_BACKEND", "c")
                .args(["test", "--test", &format!("sites.ms::{name}")])
                .arg(&source)
                .output()
                .unwrap();
            assert_eq!(output.status.code(), Some(1));
            assert!(output.stderr.is_empty(), "{:?}", output.stderr);
            text.push_str(&String::from_utf8(output.stdout).unwrap());
        }
        text
    };
    let llvm = run();
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
        "export fn main() Int:\n    x := {}1{}\n    return x.length()\n",
        "[".repeat(depth),
        "]".repeat(depth)
    );
    let dir = std::env::temp_dir().join(format!("ms-deep-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("deep.ms");
    std::fs::write(&file, source).unwrap();
    let start = std::time::Instant::now();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .env("MS_BACKEND", "c")
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
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_build::llvm_available(&ms_cli::engine::build_options_from_env())
    {
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
        .env("MS_BACKEND", "c")
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
/// built in chunks, in order, so the build grows linearly with the literal. The test compares 40000
/// elements against 5000 instead of a wall-clock limit, which a slow or loaded runner can miss
/// (macOS Intel took 12.2 s under nextest). A fixed build cost dilutes the small run, so linear
/// growth is at most 8x, and the quadratic one is about 10x on top of that. The limit of 20x keeps
/// a 2.5x margin for load noise on the linear side.
#[test]
fn debug_builds_a_long_list_literal_in_bounded_time() {
    let small = build_long_literal(5_000);
    let large = build_long_literal(40_000);
    assert!(
        large < small * 20,
        "40000 elements took {large:?}, 5000 took {small:?}: the build is not linear"
    );
}

/// Builds and runs `long_literal.ms` with `count` runtime elements and returns the build time.
fn build_long_literal(count: i64) -> std::time::Duration {
    let dir = std::env::temp_dir().join(format!("ms-long-literal-{}-{count}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let items: Vec<String> = (0..count)
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
    let expected = (0..count).fold(0, |t, i| (t * 31 + i * 7 % 1000) % 1_000_003);
    assert_eq!(
        String::from_utf8_lossy(&run.stdout),
        format!("{expected} {count}\n")
    );
    elapsed
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

/// Constant literals of 20000 and 40000 elements are static data: both build types build them in
/// bounded time.
#[test]
fn constant_literals_of_any_length_build_in_bounded_time() {
    let dir = std::env::temp_dir().join(format!("ms-const-long-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let items: Vec<String> = (0..40_000).map(|i| (i * 7 % 1000).to_string()).collect();
    let source = include_str!("llvm/long_literal.ms")
        .replace("[n + 0]", &format!("[{}]", items.join(", ")))
        .replace("    n := arguments().length()\n", "")
        .replace("import arguments from \"@std/os/env.ms\"\n", "");
    std::fs::write(dir.join("k.ms"), source).unwrap();
    for build_type in ["debug", "release"] {
        let started = std::time::Instant::now();
        let built = Command::new(env!("CARGO_BIN_EXE_ms"))
            .env("MS_BACKEND", "c")
            .current_dir(&dir)
            .args(["build", "k.ms", "--build-type", build_type, "-o", "k"])
            .output()
            .unwrap();
        assert!(
            built.status.success(),
            "{}",
            String::from_utf8_lossy(&built.stderr)
        );
        assert!(
            started.elapsed() < std::time::Duration::from_secs(20),
            "{build_type} build took {:?}",
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

/// Release builds emit every function straight from MIR. The program prints the expected output,
/// and the kept IR shows the facts the emitter proves.
#[test]
fn llvm_direct_emission_proves_facts() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_build::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let source = format!(
        "{}/tests/llvm/direct_scalars.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let dir = std::env::temp_dir().join(format!("ms-llvm-direct-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "c")
        .env("MS_KEEP_LL", "1")
        .args(["build", &source, "-o", "prog"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let out = Command::new(dir.join("prog")).output().unwrap();
    let new_ir = std::fs::read_to_string(dir.join("ms-keep.ll")).unwrap();
    let new_out = String::from_utf8_lossy(&out.stdout).into_owned();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(
        new_out,
        "-10570.332140489487\n-10610.442345302587\n-18691.88657748569\n-3832.9476242902874\n1798.4798787257132\n2478.7401910972353\n24\n"
    );
    assert!(
        new_ir
            .lines()
            .any(|l| l.trim_start().starts_with("%v") && l.contains("= fmul double")),
        "no function was emitted directly"
    );
    // A list parameter of a function only direct code calls is a borrowed pointer to the list.
    assert!(
        new_ir.contains(
            "(ptr nonnull readonly nocapture align 8 dereferenceable(24) %in0, double %v1)"
        ),
        "the list function was not emitted directly"
    );
    // A `Bool` parameter is an `i1`, which is 0 or 1 by construction.
    assert!(new_ir.contains("i1 %v2) nounwind"), "{new_ir}");
    // A pure loop-free function carries what LLVM cannot infer across a unit boundary.
    let grind = new_ir
        .lines()
        .find(|l| l.starts_with("define") && l.contains("grind"))
        .expect("grind");
    assert!(
        grind.contains("memory(none)") && grind.contains("willreturn"),
        "{grind}"
    );
    // Reading elements: the function that loops over a list is direct too, with its bounds check.
    assert!(
        new_ir.lines().any(|l| l.starts_with("define")
            && l.contains("@\"total_floats")
            && l.contains("dereferenceable(24) %in0")),
        "the list loop was not emitted directly"
    );
    // The list element loads carry the scalar element alias class.
    assert!(
        new_ir
            .lines()
            .any(|l| l.contains("load double") && l.contains("!tbaa")),
        "no tagged element load"
    );
}

/// Glue for strings, lists, records and optionals is emitted straight to LLVM IR: the program prints
/// the expected output, and the kept IR defines glue functions.
#[test]
fn llvm_direct_glue_is_emitted_directly() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_build::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let source = format!("{}/tests/llvm/direct_glue.ms", env!("CARGO_MANIFEST_DIR"));
    let dir = std::env::temp_dir().join(format!("ms-llvm-glue-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "c")
        .env("MS_KEEP_LL", "1")
        .args(["build", &source, "-o", "prog"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let out = Command::new(dir.join("prog")).output().unwrap();
    let ir = std::fs::read_to_string(dir.join("ms-keep.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        "210 20 1 first node name that is long enough\n"
    );
    assert!(
        ir.lines()
            .any(|l| l.starts_with("define") && l.contains("@\"ms.glue.")),
        "no glue was emitted"
    );
}

/// A free takes the block as a `ptr`, as its declaration says. Passing the address as an `i64`
/// hid the block from LLVM, which then moved the read of a record's name after the free of the
/// record's box (`if hit := found:` printed garbage).
#[test]
fn llvm_free_calls_pass_a_pointer() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_build::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let source = format!(
        "{}/tests/llvm/free_pointer_argument.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let dir = std::env::temp_dir().join(format!("ms-llvm-free-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "c")
        .env("MS_KEEP_LL", "1")
        .args(["build", &source, "-o", "prog"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let out = Command::new(dir.join("prog")).output().unwrap();
    let ir = std::fs::read_to_string(dir.join("ms-keep.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(String::from_utf8_lossy(&out.stdout), "a,b,c:1\nhit a,b,c\n");
    assert!(ir.contains("@\"msrt_free\"(ptr"), "no free in the program");
    assert!(
        !ir.contains("@\"msrt_free\"(i64"),
        "a free was called with an integer address"
    );
}

/// A recursive method is called by address, so it keeps the leaf convention, and its stack-growth
/// shim is emitted directly too.
#[test]
fn llvm_direct_grow_shim_for_a_leaf_convention_function() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_build::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let source = format!(
        "{}/tests/llvm/direct_grow_shim.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let dir = std::env::temp_dir().join(format!("ms-llvm-grow-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "c")
        .args(["build", &source, "-o", "prog"])
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&built.stderr);
    assert!(built.status.success(), "{stderr}");
    let out = Command::new(dir.join("prog")).output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(String::from_utf8_lossy(&out.stdout), "3000007\n");
}
