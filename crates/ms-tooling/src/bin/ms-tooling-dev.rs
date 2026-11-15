//! Developer tool: run a source tool on standalone `.ms` files and print the
//! output of the matching `ms` command, so the two can be diffed.
//!
//! ```text
//! ms-tooling-dev lint FILE...
//! ms-tooling-dev inspect FILE
//! ms-tooling-dev skill-calls count DIR...   counts of the calls agents use, as the counts file
//! ms-tooling-dev skill-calls update         rewrite the call tables in the agent skill
//! ```
//!
//! Only files without local imports are supported; projects and aliases belong
//! to the driver.

use ms_check::{CheckOptions, ImportMap};
use std::path::Path;
use std::sync::Arc;

fn main() {
    let syms = ms_syntax::Names::global();
    let handle = std::thread::Builder::new()
        .stack_size(512 << 20)
        .spawn(move || run(syms))
        .expect("spawn");
    std::process::exit(handle.join().unwrap_or(2));
}

fn run(syms: ms_syntax::Names) -> i32 {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some((command, files)) = args.split_first() else {
        eprintln!("usage: ms-tooling-dev lint FILE...");
        return 2;
    };
    match command.as_str() {
        "lint" => lint(syms, files),
        "inspect" => inspect(syms, files),
        "skill-calls" => skill_calls(files),
        other => {
            eprintln!("unknown command {other}");
            2
        }
    }
}

fn lint(syms: ms_syntax::Names, files: &[String]) -> i32 {
    let mut status = 0;
    for path in files {
        let text = std::fs::read_to_string(path).expect("read source");
        let file: Arc<str> = Arc::from(
            Path::new(path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or(path),
        );
        let module = match ms_syntax::parser::parse(&file, &text) {
            Ok(m) => m,
            Err(d) => {
                println!("{d}");
                status = 1;
                continue;
            }
        };
        let program = ms_check::check(
            syms,
            vec![ms_check::load_module(syms, &module)],
            ImportMap::default(),
            CheckOptions::default(),
        );
        if !program.diagnostics.is_empty() {
            for d in &program.diagnostics {
                println!("{d}");
            }
            status = 1;
            continue;
        }
        for f in ms_tooling::lint::lint_modules(syms, &program) {
            println!(
                "{}:{}:{}: {} {}",
                f.file, f.pos.line, f.pos.column, f.code, f.message
            );
            status = 1;
        }
    }
    status
}

/// Parses and checks one standalone file, printing diagnostics on failure.
fn checked(syms: ms_syntax::Names, path: &str) -> Option<ms_check::Program> {
    let text = std::fs::read_to_string(path).expect("read source");
    let file: Arc<str> = Arc::from(
        Path::new(path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(path),
    );
    let module = match ms_syntax::parser::parse(&file, &text) {
        Ok(m) => m,
        Err(d) => {
            println!("{d}");
            return None;
        }
    };
    let program = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    if program.diagnostics.is_empty() {
        return Some(program);
    }
    for d in &program.diagnostics {
        println!("{d}");
    }
    None
}

fn inspect(syms: ms_syntax::Names, files: &[String]) -> i32 {
    let Some(program) = files.first().and_then(|f| checked(syms, f)) else {
        return 1;
    };
    println!(
        "{}",
        ms_tooling::inspect::inspect(syms, &program)
            .to_json()
            .pretty(ms_json::Escape::HtmlSafe)
    );
    0
}

/// `skill-calls count DIR...` prints counts over every `.ms` file below the directories;
/// `skill-calls update` renders the committed counts into `SKILL.md`.
fn skill_calls(args: &[String]) -> i32 {
    use ms_tooling::guide::skill_calls::{Counts, block_of, count, render, splice};
    let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("data/agent-skill");
    match args.split_first() {
        Some((mode, dirs)) if mode == "count" => {
            let mut sources = Vec::new();
            let mut pending: Vec<std::path::PathBuf> = dirs.iter().map(Into::into).collect();
            while let Some(path) = pending.pop() {
                if path.is_dir() {
                    pending.extend(
                        std::fs::read_dir(&path)
                            .expect("read dir")
                            .map(|e| e.expect("entry").path()),
                    );
                } else if path.extension().is_some_and(|e| e == "ms") {
                    sources.push(std::fs::read_to_string(&path).expect("read source"));
                }
            }
            eprintln!("{} programs", sources.len());
            print!("{}", count(sources.iter().map(String::as_str)).to_text());
            0
        }
        Some((mode, _)) if mode == "update" => {
            let counts = Counts::parse(
                &std::fs::read_to_string(data.join("call-counts.tsv")).expect("counts file"),
            );
            let path = data.join("SKILL.md");
            let skill = std::fs::read_to_string(&path).expect("skill");
            let Some(updated) = splice(&skill, &render(&counts)) else {
                eprintln!("SKILL.md has no calls:start and calls:end markers");
                return 2;
            };
            let changed = block_of(&skill) != block_of(&updated);
            std::fs::write(&path, updated).expect("write skill");
            eprintln!("{}", if changed { "updated" } else { "unchanged" });
            0
        }
        _ => {
            eprintln!("usage: ms-tooling-dev skill-calls count DIR... | update");
            2
        }
    }
}
