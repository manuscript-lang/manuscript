//! Independent check/lint inputs keep their own results and share only reporting.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ms-analysis-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn ms(dir: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap()
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
