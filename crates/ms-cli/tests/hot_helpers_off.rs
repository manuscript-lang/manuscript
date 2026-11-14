//! A runtime helper that fills an out slot keeps the call and its result when the pure runtime
//! helpers are not linked into the program (`MS_RT_HOT=0`): the declaration may not say the call
//! only reads memory.
use crate::common;

use std::process::Command;

fn run(hot: &str) -> String {
    let root = common::scratch(&format!("hot-off-{hot}"));
    std::fs::write(
        root.join("main.ms"),
        include_str!("hot_helpers_off/main.ms"),
    )
    .unwrap();
    let output = root.join(format!("program{}", std::env::consts::EXE_SUFFIX));
    let build = Command::new(env!("CARGO_BIN_EXE_ms"))
        .env_remove("MS_BACKEND")
        .env("MS_RT_HOT", hot)
        .arg("build")
        .arg(root.join("main.ms"))
        .args(["--build-type", "Release", "-o"])
        .arg(&output)
        .output()
        .unwrap();
    assert!(
        build.status.success(),
        "{}",
        String::from_utf8_lossy(&build.stderr)
    );
    let run = Command::new(&output).output().unwrap();
    let _ = std::fs::remove_dir_all(root);
    String::from_utf8_lossy(&run.stdout).replace("\r\n", "\n")
}

#[test]
fn out_slot_helpers_survive_without_the_hot_library() {
    let want = "104 12349 102\n";
    assert_eq!(run("0"), want);
    assert_eq!(run("1"), want);
}
