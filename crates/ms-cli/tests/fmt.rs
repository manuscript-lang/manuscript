//! `ms fmt` rewrites source with the `ms-syntax` formatter and refuses source that does not parse.

use std::process::Command;

fn ms(dir: &std::path::Path, args: &[&str]) -> (i32, String, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap();
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

#[test]
fn fmt_rewrites_checks_and_rejects_invalid_source() {
    let dir = std::env::temp_dir().join(format!("ms-cli-fmt-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("a.ms"), "fn main() Unit:\n    let x = 1   \n").unwrap();
    std::fs::write(dir.join("bad.ms"), "fn main(:\n").unwrap();

    let (status, _, stderr) = ms(&dir, &["fmt", "--check", "a.ms"]);
    assert_eq!(status, 1, "{stderr}");
    let (status, _, stderr) = ms(&dir, &["fmt", "a.ms"]);
    assert_eq!(status, 0, "{stderr}");
    assert_eq!(
        std::fs::read_to_string(dir.join("a.ms")).unwrap(),
        "fn main() Unit:\n    let x = 1\n"
    );
    assert_eq!(ms(&dir, &["fmt", "--check", "a.ms"]).0, 0);

    let (status, _, stderr) = ms(&dir, &["fmt", "bad.ms"]);
    assert_eq!(status, 1);
    assert!(stderr.contains("bad.ms:"), "{stderr}");
    assert_eq!(
        std::fs::read_to_string(dir.join("bad.ms")).unwrap(),
        "fn main(:\n"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn fmt_rejects_invalid_utf8_without_rewriting() {
    let dir = std::env::temp_dir().join(format!("ms-cli-fmt-utf8-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = b"# caf\xe9   \nfn main() Unit:\n    let x = 1   \n";
    std::fs::write(dir.join("a.ms"), source).unwrap();
    for args in [&["fmt", "--check", "a.ms"][..], &["fmt", "a.ms"][..]] {
        let (status, _, stderr) = ms(&dir, args);
        assert_eq!(status, 1, "{stderr}");
        assert!(stderr.contains("source must be valid UTF-8"), "{stderr}");
    }
    assert_eq!(std::fs::read(dir.join("a.ms")).unwrap(), source);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn guide_prints_the_cheat_sheet() {
    let (status, stdout, _) = ms(&std::env::temp_dir(), &["guide"]);
    assert_eq!(status, 0);
    assert!(stdout.starts_with("# Manuscript cheat sheet"));
}
