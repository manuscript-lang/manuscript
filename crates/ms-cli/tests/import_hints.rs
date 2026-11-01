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
