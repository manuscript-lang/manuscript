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
        def main() -> Int:\n    let _ = stdout().write(\"hi\\n\")\n    return total(itemz: [1])\n";
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

#[test]
fn fix_repairs_habits_and_mutation_and_decimal_import() {
    let dir = std::env::temp_dir().join(format!("ms-cli-fix-habits-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = "type Color:\n    case Red\n    case Green\n\n\
        def pick() -> Color:\n    return Red()\n\n\
        def main() -> Int:\n    let fixed = 1\n    fixed = 2\n    let a = Some(1)\n    let b = true\n    let d = 1.5d\n    return fixed\n";
    std::fs::write(dir.join("a.ms"), source).unwrap();

    let (status, text) = ms(&["check", "a.ms", "--fix"], &dir);
    assert_eq!(status, Some(0), "{text}");
    let fixed = std::fs::read_to_string(dir.join("a.ms")).unwrap();
    assert!(
        fixed.starts_with("from \"@std/decimal.ms\" import Decimal\n"),
        "{fixed}"
    );
    assert!(fixed.contains("return Red\n"), "{fixed}");
    assert!(fixed.contains("var fixed = 1"), "{fixed}");
    assert!(fixed.contains("let a = some(1)"), "{fixed}");
    assert!(fixed.contains("let b = True"), "{fixed}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn guide_explains_codes_and_names_the_family_and_repair() {
    let dir = std::env::temp_dir();
    let (status, text) = ms(&["guide", "MS3060"], &dir);
    assert_eq!(status, Some(0), "{text}");
    assert!(text.contains("MS3060: Mutation"), "{text}");
    let (status, text) = ms(&["guide", "MS9999"], &dir);
    assert_eq!(status, Some(1), "{text}");
}

#[test]
fn fix_wraps_expressions_to_convert_types() {
    let dir = std::env::temp_dir().join(format!("ms-cli-fix-wrap-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = "def say(text: String) -> Unit:\n    return ()\n\n\
        export def main() -> Int:\n    let n = 3\n    let m = 4\n    let a: Float = n\n    let b: Float = n + m\n    let d: Float = 7\n    let e = 1.5 * n\n    say(text: n + 1)\n    return 0\n";
    std::fs::write(dir.join("a.ms"), source).unwrap();

    let (status, text) = ms(&["check", "a.ms", "--fix"], &dir);
    assert_eq!(status, Some(0), "{text}");
    let fixed = std::fs::read_to_string(dir.join("a.ms")).unwrap();
    assert!(fixed.contains("let a: Float = n.to_float()"), "{fixed}");
    assert!(
        fixed.contains("let b: Float = (n + m).to_float()"),
        "{fixed}"
    );
    assert!(fixed.contains("let d: Float = 7.0"), "{fixed}");
    assert!(fixed.contains("1.5 * n.to_float()"), "{fixed}");
    assert!(fixed.contains("say(text: f\"{n + 1}\")"), "{fixed}");
    let _ = std::fs::remove_dir_all(&dir);
}
