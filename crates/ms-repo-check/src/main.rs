//! `repo-check`: repository invariants that no compiler or test run enforces.
//! Run from the repository root; exits nonzero listing every violation.

mod licenses;
mod nested;
mod portability;
mod release;
mod unsafe_boundary;

use ms_syntax::parser::parse;
use std::path::Path;
use std::process::{Command, ExitCode};
use std::sync::Arc;

fn main() -> ExitCode {
    // Deeply nested sources need more stack than the default main thread has.
    let handle = std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(run)
        .expect("spawn");
    handle.join().unwrap_or(ExitCode::from(2))
}

fn run() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    match arguments.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [] => {}
        ["licenses"] | ["licenses", "-check"] => {
            return match licenses::run(arguments.len() == 2) {
                Ok(()) => ExitCode::SUCCESS,
                Err(error) => {
                    eprintln!("{error}");
                    ExitCode::FAILURE
                }
            };
        }
        _ => {
            eprintln!("usage: repo-check [licenses [-check]]");
            return ExitCode::from(2);
        }
    }
    let files = match tracked_files() {
        Ok(files) => files,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::FAILURE;
        }
    };
    let mut issues = Vec::new();
    issues.extend(standard_syntax());
    issues.extend(nested::check(&files));
    issues.extend(format_drift(&files));
    issues.extend(release::extension_version());
    issues.extend(release::workflow_triggers());
    issues.extend(unsafe_boundary::check(&files));
    issues.extend(portability::check(&files));
    if issues.is_empty() {
        println!(
            "Nested matches, formatting, stdlib syntax, release pins, triggers, unsafe boundary, and portability agree."
        );
        return ExitCode::SUCCESS;
    }
    issues.sort();
    eprintln!("repository invariants:\n- {}", issues.join("\n- "));
    ExitCode::FAILURE
}

/// Tracked and untracked-but-not-ignored files that still exist, `/`-separated.
fn tracked_files() -> Result<Vec<String>, String> {
    let output = Command::new("git")
        .args([
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "--deduplicate",
            "-z",
        ])
        .output()
        .map_err(|e| format!("list repository files: {e}"))?;
    if !output.status.success() {
        return Err("list repository files: git ls-files failed".into());
    }
    Ok(String::from_utf8_lossy(&output.stdout)
        .split('\0')
        .filter(|p| !p.is_empty() && Path::new(p).is_file())
        .map(str::to_string)
        .collect())
}

/// Vendored code and frozen conformance inputs are not ours to rewrite.
pub(crate) fn skipped(path: &str) -> bool {
    path.starts_with("vendor/")
        || path.starts_with("website/themes/")
        || path.starts_with("tests/conformance/fixtures/")
}

/// Every standard-library declaration file must parse.
fn standard_syntax() -> Vec<String> {
    let Ok(entries) = std::fs::read_dir("stdlib") else {
        return vec!["stdlib: cannot read standard declarations".into()];
    };
    let mut issues = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|e| e != "ms") {
            continue;
        }
        let name = path.to_string_lossy().into_owned();
        let source = match std::fs::read_to_string(&path) {
            Ok(source) => source,
            Err(e) => {
                issues.push(format!("{name}: {e}"));
                continue;
            }
        };
        if let Err(diagnostic) = parse(&Arc::from(name.as_str()), &source) {
            issues.push(format!(
                "invalid standard-library syntax: {name}: {diagnostic:?}"
            ));
        }
    }
    issues
}

/// `ms fmt --check` over the repository's own sources; crate test inputs
/// deliberately keep their original spelling.
fn format_drift(files: &[String]) -> Vec<String> {
    let mut issues = Vec::new();
    for path in files
        .iter()
        .filter(|p| p.ends_with(".ms") && !skipped(p) && !p.contains("/tests/"))
    {
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let file: Arc<str> = Arc::from(path.as_str());
        // Files that do not parse are negative fixtures; the nested-match and
        // test suites own them.
        if let Ok(formatted) = ms_syntax::format(&file, &source)
            && formatted != source
        {
            issues.push(format!("{path}: run ms fmt"));
        }
    }
    issues
}
