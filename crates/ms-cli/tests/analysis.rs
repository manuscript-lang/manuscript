//! Independent check/lint inputs keep their own results and share only reporting.

use crate::common;

use common::scratch;
use std::path::Path;
use std::process::{Command, Output};

// Exercise raw byte filenames on Linux; APFS rejects their creation.
#[cfg(target_os = "linux")]
#[test]
fn discovered_source_names_are_never_replaced() {
    use std::ffi::OsString;
    use std::os::unix::{ffi::OsStringExt, fs::symlink};

    let dir = scratch("invalid-source-name");
    std::fs::write(dir.join("\u{fffd}.ms"), "").unwrap();
    std::fs::write(dir.join(".ms"), "").unwrap();
    std::fs::write(dir.join(OsString::from_vec(b"\xff.txt".to_vec())), [0xff]).unwrap();
    let hidden = dir.join(OsString::from_vec(b".\xff".to_vec()));
    std::fs::create_dir(&hidden).unwrap();
    std::fs::write(hidden.join("bad.ms"), [0xff]).unwrap();
    std::fs::create_dir(dir.join("empty")).unwrap();
    symlink(
        dir.join("empty"),
        dir.join(OsString::from_vec(b"linked-\xff.ms".to_vec())),
    )
    .unwrap();

    for command in ["check", "lint"] {
        let output = ms(&dir, &[command, "."]);
        assert!(output.status.success(), "{command}: {output:?}");
        if command == "check" {
            assert_eq!(
                String::from_utf8(output.stdout).unwrap(),
                "Checked .ms\nChecked \u{fffd}.ms\n"
            );
        }
    }

    std::fs::write(dir.join(OsString::from_vec(b"\xff.ms".to_vec())), [0xff]).unwrap();
    for command in ["check", "lint"] {
        let output = ms(&dir, &[command, "."]);
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert_eq!(output.status.code(), Some(1), "{command}: {output:?}");
        assert!(stderr.contains("source filename"), "{stderr}");
        assert!(stderr.contains("is not valid UTF-8;"), "{stderr}");
        assert!(stderr.contains("rename it using UTF-8"), "{stderr}");

        let output = ms(&dir, &[command, ".", "--json"]);
        assert_eq!(output.status.code(), Some(1), "{command}: {output:?}");
        assert!(output.stderr.is_empty(), "{command}: {output:?}");
        let document = ms_json::parse(std::str::from_utf8(&output.stdout).unwrap()).unwrap();
        let diagnostics = document.get("diagnostics").unwrap().as_array().unwrap();
        assert_eq!(diagnostics.len(), 1, "{document:?}");
        assert_eq!(
            diagnostics[0].get("phase").unwrap().as_str(),
            Some("resolution")
        );

        let output = ms(&dir, &[command, ".", "\u{fffd}.ms"]);
        assert_eq!(output.status.code(), Some(1), "{command}: {output:?}");
        if command == "check" {
            assert_eq!(
                String::from_utf8(output.stdout).unwrap(),
                "Checked \u{fffd}.ms\n"
            );
        }
    }

    std::fs::remove_file(dir.join(OsString::from_vec(b"\xff.ms".to_vec()))).unwrap();
    let nested = dir.join(OsString::from_vec(b"nested-\xff".to_vec()));
    std::fs::create_dir(&nested).unwrap();
    std::fs::write(nested.join("ms.toml"), "not a manifest").unwrap();
    std::fs::write(nested.join("bad.ms"), [0xff]).unwrap();
    for command in ["check", "lint"] {
        let output = ms(&dir, &[command, "."]);
        assert!(output.status.success(), "{command}: {output:?}");
    }
    let _ = std::fs::remove_dir_all(dir);
}

fn ms(dir: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap()
}

