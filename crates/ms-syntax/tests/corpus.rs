//! Parser tests against the repository corpus and the recorded
//! fixtures under `tests/data`.

use ms_syntax::dump::{dump_module, quote};
use ms_syntax::parse_partial;
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
fn recovery_matches_oracle() {
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
            got += &dump_module(ms_syntax::Names::global(), &module);
            if update_golden() {
                std::fs::write(path.with_extension("expected"), &got).unwrap();
                continue;
            }
            assert_eq!(got, want, "{}", path.display());
        }
    });
}

#[test]
fn nesting_limits() {
    big_stack(|| {
        let deep = 200_000;
        let wrap = |body: String| format!("fn f() Int:\n\treturn {body}\n");
        let cases = [
            wrap("(".repeat(deep) + "1" + &")".repeat(deep)),
            wrap("[".repeat(deep) + &"]".repeat(deep)),
            wrap("f(".repeat(deep) + "1" + &")".repeat(deep)),
            wrap("-".repeat(deep) + "1"),
            wrap("1+".repeat(deep) + "1"),
            wrap("f\"{".repeat(deep) + "1" + &"}\"".repeat(deep)),
            wrap("x".to_string() + &".a".repeat(deep)),
            format!(
                "fn f(x: {}Int{}) Int:\n\treturn 1\n",
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
            "fn f() Int:\n\treturn {}1{} {}\n",
            "(".repeat(500),
            ")".repeat(500),
            "+ 1 ".repeat(5000)
        );
        ms_syntax::parser::parse(&file, &moderate).unwrap();
    });
}

#[test]
fn pipe_and_case_paths_obey_the_chain_limit() {
    big_stack(|| {
        let file: Arc<str> = Arc::from("pipe-limit.ms");
        let long = ms_syntax::parser::MAX_CHAIN + 1;
        let cases = [
            (
                format!("fn f() Int:\n\treturn 1{}\n", " | step".repeat(long)),
                2,
            ),
            (
                format!("fn f() Int:\n\treturn 1{}\n", " | .member()".repeat(long)),
                2,
            ),
            (
                format!("fn f() Int:\n\treturn 1 | step{}\n", ".member".repeat(long)),
                2,
            ),
            (
                format!(
                    "fn f() Int:\n\treturn match value:\n\t\tCase{}: 1\n",
                    ".member".repeat(long)
                ),
                3,
            ),
        ];
        for (source, line) in cases {
            let result = ms_syntax::parser::parse(&file, &source);
            assert!(
                result.is_err(),
                "overlong expression chain must be rejected"
            );
            let diagnostic = result.err().unwrap();
            assert!(
                diagnostic
                    .message
                    .starts_with("expression chain exceeds 10000")
            );
            assert_eq!(diagnostic.pos.line, line);
            assert!((diagnostic.pos.offset as usize) < source.len());
        }
        let source = format!("fn f() Int:\n\treturn 1{}\n", " | step".repeat(100));
        ms_syntax::parser::parse(&file, &source).unwrap();
    });
}
