//! Bundled LLVM release builds keep the same exit code and source frames as
//! Cranelift, including frames of inlined functions. No clang installation is needed.

use std::process::Command;

fn build_and_run(backend: &str, out: &std::path::Path) -> (Option<i32>, String) {
    build_and_run_units(backend, "1", out)
}

fn build_and_run_units(backend: &str, units: &str, out: &std::path::Path) -> (Option<i32>, String) {
    let source = format!(
        "{}/tests/llvm/overflow_frames.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .env("MS_BACKEND", backend)
        .env("MS_LLVM_UNITS", units)
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
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_clif::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-llvm-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let cranelift = build_and_run("cranelift", &dir.join("cranelift"));
    let llvm = build_and_run("llvm", &dir.join("llvm"));
    for (name, backend) in [("cranelift", "cranelift"), ("llvm", "llvm")] {
        let sidecar = std::fs::read_to_string(dir.join(format!("{name}.ms-build.json"))).unwrap();
        assert!(
            sidecar.contains(&format!("\"backend\": \"{backend}\"")),
            "{sidecar}"
        );
    }
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
fn llvm_units_keep_fault_frames() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_clif::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-llvm-units-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let whole = build_and_run_units("llvm", "1", &dir.join("whole"));
    let split = build_and_run_units("llvm", "4", &dir.join("split"));
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(split.0, Some(67), "{}", split.1);
    assert_eq!(split, whole);
}

#[test]
fn llvm_native_calls_keep_distinct_fault_sites() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_clif::llvm_available(&ms_cli::engine::build_options_from_env())
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
        || !ms_clif::llvm_available(&ms_cli::engine::build_options_from_env())
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
/// built in chunks, in order, so the build grows linearly with the literal. The test compares 40000
/// elements against 10000 instead of a wall-clock limit, which a slow or loaded runner can miss
/// (macOS Intel took 12.2 s under nextest): linear growth is at most 4x, the quadratic one about 10x.
#[test]
fn debug_builds_a_long_list_literal_in_bounded_time() {
    let small = build_long_literal(10_000);
    let large = build_long_literal(40_000);
    assert!(
        large < small * 6,
        "40000 elements took {large:?}, 10000 took {small:?}: the build is not linear"
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

/// Constant literals of 20000 and 40000 elements are static data: both backends build them in
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
    for backend in ["cranelift", "llvm"] {
        if backend == "llvm" && !cfg!(any(target_os = "linux", target_os = "macos")) {
            continue;
        }
        if backend == "llvm" && !ms_clif::llvm_available(&ms_cli::engine::build_options_from_env())
        {
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

/// Functions made only of scalar arithmetic, comparisons, branches and calls are emitted straight
/// from MIR (`MS_LLVM_DIRECT`); the rest still go through the Cranelift translation. The program
/// prints the same output either way, and the kept IR shows a direct function.
#[test]
fn llvm_direct_emission_matches_translation() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_clif::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let source = format!(
        "{}/tests/llvm/direct_scalars.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let dir = std::env::temp_dir().join(format!("ms-llvm-direct-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let run = |direct: bool| {
        let work = dir.join(if direct { "direct" } else { "old" });
        std::fs::create_dir_all(&work).unwrap();
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_ms"));
        cmd.current_dir(&work)
            .env("MS_BACKEND", "llvm")
            .env("MS_LLVM_UNITS", "1")
            .env("MS_KEEP_LL", "1")
            .args(["build", &source, "-o", "prog"]);
        if direct {
            cmd.env("MS_LLVM_DIRECT", "1");
        }
        let built = cmd.output().unwrap();
        assert!(
            built.status.success(),
            "{}",
            String::from_utf8_lossy(&built.stderr)
        );
        let out = Command::new(work.join("prog")).output().unwrap();
        let ir = std::fs::read_to_string(work.join("ms-keep.ll")).unwrap();
        (String::from_utf8_lossy(&out.stdout).into_owned(), ir)
    };
    let (old_out, old_ir) = run(false);
    let (new_out, new_ir) = run(true);
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(new_out, old_out);
    assert_eq!(
        new_out,
        "-10570.332140489487\n-10610.442345302587\n-18691.88657748569\n-3832.9476242902874\n1798.4798787257132\n2478.7401910972353\n24\n"
    );
    // Direct functions name their values `%vN`; the translation names them `%tN`.
    let direct = |ir: &str| {
        ir.lines()
            .any(|l| l.trim_start().starts_with("%v") && l.contains("= fmul double"))
    };
    assert!(!direct(&old_ir), "the translation was not used");
    assert!(direct(&new_ir), "no function was emitted directly");
    // A list parameter is three leaves, and `length` is one of them.
    assert!(
        new_ir.contains("%a0_0, i64 %a0_1, i64 %a0_2, double %a1_0"),
        "the list function was not emitted directly"
    );
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
            && l.contains("%a0_2")),
        "the list loop was not emitted directly"
    );
}

/// Glue for strings, lists, records and optionals is emitted straight to LLVM IR
/// (`MS_LLVM_DIRECT`): the program prints the same output, and the kept IR has a glue function
/// whose entry block is the direct emitter's `entry`, which the translation never names so.
#[test]
fn llvm_direct_glue_matches_translation() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_clif::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let source = format!("{}/tests/llvm/direct_glue.ms", env!("CARGO_MANIFEST_DIR"));
    let dir = std::env::temp_dir().join(format!("ms-llvm-glue-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let run = |direct: bool| {
        let work = dir.join(if direct { "direct" } else { "old" });
        std::fs::create_dir_all(&work).unwrap();
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_ms"));
        cmd.current_dir(&work)
            .env("MS_BACKEND", "llvm")
            .env("MS_LLVM_UNITS", "1")
            .env("MS_KEEP_LL", "1")
            .args(["build", &source, "-o", "prog"]);
        if direct {
            cmd.env("MS_LLVM_DIRECT", "1");
        }
        let built = cmd.output().unwrap();
        assert!(
            built.status.success(),
            "{}",
            String::from_utf8_lossy(&built.stderr)
        );
        let out = Command::new(work.join("prog")).output().unwrap();
        let ir = std::fs::read_to_string(work.join("ms-keep.ll")).unwrap();
        (String::from_utf8_lossy(&out.stdout).into_owned(), ir)
    };
    let (old_out, old_ir) = run(false);
    let (new_out, new_ir) = run(true);
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(new_out, old_out);
    assert_eq!(new_out, "210 20 1 first node name that is long enough\n");
    let direct = |ir: &str| {
        let mut lines = ir.lines();
        while let Some(l) = lines.next() {
            if l.starts_with("define")
                && l.contains("@\"ms.glue.")
                && lines.next() == Some("entry:")
            {
                return true;
            }
        }
        false
    };
    assert!(!direct(&old_ir), "the translation was not used");
    assert!(direct(&new_ir), "no glue was emitted directly");
}

/// Closures, indirect calls and runtime calls are emitted straight from MIR (`MS_LLVM_DIRECT`): the
/// program prints the same output, and the kept IR has the closure object written through typed
/// stores, a call through the code pointer it holds, and a runtime call with a hidden result pointer.
#[test]
fn llvm_direct_closures_match_translation() {
    if !cfg!(any(target_os = "linux", target_os = "macos"))
        || !ms_clif::llvm_available(&ms_cli::engine::build_options_from_env())
    {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-llvm-closures-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    // The padding keeps the inliner from folding these functions into `main`.
    let pad: String = (0..60)
        .map(|i| format!("    pad = pad * 1.0001 + {i}.5\n"))
        .collect();
    let program = format!(
        r#"// Closures, indirect calls and runtime calls, emitted straight from MIR. The padding keeps the
// inliner from folding these functions into `main`.
fn make_scaler(scale: Float, shift: Float, flip: Bool) fn(Float) Float:
    var pad = scale
{pad}
    return fn(x: Float) Float:
        if flip:
            return x * scale + shift + pad * 0.0
        return x - shift

fn make_counter(xs: List[Float], label: String, bias: Float, big: Bool) fn(Float) Float:
    var pad = bias
{pad}
    return fn(x: Float) Float:
        if xs.length() > 2 and big:
            return x * bias + pad * 0.0
        return x + bias

fn show(n: Int, bias: Float) String:
    var pad = bias
{pad}
    if pad > 1.0e300:
        return pad.to_string()
    return n.to_string()

fn fold(f: fn(Float) Float, start: Float, steps: Float) Float:
    var acc = start
    var i = 0.0
    while i < steps:
        acc = f(acc)
        i = i + 1.0
    return acc

fn main() Int:
    scale := make_scaler(1.5, 2.0, true)
    shift := make_scaler(1.5, 2.0, false)
    counter := make_counter([1.0, 2.0, 3.0], "three", 0.5, true)
    small := make_counter([1.0], "one", 0.5, true)
    print(fold(scale, 1.0, 5.0))
    print(fold(shift, 10.0, 5.0))
    print(fold(counter, 1.0, 4.0))
    print(fold(small, 1.0, 4.0))
    print(show(7, 1.0))
    return 0"#,
    );
    let source = dir.join("direct_closures.ms");
    std::fs::write(&source, program).unwrap();
    let run = |direct: bool| {
        let work = dir.join(if direct { "direct" } else { "old" });
        std::fs::create_dir_all(&work).unwrap();
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_ms"));
        cmd.current_dir(&work)
            .env("MS_BACKEND", "llvm")
            .env("MS_LLVM_UNITS", "1")
            .env("MS_KEEP_LL", "1")
            .args(["build", source.to_str().unwrap(), "-o", "prog"]);
        if direct {
            cmd.env("MS_LLVM_DIRECT", "1");
        }
        let built = cmd.output().unwrap();
        assert!(
            built.status.success(),
            "{}",
            String::from_utf8_lossy(&built.stderr)
        );
        let out = Command::new(work.join("prog")).output().unwrap();
        let ir = std::fs::read_to_string(work.join("ms-keep.ll")).unwrap();
        (String::from_utf8_lossy(&out.stdout).into_owned(), ir)
    };
    let (old_out, old_ir) = run(false);
    let (new_out, new_ir) = run(true);
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(new_out, old_out);
    assert_eq!(new_out, "33.96875\n0\n0.0625\n3\n7\n");
    // Direct functions name their values `%vN`; the translation names them `%tN`.
    let direct = |ir: &str, what: &str| {
        ir.lines()
            .any(|l| l.trim_start().starts_with("%v") && l.contains(what))
    };
    for what in [
        // A closure object: heap block, then its code pointer, captures written as typed stores.
        "= call noalias align 16 ptr @\"msrt_alloc\"",
        // The call through the code pointer the closure holds.
        "= call double %v",
    ] {
        assert!(!direct(&old_ir, what), "the translation was used: {what}");
        assert!(direct(&new_ir, what), "not emitted directly: {what}");
    }
    // A runtime call whose result is not a register passes the address of a stack slot.
    assert!(
        new_ir.contains("call void @\"msrt_int_to_string\"(i64 %a0_0, i64 %v"),
        "no direct runtime call with a result slot"
    );
}
