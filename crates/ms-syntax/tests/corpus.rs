//! Parser and formatter tests against the repository corpus and the recorded
//! fixtures under `tests/data`.

use ms_syntax::dump::{dump_module, quote};
use ms_syntax::{format, parse_partial};
use std::path::{Path, PathBuf};
use std::sync::Arc;

fn data(dir: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/data")
        .join(dir)
}

/// `UPDATE_GOLDEN=1 cargo test` rewrites the recorded diagnostics instead of
/// comparing, after a deliberate message change.
fn update_golden() -> bool {
    std::env::var_os("UPDATE_GOLDEN").is_some()
}

fn sorted(dir: &Path, ext: &str) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == ext))
        .collect();
    files.sort();
    files
}

/// Runs `f` on a thread with a large stack, like the CLI does.
fn big_stack<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> T {
    std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(f)
        .unwrap()
        .join()
        .unwrap()
}

fn repository_sources() -> Vec<PathBuf> {
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
        for entry in std::fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            let name = path.file_name().unwrap().to_string_lossy().to_string();
            if path.is_dir() {
                let skip = name.starts_with('.')
                    || name.starts_with("target")
                    || matches!(
                        name.as_str(),
                        "vendor"
                            | "toolchain"
                            | "node_modules"
                            | "crates"
                            | "bench"
                            | "conformance"
                    );
                if !skip {
                    walk(&path, out);
                }
            } else if path.extension().is_some_and(|e| e == "ms") {
                out.push(path);
            }
        }
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut out = Vec::new();
    walk(&root, &mut out);
    out.sort();
    out
}

#[test]
fn repository_sources_parse_and_are_formatted() {
    big_stack(|| {
        let files = repository_sources();
        assert!(files.len() > 100, "found {} sources", files.len());
        for path in files {
            let text = std::fs::read_to_string(&path).unwrap();
            let file: Arc<str> = Arc::from(path.to_string_lossy().as_ref());
            // Sources written to test failures on purpose are listed in tests/ directories only.
            if ms_syntax::parser::parse(&file, &text).is_err() {
                continue;
            }
            let once = format(&file, &text).unwrap();
            assert_eq!(
                once,
                text,
                "{} is not formatted as the recorded output",
                path.display()
            );
            assert_eq!(
                format(&file, &once).unwrap(),
                once,
                "formatting is not idempotent for {}",
                path.display()
            );
        }
    });
}

#[test]
fn parse_diagnostics_match_go() {
    big_stack(|| {
        let files = sorted(&data("parse-errors"), "src");
        assert!(files.len() >= 50);
        for path in files {
            let text = std::fs::read_to_string(&path).unwrap();
            let want = std::fs::read_to_string(path.with_extension("expected")).unwrap();
            let file: Arc<str> = Arc::from("f.ms");
            let got = match ms_syntax::parser::parse(&file, &text) {
                Ok(_) => "ok".to_string(),
                Err(d) => format!(
                    "error parse {}:{}:{} {}",
                    d.pos.line,
                    d.pos.column,
                    d.pos.offset,
                    quote(&d.message)
                ),
            };
            if update_golden() {
                std::fs::write(path.with_extension("expected"), format!("{got}\n")).unwrap();
                continue;
            }
            assert_eq!(got, want.trim_end(), "{}", path.display());
        }
    });
}

#[test]
fn recovery_matches_go() {
    big_stack(|| {
        let files = sorted(&data("partial"), "src");
        assert!(files.len() >= 25);
        for path in files {
            let text = std::fs::read_to_string(&path).unwrap();
            let want = std::fs::read_to_string(path.with_extension("expected")).unwrap();
            let file: Arc<str> = Arc::from("f.ms");
            let (module, diags) = parse_partial(&file, &text);
            let mut got = String::new();
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
                        quote(&f.replacement)
                    )
                });
                got += &format!(
                    "diag {} {}:{}:{} end={end} fix={fix} {}\n",
                    d.phase.as_str(),
                    d.pos.line,
                    d.pos.column,
                    d.pos.offset,
                    quote(&d.message)
                );
            }
            got += &dump_module(&module);
            if update_golden() {
                std::fs::write(path.with_extension("expected"), &got).unwrap();
                continue;
            }
            assert_eq!(got, want, "{}", path.display());
        }
    });
}

