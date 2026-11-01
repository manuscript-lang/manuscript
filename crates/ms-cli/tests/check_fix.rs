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
    let source = "fn total(items: List[Int]) Int:\n\
        \x20   let sum = 0\n\
        \x20   return sumn\n\
        \n\
        fn main() Int:\n\
        \x20   let _ = stdout().write(\"hi\\n\")\n\
        \x20   return total(itemz: [1])\n\
        ";
    std::fs::write(dir.join("a.ms"), source).unwrap();

    let (status, text) = ms(&["check", "a.ms", "--json"], &dir);
    assert_eq!(status, Some(1), "{text}");
    assert!(text.contains("\"replacement\": \"sum\""), "{text}");

    let (status, text) = ms(&["check", "a.ms", "--fix"], &dir);
    assert_eq!(status, Some(0), "{text}");
    assert!(text.contains("applied 3 fixes in 1 file"), "{text}");
    let fixed = std::fs::read_to_string(dir.join("a.ms")).unwrap();
    assert!(
        fixed.starts_with("import stdout from \"@std/io/io.ms\"\n"),
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
    let source = "type Color:\n\
        \x20   case Red\n\
        \x20   case Green\n\
        \n\
        fn pick() Color:\n\
        \x20   return Red()\n\
        \n\
        fn main() Int:\n\
        \x20   let fixed = 1\n\
        \x20   fixed = 2\n\
        \x20   let _a: Int? = None\n\
        \x20   let _b = true\n\
        \x20   let _d = 1.5d\n\
        \x20   return fixed\n\
        ";
    std::fs::write(dir.join("a.ms"), source).unwrap();

    let (status, text) = ms(&["check", "a.ms", "--fix"], &dir);
    assert_eq!(status, Some(0), "{text}");
    let fixed = std::fs::read_to_string(dir.join("a.ms")).unwrap();
    assert!(
        fixed.starts_with("import Decimal from \"@std/math/decimal.ms\"\n"),
        "{fixed}"
    );
    assert!(fixed.contains("return Red\n"), "{fixed}");
    assert!(fixed.contains("var fixed = 1"), "{fixed}");
    assert!(fixed.contains("let _a: Int? = none"), "{fixed}");
    assert!(fixed.contains("let _b = true"), "{fixed}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn guide_explains_codes_and_names_the_family_and_repair() {
    let dir = std::env::temp_dir();
    let (status, text) = ms(&["guide", "MS3060"], &dir);
    assert_eq!(status, Some(0), "{text}");
    assert!(text.contains("MS3060: Mutation"), "{text}");
    let (status, text) = ms(&["guide", "MS3000.1"], &dir);
    assert_eq!(status, Some(0), "{text}");
    assert!(text.contains("MS3000.1: Unused local binding"), "{text}");
    let (status, text) = ms(&["guide", "MS9999"], &dir);
    assert_eq!(status, Some(1), "{text}");
}

#[test]
fn fix_wraps_expressions_to_convert_types() {
    let dir = std::env::temp_dir().join(format!("ms-cli-fix-wrap-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = "fn say(text: String) Unit:\n\
        \x20   return unit\n\
        \n\
        export fn main() Int:\n\
        \x20   let n = 3\n\
        \x20   let m = 4\n\
        \x20   let _a: Float = n\n\
        \x20   let _b: Float = n + m\n\
        \x20   let _d: Float = 7\n\
        \x20   let _e = 1.5 * n\n\
        \x20   say(text: n + 1)\n\
        \x20   return 0\n\
        ";
    std::fs::write(dir.join("a.ms"), source).unwrap();

    let (status, text) = ms(&["check", "a.ms", "--fix"], &dir);
    assert_eq!(status, Some(0), "{text}");
    let fixed = std::fs::read_to_string(dir.join("a.ms")).unwrap();
    assert!(fixed.contains("let _a: Float = n.to_float()"), "{fixed}");
    assert!(
        fixed.contains("let _b: Float = (n + m).to_float()"),
        "{fixed}"
    );
    assert!(fixed.contains("let _d: Float = 7.0"), "{fixed}");
    assert!(fixed.contains("1.5 * n.to_float()"), "{fixed}");
    assert!(fixed.contains("say(text: \"{n + 1}\")"), "{fixed}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn check_json_carries_the_fix_that_fix_applies() {
    let dir = std::env::temp_dir().join(format!("ms-cli-check-json-fix-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = include_str!("check_fix/float_fix.ms");
    std::fs::write(dir.join("a.ms"), source).unwrap();

    let (status, text) = ms(&["check", "a.ms", "--json"], &dir);
    assert_eq!(status, Some(1), "{text}");
    assert!(text.contains("\"fix\""), "{text}");
    assert!(text.contains("\"replacement\": \"n.to_float()\""), "{text}");
    assert_eq!(std::fs::read_to_string(dir.join("a.ms")).unwrap(), source);

    let (status, text) = ms(&["check", "a.ms", "--fix"], &dir);
    assert_eq!(status, Some(0), "{text}");
    let fixed = std::fs::read_to_string(dir.join("a.ms")).unwrap();
    assert!(fixed.contains("let _a: Float = n.to_float()"), "{fixed}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[cfg(unix)]
#[test]
fn directory_symlink_named_like_source_is_skipped() {
    let dir = std::env::temp_dir().join(format!("ms-cli-dir-link-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("real")).unwrap();
    std::os::unix::fs::symlink("real", dir.join("linked.ms")).unwrap();

    for args in [
        &["fmt", ".", "--check", "--json"][..],
        &["check", ".", "--json"],
        &["lint", ".", "--json"],
    ] {
        let (status, text) = ms(args, &dir);
        assert_eq!(status, Some(0), "{args:?}: {text}");
        assert!(!text.contains("is a directory"), "{args:?}: {text}");
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn json_diagnostics_carry_the_sub_code_of_their_cause() {
    let dir = std::env::temp_dir().join(format!("ms-cli-subcode-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("a.ms"),
        "export fn main() Int:\n    let unused = 1\n    return 0\n",
    )
    .unwrap();
    let (status, text) = ms(&["check", "a.ms", "--json"], &dir);
    assert_eq!(status, Some(1), "{text}");
    assert!(text.contains("\"code\": \"MS3000\""), "{text}");
    assert!(text.contains("\"subcode\": \"MS3000.1\""), "{text}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn fix_renames_a_misspelled_member() {
    let dir = std::env::temp_dir().join(format!("ms-cli-fix-member-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = "fn main() Int:\n    let xs = [1, 2]\n    return xs.lenght() + xs.len()\n";
    std::fs::write(dir.join("a.ms"), source).unwrap();
    let (status, text) = ms(&["check", "a.ms", "--fix"], &dir);
    assert_eq!(status, Some(0), "{text}");
    let fixed = std::fs::read_to_string(dir.join("a.ms")).unwrap();
    assert!(fixed.contains("xs.length() + xs.length()"), "{fixed}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn error_with_a_string_gives_one_diagnostic_naming_fail() {
    let dir = std::env::temp_dir().join(format!("ms-cli-error-string-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("a.ms"), "test \"x\":\n    error(\"boom\")\n").unwrap();
    let (status, text) = ms(&["check", "a.ms"], &dir);
    assert_eq!(status, Some(1), "{text}");
    assert!(text.contains("try fail("), "{text}");
    assert!(text.contains("1 error;"), "{text}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn fix_removes_only_a_trailing_semicolon() {
    let dir = std::env::temp_dir().join(format!("ms-cli-fix-semi-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("a.ms"),
        "export fn main() Int:\n    let a = 1;  # note\n    return a\n",
    )
    .unwrap();
    let (status, text) = ms(&["check", "a.ms", "--fix"], &dir);
    assert_eq!(status, Some(0), "{text}");
    let fixed = std::fs::read_to_string(dir.join("a.ms")).unwrap();
    assert!(fixed.contains("let a = 1  # note\n"), "{fixed}");

    // A mid-line semicolon has no fix: deleting it would fuse two statements.
    let source = "export fn main() Int:\n    let a = 1; let b = 2\n    return a\n";
    std::fs::write(dir.join("b.ms"), source).unwrap();
    let (status, text) = ms(&["check", "b.ms", "--fix"], &dir);
    assert_eq!(status, Some(1), "{text}");
    assert_eq!(std::fs::read_to_string(dir.join("b.ms")).unwrap(), source);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn unknown_standard_module_suggests_the_extended_name() {
    let dir = std::env::temp_dir().join(format!("ms-cli-mod-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("a.ms"), "import x from \"@std/testing.ms\"\n").unwrap();
    let (_, text) = ms(&["check", "a.ms"], &dir);
    assert!(text.contains("did you mean '@std/test/test.ms'?"), "{text}");
    let _ = std::fs::remove_dir_all(&dir);
}