#[test]
fn collection_diagnostic_fixes_identify_the_original_source() {
    for crlf in [false, true] {
        for targets in [
            vec!["a/bad.ms", "b/bad.ms"],
            vec!["."],
            vec!["a/entry.ms", "b/entry.ms"],
        ] {
            let dir = scratch("collection-fix-paths");
            let original = include_str!("check_fix/float_fix_unicode.ms");
            let source = if crlf {
                original.replace('\n', "\r\n")
            } else {
                original.to_string()
            };
            for name in ["a", "b"] {
                std::fs::create_dir(dir.join(name)).unwrap();
                std::fs::write(dir.join(name).join("bad.ms"), &source).unwrap();
                std::fs::write(
                    dir.join(name).join("entry.ms"),
                    include_str!("check_fix/import_main.ms"),
                )
                .unwrap();
            }
            // A same-named file at the invocation root must never receive these edits.
            std::fs::write(dir.join("bad.ms"), "").unwrap();
            let mut args = vec!["check"];
            args.extend(targets.iter().copied());
            args.push("--json");
            let output = ms(&dir, &args);
            assert_eq!(output.status.code(), Some(1), "{output:?}");
            let document = ms_json::parse(std::str::from_utf8(&output.stdout).unwrap()).unwrap();
            let diagnostics = document.get("diagnostics").unwrap().as_array().unwrap();
            assert_eq!(diagnostics.len(), 2, "{document:?}");
            for issue in diagnostics {
                let position = issue.get("position").unwrap();
                let file = position.get("file").unwrap().as_str().unwrap();
                assert!(["a/bad.ms", "b/bad.ms"].contains(&file), "{issue:?}");
                let fix = issue.get("fix").unwrap();
                let start = fix.get("position").unwrap();
                let end = fix.get("end").unwrap();
                assert_eq!(start, position, "{issue:?}");
                assert_eq!(end.get("file").unwrap().as_str(), Some(file), "{issue:?}");
                let begin = start.get("offset").unwrap().as_i64().unwrap() as usize;
                let stop = end.get("offset").unwrap().as_i64().unwrap() as usize;
                assert_eq!(&source[begin..stop], "n");
                let mut fixed = std::fs::read_to_string(dir.join(file)).unwrap();
                fixed.replace_range(
                    begin..stop,
                    fix.get("replacement").unwrap().as_str().unwrap(),
                );
                std::fs::write(dir.join(file), fixed).unwrap();
            }
            assert_eq!(std::fs::read_to_string(dir.join("bad.ms")).unwrap(), "");
            let rechecked = ms(&dir, &args);
            assert!(rechecked.status.success(), "{rechecked:?}");
            std::fs::remove_dir_all(dir).unwrap();
        }
    }
}

