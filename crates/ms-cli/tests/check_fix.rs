//! `ms check --fix` applies the machine-applicable `fix` edits of its diagnostics.

use std::process::Command;

fn ms(args: &[&str], dir: &std::path::Path) -> (Option<i32>, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap();
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    (out.status.code(), text)
}

#[test]
fn fix_renames_misspellings_and_adds_imports() {
    let dir = std::env::temp_dir().join(format!("ms-cli-fix-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = "def total(items: List[Int]) -> Int:\n    let sum = 0\n    return sumn\n\n\
        def main() -> Int:\n    stdout().write(\"hi\\n\")\n    return total(itemz: [1])\n";
    std::fs::write(dir.join("a.ms"), source).unwrap();

    let (status, text) = ms(&["check", "a.ms", "--json"], &dir);
    assert_eq!(status, Some(1), "{text}");
    assert!(text.contains("\"replacement\": \"sum\""), "{text}");

    let (status, text) = ms(&["check", "a.ms", "--fix"], &dir);
    assert_eq!(status, Some(0), "{text}");
    assert!(text.contains("applied 3 fixes in 1 file"), "{text}");
    let fixed = std::fs::read_to_string(dir.join("a.ms")).unwrap();
    assert!(
        fixed.starts_with("from \"@std/io.ms\" import stdout\n"),
        "{fixed}"
    );
    assert!(fixed.contains("return sum\n"), "{fixed}");
    assert!(fixed.contains("total(items: [1])"), "{fixed}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn fix_rejects_watch_and_other_commands() {
    let dir = std::env::temp_dir();
    let (status, text) = ms(&["check", "x.ms", "--fix", "--watch"], &dir);
    assert_eq!(status, Some(2), "{text}");
    let (status, text) = ms(&["build", "x.ms", "--fix"], &dir);
    assert_eq!(status, Some(2), "{text}");
}
