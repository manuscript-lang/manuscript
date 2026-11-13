//! Element-wise list loops stay auto-vectorizable. The release build hands LLVM every element
//! address as a base pointer plus an offset; an `inttoptr` of a sum brings back "cannot identify
//! array bounds" and a 4x slowdown that no output comparison notices.

use std::process::Command;

const KERNELS: &str = include_str!("vectorized_loops/k.ms");

#[test]
fn element_wise_list_loops_are_vectorized() {
    if !ms_build::llvm_available(&ms_cli::engine::build_options_from_env()) {
        return;
    }
    let tools = ms_clif::link::llvm_tools(&ms_cli::engine::build_options_from_env())
        .unwrap()
        .unwrap();
    let dir = std::env::temp_dir().join(format!("ms-vectorized-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("k.ms"), KERNELS).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "llvm")
        .env("MS_KEEP_LL", "1")
        .args(["build", "k.ms", "-o", "k"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    // Program functions are internal; external linkage keeps them from being inlined and folded.
    let ir = std::fs::read_to_string(dir.join("ms-keep.ll")).unwrap();
    std::fs::write(
        dir.join("external.ll"),
        ir.replace("define internal ", "define "),
    )
    .unwrap();
    let opt = tools.join(format!("opt{}", std::env::consts::EXE_SUFFIX));
    let remarks = Command::new(opt)
        .current_dir(&dir)
        .args([
            "-passes=default<O3>",
            "-pass-remarks=loop-vectorize",
            "-pass-remarks-missed=loop-vectorize",
            "-disable-output",
            "external.ll",
        ])
        .output()
        .unwrap();
    let text = String::from_utf8_lossy(&remarks.stderr).into_owned();
    let _ = std::fs::remove_dir_all(&dir);
    assert!(remarks.status.success(), "{text}");
    // LLVM reports a loop at the line of its body: lines 3 and 7 of `k.ms` are the loops of `fma`
    // and `scale`.
    for line in ["k.ms:3:0: vectorized loop", "k.ms:7:0: vectorized loop"] {
        assert!(
            text.contains(line),
            "a list loop is not vectorized:\n{text}"
        );
    }
}

/// A fault inside a vectorized function reports its exit code and source frames.
#[test]
fn vectorized_function_reports_fault_frames() {
    if !ms_build::llvm_available(&ms_cli::engine::build_options_from_env()) {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-vector-fault-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("fault.ms"),
        include_str!("vectorized_loops/fault.ms"),
    )
    .unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "llvm")
        .args(["build", "fault.ms", "-o", "fault"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let out = Command::new(dir.join("fault")).output().unwrap();
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    let _ = std::fs::remove_dir_all(&dir);
    assert_ne!(out.status.code(), Some(0), "{stderr}");
    assert_eq!(stderr.matches(" in scale").count(), 1, "{stderr}");
    assert!(stderr.contains("fault.ms:3 in scale"), "{stderr}");
    assert!(stderr.contains("fault.ms:8 in main"), "{stderr}");
}

/// `MS_VECTORIZE=off` leaves the list loops scalar.
#[test]
fn vectorize_off_keeps_loops_scalar() {
    if !ms_build::llvm_available(&ms_cli::engine::build_options_from_env()) {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-vectorize-off-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("k.ms"), KERNELS).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "llvm")
        .env("MS_KEEP_LL", "1")
        .env("MS_VECTORIZE", "off")
        .args(["build", "k.ms", "-o", "k"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let ir = std::fs::read_to_string(dir.join("ms-keep.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert!(!ir.contains(".avx2"), "per-CPU copies were emitted");
}

/// Release builds emit one copy of each function: no per-CPU copies, dispatcher or CPU query.
#[test]
fn release_builds_emit_no_per_cpu_copies() {
    if !ms_build::llvm_available(&ms_cli::engine::build_options_from_env()) {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-one-copy-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("k.ms"), KERNELS).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "llvm")
        .env("MS_KEEP_LL", "1")
        .args(["build", "k.ms", "-o", "k"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let ir = std::fs::read_to_string(dir.join("ms-keep.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    for banned in [".avx2", "msrt_cpu_level", "target-features"] {
        assert!(!ir.contains(banned), "the IR mentions {banned}");
    }
}

/// On aarch64 the element-wise loops compile to NEON vector instructions. There are no per-CPU
/// copies there: NEON is part of the baseline.
#[cfg(target_arch = "aarch64")]
#[test]
fn element_wise_list_loops_use_neon() {
    if !ms_build::llvm_available(&ms_cli::engine::build_options_from_env()) {
        return;
    }
    let tools = ms_clif::link::llvm_tools(&ms_cli::engine::build_options_from_env())
        .unwrap()
        .unwrap();
    let dir = std::env::temp_dir().join(format!("ms-neon-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("k.ms"), KERNELS).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "llvm")
        .env("MS_KEEP_LL", "1")
        .args(["build", "k.ms", "-o", "k"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let ir = std::fs::read_to_string(dir.join("ms-keep.ll")).unwrap();
    std::fs::write(
        dir.join("external.ll"),
        ir.replace("define internal ", "define "),
    )
    .unwrap();
    let exe = |name: &str| tools.join(format!("{name}{}", std::env::consts::EXE_SUFFIX));
    let opt = Command::new(exe("opt"))
        .current_dir(&dir)
        .args(["-passes=default<O3>", "external.ll", "-o", "k.bc"])
        .output()
        .unwrap();
    assert!(
        opt.status.success(),
        "{}",
        String::from_utf8_lossy(&opt.stderr)
    );
    let llc = Command::new(exe("llc"))
        .current_dir(&dir)
        .args(["-filetype=asm", "k.bc", "-o", "k.s"])
        .output()
        .unwrap();
    assert!(
        llc.status.success(),
        "{}",
        String::from_utf8_lossy(&llc.stderr)
    );
    let asm = std::fs::read_to_string(dir.join("k.s")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    // Packed arithmetic: `.2d` for `scale` (Float; LLVM turns `a * 2.0` into `a + a`), `.4s` for
    // `fma` (Float32).
    for lane in [".2d", ".4s"] {
        assert!(
            asm.lines().any(|l| {
                let l = l.trim_start();
                // ELF prints `fadd\tv0.2d`; Mach-O prints `fadd.2d\tv0`.
                ["fmul", "fmla", "fadd"].iter().any(|op| {
                    l.strip_prefix(op)
                        .is_some_and(|rest| rest.starts_with("\tv") || rest.starts_with('.'))
                }) && l.contains(lane)
            }),
            "no NEON {lane} arithmetic in:\n{asm}"
        );
    }
}
