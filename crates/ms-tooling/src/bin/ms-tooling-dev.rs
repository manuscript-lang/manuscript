//! Developer tool: run a source tool on standalone `.ms` files and print the
//! output of the matching Go `ms` command, so the two can be diffed.
//!
//! ```text
//! ms-tooling-dev lint FILE...
//! ms-tooling-dev inspect FILE
//! ```
//!
//! Only files without local imports are supported; projects and aliases belong
//! to the driver.

use ms_check::{CheckOptions, ImportMap};
use std::path::Path;
use std::sync::Arc;

fn main() {
    let handle = std::thread::Builder::new()
        .stack_size(512 << 20)
        .spawn(run)
        .expect("spawn");
    std::process::exit(handle.join().unwrap_or(2));
}

fn run() -> i32 {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some((command, files)) = args.split_first() else {
        eprintln!("usage: ms-tooling-dev lint FILE...");
        return 2;
    };
    match command.as_str() {
        "lint" => lint(files),
        "inspect" => inspect(files),
        other => {
            eprintln!("unknown command {other}");
            2
        }
    }
}

fn lint(files: &[String]) -> i32 {
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
            vec![ms_check::load_module(&module)],
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
        for f in ms_tooling::lint::lint_modules(&program) {
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
fn checked(path: &str) -> Option<ms_check::Program> {
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
        vec![ms_check::load_module(&module)],
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

fn inspect(files: &[String]) -> i32 {
    let Some(program) = files.first().and_then(|f| checked(f)) else {
        return 1;
    };
    println!(
        "{}",
        ms_tooling::inspect::inspect(&program)
            .to_json()
            .pretty(ms_json::Escape::GoHtml)
    );
    0
}
