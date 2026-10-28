//! Element-wise list loops stay auto-vectorizable. The release build hands LLVM every element
//! address as a base pointer plus an offset; an `inttoptr` of a sum brings back "cannot identify
//! array bounds" and a 4x slowdown that no output comparison notices.

use std::process::Command;

const KERNELS: &str = include_str!("vectorized_loops/k.ms");

#[test]
fn element_wise_list_loops_are_vectorized() {
    if !ms_clif::llvm_available() {
        return;
    }
    let tools = ms_clif::link::llvm_tools().unwrap().unwrap();
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
    // Lines 3 and 6 of `k.ms` are the loops of `fma` and `scale`.
    for line in ["k.ms:3:0: vectorized loop", "k.ms:6:0: vectorized loop"] {
        assert!(
            text.contains(line),
            "a list loop is not vectorized:\n{text}"
        );
    }
}

/// A fault inside the AVX2 copy of a vectorized function reports the same exit code and source
/// frames as the baseline copy.
#[test]
fn per_cpu_copies_report_the_same_fault_frames() {
    if !ms_clif::llvm_available() {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-cpu-copies-{}", std::process::id()));
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
    let run = |level: &str| {
        let out = Command::new(dir.join("fault"))
            .env("MS_CPU_LEVEL", level)
            .output()
            .unwrap();
        (
            out.status.code(),
            String::from_utf8_lossy(&out.stderr).into_owned(),
        )
    };
    let (native, baseline) = (run("native"), run("baseline"));
    let _ = std::fs::remove_dir_all(&dir);
    assert_ne!(native.0, Some(0), "{}", native.1);
    assert_eq!(native, baseline);
    // One frame for the function: the dispatcher between the caller and the copy leaves none.
    assert_eq!(native.1.matches(" in scale").count(), 1, "{}", native.1);
    assert!(native.1.contains("fault.ms:3 in scale"), "{}", native.1);
    assert!(native.1.contains("fault.ms:8 in main"), "{}", native.1);
}

/// `MS_VECTORIZE=off` leaves the list loops scalar.
#[test]
fn vectorize_off_keeps_loops_scalar() {
    if !ms_clif::llvm_available() {
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
    assert!(
        !ir.contains(".avx2"),
        "per-CPU copies with vectorization off"
    );
}

/// A search loop that returns early cannot be vectorized, so its function keeps one copy and no
/// dispatcher; a single-exit sum loop gets both copies.
#[test]
fn only_vectorizable_loops_get_per_cpu_copies() {
    if !ms_clif::llvm_available() {
        return;
    }
    let dir = std::env::temp_dir().join(format!("ms-search-loop-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("search.ms"),
        include_str!("vectorized_loops/search.ms"),
    )
    .unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .env("MS_BACKEND", "llvm")
        .env("MS_KEEP_LL", "1")
        .args(["build", "search.ms", "-o", "search"])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let ir = std::fs::read_to_string(dir.join("ms-keep.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert!(
        ir.contains("@\"total#2.avx2\""),
        "the sum loop has no AVX2 copy"
    );
    assert!(
        !ir.contains("@\"find#1.avx2\"") && !ir.contains("@\"find#1.base\""),
        "a search loop with an early return got per-CPU copies"
    );
}
