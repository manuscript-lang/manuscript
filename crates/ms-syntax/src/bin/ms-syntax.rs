//! Developer tool: parse and format Manuscript files.
//!
//! ```text
//! ms-syntax parse [--json] FILE...     print diagnostics (or "ok") per file
//! ms-syntax fmt FILE                   print the formatted source
//! ms-syntax bench FILE...              time parsing the files
//! ```

use ms_syntax::parser::parse;
use std::sync::Arc;

fn main() {
    // Deeply nested sources need more stack than the default main thread has.
    let handle = std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(run)
        .expect("spawn");
    let code = handle.join().unwrap_or(2);
    std::process::exit(code);
}

fn run() -> i32 {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("parse") => {
            let json = args.iter().any(|a| a == "--json");
            let mut failed = 0;
            for path in args[1..].iter().filter(|a| !a.starts_with("--")) {
                let bytes = std::fs::read(path).expect("read");
                let file: Arc<str> = Arc::from(path.as_str());
                let result = match String::from_utf8(bytes) {
                    Ok(text) => parse(&file, &text).map(|_| ()),
                    Err(_) => Err(Box::new(ms_syntax::Diagnostic::parse(
                        &file,
                        ms_syntax::Pos::new(0, 1, 1),
                        "source must be valid UTF-8; re-save the file with UTF-8 encoding",
                    ))),
                };
                match result {
                    Ok(()) => println!("{path}: ok"),
                    Err(d) => {
                        failed += 1;
                        if json {
                            println!("{}", d.to_json());
                        } else {
                            println!("{d}");
                        }
                    }
                }
            }
            i32::from(failed > 0)
        }
        Some("bench") => {
            let mut sources = Vec::new();
            let mut bytes = 0usize;
            for path in &args[1..] {
                let text = std::fs::read_to_string(path).expect("read");
                bytes += text.len();
                sources.push((Arc::<str>::from(path.as_str()), text));
            }
            // Validate the workload before timing it: an early parse failure
            // would otherwise look like exceptionally fast source parsing.
            for (file, text) in &sources {
                if let Err(diagnostic) = parse(file, text) {
                    eprintln!("{diagnostic}");
                    return 1;
                }
            }
            let rounds = 20;
            let start = std::time::Instant::now();
            for _ in 0..rounds {
                for (file, text) in &sources {
                    let _ = std::hint::black_box(parse(file, text));
                }
            }
            let per = start.elapsed() / rounds;
            println!(
                "{} files, {} bytes: {:?} per pass ({:.1} MB/s)",
                sources.len(),
                bytes,
                per,
                bytes as f64 / per.as_secs_f64() / 1e6
            );
            0
        }
        Some("fmt") => {
            let mut failed = 0;
            for path in &args[1..] {
                let text = std::fs::read_to_string(path).expect("read");
                let file: Arc<str> = Arc::from(path.as_str());
                match ms_syntax::format(&file, &text) {
                    Ok(out) => print!("{out}"),
                    Err(d) => {
                        failed += 1;
                        eprintln!("{d}");
                    }
                }
            }
            i32::from(failed > 0)
        }
        Some("fmt-check") => {
            let mut bad = 0;
            for path in &args[1..] {
                let text = std::fs::read_to_string(path).expect("read");
                let file: Arc<str> = Arc::from(path.as_str());
                match ms_syntax::format(&file, &text) {
                    Ok(out) if out == text => {}
                    Ok(_) => {
                        bad += 1;
                        println!("{path}: differs");
                    }
                    Err(d) => {
                        bad += 1;
                        println!("{path}: {d}");
                    }
                }
            }
            println!("{} files, {bad} not formatted", args.len() - 1);
            i32::from(bad > 0)
        }
        _ => {
            eprintln!("usage: ms-syntax parse [--json] FILE... | fmt FILE | bench FILE...");
            2
        }
    }
}
