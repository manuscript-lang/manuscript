//! A compiled program completes under an address-space limit: the heap reserves part of what the
//! limit leaves instead of all of it, so thread stacks, task stacks and the system allocator still
//! find room.

#[cfg(target_os = "linux")]
use std::process::Command;

#[cfg(target_os = "linux")]
const PROGRAM: &str = include_str!("address_limit/main.ms");

#[cfg(target_os = "linux")]
#[test]
fn a_program_with_threads_tasks_and_large_strings_runs_under_ulimit_v() {
    let root = std::env::temp_dir().join(format!("ms-address-limit-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let source = root.join("main.ms");
    let binary = root.join("main");
    std::fs::write(&source, PROGRAM).unwrap();
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args([
            "build",
            source.to_str().unwrap(),
            "-o",
            binary.to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );

    // 5 GiB: far below the 256 GiB the heap asks for. A heap that took the largest size that fits
    // (about 4 GiB here) starved the thread and task stacks and the program faulted.
    let run = Command::new("sh")
        .arg("-c")
        .arg("ulimit -v 5242880 && exec \"$0\"")
        .arg(&binary)
        .env("MS_THREADS", "4")
        .output()
        .unwrap();
    assert!(
        run.status.success(),
        "{:?}\n{}",
        run.status,
        String::from_utf8_lossy(&run.stderr)
    );
    std::fs::remove_dir_all(root).unwrap();
}
