//! `--build-type MinSizeRel` optimizes through LLVM and produces a working executable.

use std::process::Command;

#[test]
fn min_size_rel_builds_and_runs() {
    let dir = std::env::temp_dir().join(format!("ms-min-size-rel-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let source = dir.join("main.ms");
    std::fs::write(
        &source,
        "import stdout from \"@std/io.ms\"\n\nexport fn main() Int:\n    stdout().write(\"ok\\n\").get()\n    return 0\n",
    )
    .unwrap();
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("run")
        .arg(&source)
        .args(["--build-type", "MinSizeRel"])
        .output()
        .unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout), "ok\n");
}
