//! The compiled-function cache: a rebuild reuses unchanged functions, recompiles an edited one,
//! survives a damaged cache file, and always produces the executable an uncached build does.
use crate::common;

use std::path::{Path, PathBuf};
use std::process::Command;

// Recursive, so that no function is folded into another before code generation.
const PROGRAM: &str = "fn a(x: Int) Int:
    if x <= 0: return 1
    return a(x - 1) + 2

fn b(x: Int) Int:
    if x <= 0: return 0
    return b(x - 1) + x % 3

fn c(x: Int) Int:
    if x <= 0: return 3
    return c(x - 1) + a(x) + b(x)

export fn main() Int:
    return c(10) % 100
";

fn build(root: &Path, cache: bool) -> (String, Vec<u8>) {
    // The whole-program cache of other versions lives beside the code cache; start from nothing.
    let _ = std::fs::remove_dir_all(root.join(".ms-cache/build"));
    let output = root.join(format!("program{}", std::env::consts::EXE_SUFFIX));
    let result = Command::new(env!("CARGO_BIN_EXE_ms"))
        .env("MS_TIMINGS", "1")
        .env("MS_CACHE", if cache { "on" } else { "off" })
        .env_remove("MS_BACKEND")
        .args(["build"])
        .arg(root.join("main.ms"))
        .args(["--build-type", "Debug", "-o"])
        .arg(&output)
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&result.stderr).into_owned();
    assert!(result.status.success(), "{:?}: {stderr}", result.status);
    (stderr, std::fs::read(output).unwrap())
}

/// `(hits, compiled)` from the timing line.
fn counts(stderr: &str) -> (usize, usize) {
    let line = stderr
        .lines()
        .find(|l| l.contains("code cache"))
        .unwrap_or_else(|| panic!("no cache line in {stderr}"));
    let numbers: Vec<usize> = line
        .split(|c: char| !c.is_ascii_digit())
        .filter_map(|n| n.parse().ok())
        .collect();
    (numbers[0], numbers[1])
}

fn exit_code(root: &Path) -> Option<i32> {
    let program: PathBuf = root.join(format!("program{}", std::env::consts::EXE_SUFFIX));
    Command::new(program).status().unwrap().code()
}

#[test]
fn rebuilds_reuse_unchanged_functions_and_match_an_uncached_build() {
    let root = common::scratch("code-cache");
    let source = root.join("main.ms");
    std::fs::write(&source, PROGRAM).unwrap();

    let (cold, cold_exe) = build(&root, true);
    let (hits, compiled) = counts(&cold);
    assert_eq!(hits, 0, "{cold}");
    assert!(compiled >= 4, "{cold}");
    let expected = exit_code(&root);

    let (warm, warm_exe) = build(&root, true);
    assert_eq!(counts(&warm), (compiled, 0), "{warm}");
    assert_eq!(warm_exe, cold_exe);
    assert_eq!(exit_code(&root), expected);

    // Editing one function recompiles only it.
    std::fs::write(&source, PROGRAM.replace("a(x - 1) + 2", "a(x - 1) + 3")).unwrap();
    let (edited, edited_exe) = build(&root, true);
    let (hits, recompiled) = counts(&edited);
    assert_eq!(recompiled, 1, "{edited}");
    assert_eq!(hits + recompiled, compiled, "{edited}");
    let (_, uncached_exe) = build(&root, false);
    assert_eq!(edited_exe, uncached_exe);
    assert_ne!(edited_exe, cold_exe);

    // A damaged cache file is an empty cache, not a failed build.
    let cache = root.join(".ms-cache/code");
    for entry in std::fs::read_dir(&cache).unwrap() {
        std::fs::write(entry.unwrap().path(), b"damaged").unwrap();
    }
    let (healed, healed_exe) = build(&root, true);
    assert_eq!(counts(&healed).0, 0, "{healed}");
    assert_eq!(healed_exe, uncached_exe);
}