#[test]
fn formatter_matches_go() {
    big_stack(|| {
        let files = sorted(&data("format"), "src");
        let inputs: Vec<_> = files
            .iter()
            .filter(|p| p.to_string_lossy().ends_with(".in.src"))
            .collect();
        assert!(inputs.len() >= 30);
        for path in inputs {
            let text = std::fs::read_to_string(path).unwrap();
            let want =
                std::fs::read_to_string(path.to_string_lossy().replace(".in.src", ".out.src"))
                    .unwrap();
            let file: Arc<str> = Arc::from("f.ms");
            if update_golden() {
                let out = path.to_string_lossy().replace(".in.src", ".out.src");
                std::fs::write(out, format(&file, &text).unwrap()).unwrap();
                continue;
            }
            assert_eq!(format(&file, &text).unwrap(), want, "{}", path.display());
        }
    });
}

#[test]
fn setup_paragraphs_are_stable_with_lf_and_crlf() {
    let source = include_str!("data/format/040.in.src");
    let expected = include_str!("data/format/040.out.src");
    let file: Arc<str> = Arc::from("setup.ms");
    for input in [source.to_string(), source.replace('\n', "\r\n")] {
        let once = format(&file, &input).unwrap();
        assert_eq!(once, expected);
        assert_eq!(format(&file, &once).unwrap(), once);
    }
}

#[test]
fn short_callbacks_are_compact_without_changing_block_bodies() {
    let source = include_str!("data/format/041.in.src");
    let expected = include_str!("data/format/041.out.src");
    let file: Arc<str> = Arc::from("callbacks.ms");
    for input in [source.to_string(), source.replace('\n', "\r\n")] {
        let once = format(&file, &input).unwrap();
        assert_eq!(once, expected);
        assert_eq!(format(&file, &once).unwrap(), once);
    }
}

#[test]
fn prose_paragraphs_keep_related_steps_together() {
    let source = include_str!("data/format/042.in.src");
    let expected = include_str!("data/format/042.out.src");
    let file: Arc<str> = Arc::from("paragraphs.ms");
    for input in [source.to_string(), source.replace('\n', "\r\n")] {
        let once = format(&file, &input).unwrap();
        assert_eq!(once, expected);
        assert_eq!(format(&file, &once).unwrap(), once);
    }
}

#[test]
fn callback_defaults_keep_the_enclosing_function_suite_aligned() {
    let source = include_str!("data/format/043.in.src");
    let expected = include_str!("data/format/043.out.src");
    let file: Arc<str> = Arc::from("defaults.ms");
    for input in [source.to_string(), source.replace('\n', "\r\n")] {
        let once = format(&file, &input).unwrap();
        assert_eq!(once, expected);
        assert_eq!(format(&file, &once).unwrap(), once);
    }
}

#[test]
fn nesting_limits() {
    big_stack(|| {
        let deep = 200_000;
        let wrap = |body: String| format!("def f() -> Int:\n    return {body}\n");
        let cases = [
            wrap("(".repeat(deep) + "1" + &")".repeat(deep)),
            wrap("[".repeat(deep) + &"]".repeat(deep)),
            wrap("f(".repeat(deep) + "1" + &")".repeat(deep)),
            wrap("-".repeat(deep) + "1"),
            wrap("1+".repeat(deep) + "1"),
            wrap("f\"{".repeat(deep) + "1" + &"}\"".repeat(deep)),
            wrap("x".to_string() + &".a".repeat(deep)),
            format!(
                "def f(x: {}Int{}) -> Int:\n    return 1\n",
                "(".repeat(deep),
                ")".repeat(deep)
            ),
        ];
        let file: Arc<str> = Arc::from("deep.ms");
        for source in cases {
            let err = ms_syntax::parser::parse(&file, &source).unwrap_err();
            assert!(err.message.contains("exceeds"), "{}", err.message);
        }
        let moderate = format!(
            "def f() -> Int:\n    return {}1{} {}\n",
            "(".repeat(500),
            ")".repeat(500),
            "+ 1 ".repeat(5000)
        );
        ms_syntax::parser::parse(&file, &moderate).unwrap();
    });
}
