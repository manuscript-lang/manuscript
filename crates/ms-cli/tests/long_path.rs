//! A project under a path longer than 260 characters (the Windows `MAX_PATH`) checks, formats,
//! lints, tests, runs and builds, and its program works with files at that depth.
use crate::common;
use std::path::Path;
use std::process::{Command, Output};

fn ms(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .output()
        .unwrap()
}

fn passes(output: &Output, what: &str) -> String {
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(
        output.status.success(),
        "{what}: {stdout}{}",
        String::from_utf8_lossy(&output.stderr)
    );
    stdout
}

#[test]
fn a_project_under_a_long_path_builds_tests_and_runs() {
    let mut dir = common::scratch("long-path");
    for part in ["a", "b", "c"] {
        dir.push(part.repeat(100));
    }
    std::fs::create_dir_all(&dir).unwrap();
    assert!(dir.as_os_str().len() > 300);
    let file = dir.join("main.ms");
    std::fs::write(&file, include_str!("long_path/main.ms")).unwrap();
    let file = file.to_str().unwrap();

    passes(&ms(&["check", file]), "check");
    passes(&ms(&["fmt", "--check", file]), "fmt");
    passes(&ms(&["lint", file]), "lint");
    let tested = passes(&ms(&["test", file]), "test");
    assert!(tested.contains("1 tests, 0 failed"), "{tested}");

    let ran = passes(&ms(&["run", file, "--", dir.to_str().unwrap()]), "run");
    assert!(ran.ends_with("true\nfalse\ndone\n"), "{ran}");

    let exe = dir.join(if cfg!(windows) { "out.exe" } else { "out" });
    passes(&ms(&["build", file, "-o", exe.to_str().unwrap()]), "build");
    let ran = Command::new(&exe)
        .arg(dir.to_str().unwrap())
        .output()
        .unwrap();
    assert!(passes(&ran, "built program").ends_with("done\n"));
    assert!(Path::new(&exe).is_file());
}
