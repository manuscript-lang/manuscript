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
