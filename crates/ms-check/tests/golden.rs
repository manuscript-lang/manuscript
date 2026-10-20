//! Diagnostic parity with the Go checker: every Manuscript source found in the
//! Go test suite's string literals must produce exactly the diagnostics
//! `ms check --json` reported for it (see `gen_golden.py`).

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("t.ms");
    let diagnostics = match ms_syntax::parser::parse(&file, source) {
        Err(d) => vec![*d],
        Ok(module) => {
            let program = ms_check::check(
                vec![ms_check::load_module(&module)],
                ImportMap::default(),
                CheckOptions::default(),
            );
            program.diagnostics
        }
    };
    diagnostics
        .iter()
        .map(|d| {
            format!(
                "{}\t{}\t{}\t{}\t{}",
                d.phase.as_str(),
                d.pos.line,
                d.pos.column,
                d.pos.offset,
                d.message.replace('\\', "\\\\").replace('\n', "\\n")
            )
        })
        .collect()
}

#[test]
fn matches_go_oracle() {
    // Deeply nested sources need more stack than a test thread has.
    let handle = std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(|| {
            let golden = include_str!("golden.txt");
            let mut failures: Vec<String> = Vec::new();
            let mut total = 0;
            let mut rewritten: Vec<String> = Vec::new();
            for record in golden.split('\u{1e}') {
                let (source, expected) = record.split_once('\u{1f}').expect("record");
                let expected: Vec<&str> = expected.lines().collect();
                total += 1;
                let actual = diagnostics(source);
                let lines = actual.join("\n");
                rewritten.push(format!("{source}\u{1f}{lines}"));
                if actual != expected {
                    failures.push(format!(
                        "--- source:\n{source}\n--- expected:\n{}\n--- actual:\n{}",
                        expected.join("\n"),
                        actual.join("\n")
                    ));
                }
            }
            // `UPDATE_GOLDEN=1 cargo test -p ms-check --test golden` rewrites
            // golden.txt after a deliberate message change.
            if std::env::var_os("UPDATE_GOLDEN").is_some() {
                let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden.txt");
                std::fs::write(path, rewritten.join("\u{1e}")).expect("write golden");
                return;
            }
            assert!(
                failures.is_empty(),
                "{} of {total} sources differ; first:\n{}",
                failures.len(),
                failures
                    .iter()
                    .take(3)
                    .cloned()
                    .collect::<Vec<_>>()
                    .join("\n\n")
            );
        })
        .expect("spawn");
    handle.join().expect("golden test");
}
