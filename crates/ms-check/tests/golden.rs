//! Diagnostic parity with the removed Go checker: every Manuscript source from the
//! Go test suite's string literals must produce exactly the diagnostics recorded in
//! `golden.txt`. The Go oracle and its generator scripts are gone; run with
//! `UPDATE_GOLDEN=1` to rewrite `golden.txt` after an intended wording change.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("t.ms");
    let diagnostics = match ms_syntax::parser::parse(&file, source) {
        Err(d) => vec![*d],
        Ok(module) => {
            let program = ms_check::check(
                syms,
                vec![ms_check::load_module(syms, &module)],
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

/// The records one shard checks are every `SHARDS`th one, so the shards run as separate tests in
/// parallel. `UPDATE_GOLDEN` rewrites the whole file from shard 0 alone.
const SHARDS: usize = 4;

fn matches_oracle(shard: usize) {
    let updating = std::env::var_os("UPDATE_GOLDEN").is_some();
    if updating && shard != 0 {
        return;
    }
    // Deeply nested sources need more stack than a test thread has.
    let handle = std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(move || {
            let golden = include_str!("golden.txt");
            let mut failures: Vec<String> = Vec::new();
            let mut total = 0;
            let mut updated = String::new();
            for (index, record) in golden.split('\u{1e}').enumerate() {
                if !updating && index % SHARDS != shard {
                    continue;
                }
                let (source, expected) = record.split_once('\u{1f}').expect("record");
                let expected: Vec<&str> = expected.lines().collect();
                total += 1;
                let actual = diagnostics(source);
                if !updated.is_empty() {
                    updated.push('\u{1e}');
                }
                updated.push_str(&format!("{source}\u{1f}{}", actual.join("\n")));
                if actual != expected {
                    failures.push(format!(
                        "--- source:\n{source}\n--- expected:\n{}\n--- actual:\n{}",
                        expected.join("\n"),
                        actual.join("\n")
                    ));
                }
            }
            if updating {
                let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden.txt");
                std::fs::write(path, updated).expect("write golden.txt");
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

#[test]
fn matches_oracle_shard_0() {
    matches_oracle(0);
}

#[test]
fn matches_oracle_shard_1() {
    matches_oracle(1);
}

#[test]
fn matches_oracle_shard_2() {
    matches_oracle(2);
}

#[test]
fn matches_oracle_shard_3() {
    matches_oracle(3);
}
