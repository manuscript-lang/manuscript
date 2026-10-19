//! Developer tool: parse and format Manuscript files and compare with the Go oracle.
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
        Some("dump-strict") | Some("dump-partial") => {
            // Prints the tree in the shape of the Go oracle used by the differential tests.
            let strict = args[0] == "dump-strict";
            for path in &args[1..] {
                let text = std::fs::read_to_string(path).expect("read");
                let file: Arc<str> = Arc::from("f.ms");
                println!("file {path}");
                if strict {
                    match parse(&file, &text) {
                        Ok(m) => print!("ok\n{}", ms_syntax::dump::dump_module(&m)),
                        Err(d) => println!(
                            "error parse {}:{}:{} {}",
                            d.pos.line,
                            d.pos.column,
                            d.pos.offset,
                            ms_syntax::dump::quote(&d.message)
                        ),
                    }
                    continue;
                }
                let (m, diags) = ms_syntax::parse_partial(&file, &text);
                for d in &diags {
                    let end = d.end.map_or("-".to_string(), |e| {
                        format!("{}:{}:{}", e.line, e.column, e.offset)
                    });
                    let fix = d.fix.as_ref().map_or("-".to_string(), |f| {
                        format!(
                            "{}:{}:{}>{}:{}:{}={}",
                            f.pos.line,
                            f.pos.column,
                            f.pos.offset,
                            f.end.line,
                            f.end.column,
                            f.end.offset,
                            ms_syntax::dump::quote(&f.replacement)
                        )
                    });
                    println!(
                        "diag {} {}:{}:{} end={end} fix={fix} {}",
                        d.phase.as_str(),
                        d.pos.line,
                        d.pos.column,
                        d.pos.offset,
                        ms_syntax::dump::quote(&d.message)
                    );
                }
                print!("{}", ms_syntax::dump::dump_module(&m));
            }
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
        Some("compare") => compare(&args[1..]),
        _ => {
            eprintln!("usage: ms-syntax parse [--json] FILE... | fmt FILE | bench FILE...");
            2
        }
    }
}

/// Renders the same three-section report the Go oracle writes next to each corpus file.
fn report(name: &str, bytes: &[u8], sections: &[&str]) -> String {
    let file: Arc<str> = Arc::from(name);
    let mut out = String::new();
    let text = match std::str::from_utf8(bytes) {
        Ok(t) => t,
        Err(_) => {
            let d = ms_syntax::Diagnostic::parse(
                &file,
                ms_syntax::Pos::new(0, 1, 1),
                "source must be valid UTF-8; re-save the file with UTF-8 encoding",
            );
            for sec in sections {
                match *sec {
                    "parse" => out.push_str(&format!("error {}\n", d.to_json())),
                    "partial" => out.push_str(&format!(
                        "--partial\ndiag {}\n{}",
                        d.to_json(),
                        ms_syntax::dump::dump_module(&ms_syntax::Module::default())
                    )),
                    _ => out.push_str(&format!("--format\nerror {}\n", d.to_json())),
                }
            }
            return out;
        }
    };
    for sec in sections {
        if *sec == "parse" {
            match parse(&file, text) {
                Ok(m) => out.push_str(&format!("ok\n{}", ms_syntax::dump::dump_module(&m))),
                Err(d) => out.push_str(&format!("error {}\n", d.to_json())),
            }
        }
    }
    out
}

fn compare(args: &[String]) -> i32 {
    let dir = &args[0];
    let only = args.get(1).map(String::as_str).unwrap_or("parse");
    let mut names: Vec<_> = std::fs::read_dir(dir)
        .expect("dir")
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "ms"))
        .collect();
    names.sort();
    let (mut total, mut bad) = (0, 0);
    for path in names {
        let expected = std::fs::read_to_string(path.with_extension("expected")).unwrap_or_default();
        let bytes = std::fs::read(&path).expect("read");
        let base = path.file_name().unwrap().to_string_lossy().to_string();
        let want = expected
            .split("--partial\n")
            .next()
            .unwrap_or("")
            .to_string();
        let got = report(&base, &bytes, &[only]);
        total += 1;
        if want != got {
            bad += 1;
            if bad <= 10 {
                println!(
                    "MISMATCH {base}\n--- want\n{}\n--- got\n{}",
                    &want[..want.len().min(1500)],
                    &got[..got.len().min(1500)]
                );
            } else if bad <= 60 {
                println!("MISMATCH {base}");
            }
        }
    }
    println!("{total} files, {bad} mismatches");
    i32::from(bad > 0)
}