#[test]
fn mixed_inputs_keep_successes_and_report_each_failure_once() {
    let dir = scratch("mixed");
    std::fs::write(dir.join("good.ms"), "fn value() Int:\n    return 1\n").unwrap();
    std::fs::write(
        dir.join("bad.ms"),
        "fn value() Int:\n    return \"wrong\"\n",
    )
    .unwrap();
    let args = ["check", "good.ms", "missing.ms", "bad.ms", "./good.ms"];
    let output = ms(&dir, &args);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(String::from_utf8_lossy(&output.stdout), "Checked good.ms\n");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(
        stderr.matches("expected Int, found String").count(),
        1,
        "{stderr}"
    );
    assert_eq!(stderr.matches("file not found:").count(), 1, "{stderr}");
    assert!(stderr.contains("2 errors; fix them and re-run"), "{stderr}");
    assert!(stderr.find("bad.ms:").unwrap() < stderr.find("missing.ms:").unwrap());

    let mut json_args = args.to_vec();
    json_args.push("--json");
    let output = ms(&dir, &json_args);
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stderr.is_empty());
    let document = ms_json::parse(std::str::from_utf8(&output.stdout).unwrap()).unwrap();
    let diagnostics = document.get("diagnostics").unwrap().as_array().unwrap();
    assert_eq!(diagnostics.len(), 2);
    assert_eq!(
        diagnostics[0].get("phase").unwrap().as_str().unwrap(),
        "type"
    );
    assert_eq!(
        diagnostics[1].get("phase").unwrap().as_str().unwrap(),
        "resolution"
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn lint_deduplicates_shared_imports_and_keeps_findings_from_valid_inputs() {
    let dir = scratch("lint");
    std::fs::write(
        dir.join("shared.ms"),
        include_str!("analysis/lint-shared.ms"),
    )
    .unwrap();
    for name in ["a.ms", "b.ms"] {
        std::fs::write(
            dir.join(name),
            "import value from \"./shared.ms\"\n\nfn use_value() Int:\n    return value()\n",
        )
        .unwrap();
    }
    let output = ms(&dir, &["lint", "a.ms", "b.ms"]);
    assert_eq!(output.status.code(), Some(0), "an unused import only warns");
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(stderr.matches("MSL102").count(), 1, "{stderr}");
    assert!(stderr.contains("1 warning;"), "{stderr}");
    assert!(!stderr.contains("fix them and re-run"), "{stderr}");
    let output = ms(&dir, &["lint", "a.ms", "b.ms", "--deny-warnings"]);
    assert_eq!(output.status.code(), Some(1));
    let output = ms(&dir, &["lint", "a.ms", "b.ms", "--json"]);
    assert_eq!(output.status.code(), Some(0));
    let document = ms_json::parse(std::str::from_utf8(&output.stdout).unwrap()).unwrap();
    let diagnostics = document.get("diagnostics").unwrap().as_array().unwrap();
    assert_eq!(
        diagnostics[0].get("severity").unwrap().as_str().unwrap(),
        "warning"
    );

    std::fs::write(dir.join("bad.ms"), "fn invalid() Int:\n    return false\n").unwrap();
    let output = ms(&dir, &["lint", "b.ms", "bad.ms", "a.ms", "--json"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stderr.is_empty());
    let document = ms_json::parse(std::str::from_utf8(&output.stdout).unwrap()).unwrap();
    let diagnostics = document.get("diagnostics").unwrap().as_array().unwrap();
    assert_eq!(diagnostics.len(), 2, "{document:?}");
    assert_eq!(
        diagnostics[0].get("phase").unwrap().as_str().unwrap(),
        "type"
    );
    assert_eq!(
        diagnostics[1].get("code").unwrap().as_str().unwrap(),
        "MSL102"
    );
    let _ = std::fs::remove_dir_all(dir);
}

/// A directory without sources says so rather than succeeding silently.
#[test]
fn directories_without_sources_report_none() {
    let dir = scratch("empty");
    for command in ["check", "lint", "fmt"] {
        let out = ms(&dir, &[command, "."]);
        let stderr = String::from_utf8_lossy(&out.stderr);
        assert!(out.status.success(), "{command}: {stderr}");
        assert!(stderr.contains("no .ms files found"), "{command}: {stderr}");
    }
}

#[test]
fn check_json_with_text_carries_the_terminal_output() {
    let dir = scratch("check-with-text");
    std::fs::write(dir.join("bad.ms"), "fn invalid() Int:\n    return false\n").unwrap();
    std::fs::write(dir.join("ok.ms"), "fn main() Unit:\n    let _x = 1\n").unwrap();
    for file in ["bad.ms", "ok.ms"] {
        let text = ms(&dir, &["check", file]);
        let json = ms(&dir, &["check", file, "--json", "--with-text"]);
        assert_eq!(json.status.code(), text.status.code(), "{file}");
        assert!(json.stderr.is_empty(), "{file}");
        let document = ms_json::parse(std::str::from_utf8(&json.stdout).unwrap()).unwrap();
        let carried = document.get("text").unwrap();
        for (stream, bytes) in [("stdout", &text.stdout), ("stderr", &text.stderr)] {
            assert_eq!(
                carried.get(stream).unwrap().as_str().unwrap(),
                String::from_utf8_lossy(bytes),
                "{file} {stream}"
            );
        }
    }
    let plain = ms(&dir, &["check", "bad.ms", "--json"]);
    let document = ms_json::parse(std::str::from_utf8(&plain.stdout).unwrap()).unwrap();
    assert!(document.get("text").is_none());
    let misuse = ms(&dir, &["check", "bad.ms", "--with-text"]);
    assert_eq!(misuse.status.code(), Some(2));
}
