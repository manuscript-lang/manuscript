//! `ms search_symbol` finds project declarations with their uses, then standard-library symbols.

use std::process::Command;

fn ms(dir: &std::path::Path, args: &[&str]) -> (i32, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("search_symbol")
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap();
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).into_owned(),
    )
}

#[test]
fn search_symbol_describes_project_and_standard_symbols() {
    let dir = std::env::temp_dir().join(format!("ms-cli-search-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("a.ms"),
        "def parse_config(text: String) -> Int:\n    return 1\n\ndef main() -> Int:\n    return parse_config(\"x\")\n",
    )
    .unwrap();

    let (status, out) = ms(&dir, &["parse_config"]);
    assert_eq!(status, 0);
    assert!(out.starts_with("parse_config  fn  a.ms:1:5\n"), "{out}");
    assert!(out.contains("  used (1): a.ms:5:12\n"), "{out}");

    let (_, out) = ms(&dir, &["--json", "parseconfig"]);
    assert!(out.contains("\"project_total\": 1"), "{out}");
    assert!(out.contains("\"origin\": \"project\""), "{out}");

    let (_, out) = ms(&dir, &["read", "file", "lines"]);
    assert!(out.contains("details: ms search_symbol"), "{out}");

    let (_, out) = ms(&dir, &["zzzzzzzz"]);
    assert!(
        out.starts_with("No project or standard-library symbol like"),
        "{out}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}
