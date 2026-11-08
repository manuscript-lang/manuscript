//! A standard module imported from the wrong folder names the right path.

use std::process::Command;

#[test]
fn a_standard_module_under_the_wrong_folder_suggests_its_path() {
    let dir = std::env::temp_dir().join(format!("ms-cli-import-hints-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("main.ms"),
        include_str!("import_hints/wrong_folder.ms"),
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["check", "main.ms"])
        .current_dir(&dir)
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(output.status.code(), Some(1), "{stderr}");
    assert!(
        stderr.contains(
            "unknown standard module @std/json/json.ms; did you mean '@std/data/json.ms'?"
        ),
        "{stderr}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

fn check_stderr(name: &str, source: &str) -> String {
    let dir = std::env::temp_dir().join(format!("ms-cli-import-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("main.ms"), source).unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["check", "main.ms"])
        .current_dir(&dir)
        .output()
        .unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[test]
fn a_standard_import_without_its_extension_suggests_the_extension() {
    let stderr = check_stderr(
        "std-ext",
        "import arguments from \"@std/os/env\"\nexport fn main() Int:\n    return 0\n",
    );
    assert!(
        stderr.contains("did you mean '@std/os/env.ms'?"),
        "{stderr}"
    );
}

#[test]
fn a_directory_import_does_not_suggest_a_nonsense_file() {
    for (path, bad) in [("./", "./.ms"), ("./b.ms/", "b.ms/.ms"), (".", "\"./.\"")] {
        let stderr = check_stderr(
            "dir-import",
            &format!("import b from \"{path}\"\nexport fn main() Int:\n    return 0\n"),
        );
        assert!(!stderr.contains(bad), "{path}: {stderr}");
        assert!(stderr.contains("./name.ms"), "{path}: {stderr}");
    }
}
