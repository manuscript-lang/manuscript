//! Generates the standard-library API reference (`scripts/docgen`).
//!
//! Flags: `-check` validates source documentation without
//! writing generated files, `-downloads` writes only the uncommitted API
//! downloads (`website/static/stdlib.*`), and `-coverage <file>` writes the
//! complete description inventory as JSON. `-artifacts <dir>` (default
//! `.artifacts/docs`) and `-static <dir>` (default `website/static`) redirect
//! the output trees for differential runs.

use ms_guide::docgen::{self, check_descriptions, inventory, standard_description_policy};
use ms_guide::standard_library;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

struct Options {
    check: bool,
    downloads: bool,
    coverage: Option<PathBuf>,
    artifacts: PathBuf,
    static_dir: PathBuf,
}

fn parse(args: &[String]) -> Result<Options, String> {
    let mut o = Options {
        check: false,
        downloads: false,
        coverage: None,
        artifacts: PathBuf::from(".artifacts/docs"),
        static_dir: PathBuf::from("website/static"),
    };
    let mut i = 0;
    while i < args.len() {
        let arg = args[i].trim_start_matches('-');
        let (name, inline) = match arg.split_once('=') {
            Some((n, v)) => (n, Some(v.to_string())),
            None => (arg, None),
        };
        let value = |i: &mut usize| -> Result<String, String> {
            if let Some(v) = &inline {
                return Ok(v.clone());
            }
            *i += 1;
            args.get(*i)
                .cloned()
                .ok_or_else(|| format!("flag needs an argument: -{name}"))
        };
        match name {
            "check" => o.check = true,
            "downloads" => o.downloads = true,
            "coverage" => o.coverage = Some(PathBuf::from(value(&mut i)?)),
            "artifacts" => o.artifacts = PathBuf::from(value(&mut i)?),
            "static" => o.static_dir = PathBuf::from(value(&mut i)?),
            _ => return Err(format!("flag provided but not defined: -{name}")),
        }
        i += 1;
    }
    Ok(o)
}

fn write(path: &Path, data: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
    }
    std::fs::write(path, data).map_err(|e| format!("{}: {e}", path.display()))
}

fn run(o: &Options) -> Result<(), String> {
    let report = inventory(standard_library());
    eprintln!(
        "API descriptions: {}/{} declarations, {}/{} members (including prelude aliases)",
        report.described_declarations,
        report.declarations,
        report.described_members,
        report.members
    );
    eprintln!(
        "Description quality: {}/{} declarations, {}/{} members pass structural checks; semantic review remains required",
        report.qualified_declarations,
        report.declarations,
        report.qualified_members,
        report.members
    );
    if let Some(path) = &o.coverage {
        write(path, report.to_json().as_bytes())?;
    }
    let policy = standard_description_policy()?;
    let problems = check_descriptions(&report, &policy);
    if !problems.is_empty() {
        for problem in &problems {
            eprintln!("API description: {problem}");
        }
        return Err(String::new());
    }
    let files = docgen::site_files();
    if o.check {
        return Ok(());
    }
    // All book Markdown is disposable; rebuild its tree to retire removed routes.
    if !o.downloads && o.artifacts.exists() {
        std::fs::remove_dir_all(&o.artifacts)
            .map_err(|e| format!("{}: {e}", o.artifacts.display()))?;
    }
    for (path, data) in files {
        let download = path == "website/static/stdlib.md" || path == "website/static/stdlib.json";
        if o.downloads && !download {
            continue;
        }
        let target = if download {
            o.static_dir
                .join(path.trim_start_matches("website/static/"))
        } else {
            o.artifacts.join(&path)
        };
        write(&target, &data)?;
    }
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = parse(&args).and_then(|o| run(&o));
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            if !message.is_empty() {
                eprintln!("{message}");
            }
            ExitCode::FAILURE
        }
    }
}
