//! Incremental changes are ordered transactions on successive UTF-16 snapshots.

use ms_lsp::json::{Json, obj};
use ms_lsp::lint::{Lint, LintFinding};
use ms_lsp::text::{Position, Range};
use ms_rt as _;
use std::cell::RefCell;

mod support;
use support::{Script, Workspace};

const SOURCE: &str = include_str!("document_updates/unicode.ms");

#[derive(Default)]
struct Sources(RefCell<Vec<String>>);

impl Lint for Sources {
    fn source(&self, _: &str, source: &str) -> Vec<LintFinding> {
        self.0.borrow_mut().push(source.to_string());
        Vec::new()
    }

    fn program(&self, _: &ms_check::Program) -> Vec<LintFinding> {
        Vec::new()
    }
}

fn edit(start: (usize, usize), end: (usize, usize), text: &str) -> Json {
    let position = |(line, character)| Position { line, character };
    obj([
        (
            "range",
            Range {
                start: position(start),
                end: position(end),
            }
            .json(),
        ),
        ("text", text.into()),
    ])
}

fn change(script: &mut Script, uri: &str, version: i64, edits: Vec<Json>) {
    script.notify(
        "textDocument/didChange",
        obj([
            (
                "textDocument",
                obj([("uri", uri.into()), ("version", version.into())]),
            ),
            ("contentChanges", Json::Arr(edits)),
        ]),
    );
    // A request is a barrier: each accepted notification must publish its version.
    script.request(
        "textDocument/documentSymbol",
        obj([("textDocument", obj([("uri", uri.into())]))]),
    );
}

fn versions(messages: &[Json]) -> Vec<i64> {
    messages
        .iter()
        .filter(|message| {
            message.get("method").and_then(Json::as_str) == Some("textDocument/publishDiagnostics")
        })
        .filter_map(|message| message.get("params")?.get("version")?.as_i64())
        .collect()
}

#[test]
fn incremental_changes_use_each_prior_utf16_snapshot_and_clamp_endpoints() {
    for newline in ["\n", "\r\n"] {
        let source = SOURCE.replace('\n', newline);
        let ws = Workspace::new("ordered-edits");
        let uri = ws.uri("case.ms");
        let mut script = Script::initialize(ws.root.to_str().unwrap(), false);
        script.open(&uri, &source, 1);
        change(
            &mut script,
            &uri,
            2,
            vec![
                edit((0, 2), (0, 4), "é"),
                edit((0, 3), (0, 8), "日本\n# split"),
                edit((1, 999), (1, 1000), "!"),
                edit((999, 0), (1000, 0), "# done\n"),
            ],
        );
        let sources = Sources::default();
        let messages = script.rust_with(&sources);
        let expected = source.replacen("😀alpha", "é日本\n# split!", 1) + "# done\n";
        assert_eq!(*sources.0.borrow(), [source, expected]);
        assert_eq!(versions(&messages), [1, 2]);
    }
}

#[test]
fn equal_byte_replacements_can_change_subsequent_utf16_columns() {
    let ws = Workspace::new("equal-byte-edits");
    let uri = ws.uri("case.ms");
    let mut script = Script::initialize(ws.root.to_str().unwrap(), false);
    script.open(&uri, SOURCE, 1);
    change(
        &mut script,
        &uri,
        2,
        vec![edit((0, 2), (0, 4), "abcd"), edit((0, 6), (0, 11), "βeta")],
    );
    let sources = Sources::default();
    let messages = script.rust_with(&sources);
    assert_eq!(
        *sources.0.borrow(),
        [
            SOURCE.to_string(),
            SOURCE.replacen("😀alpha", "abcdβeta", 1)
        ]
    );
    assert_eq!(versions(&messages), [1, 2]);
}

#[test]
fn rejected_later_changes_preserve_the_entire_document_and_version() {
    let ws = Workspace::new("atomic-edits");
    let uri = ws.uri("case.ms");
    let mut script = Script::initialize(ws.root.to_str().unwrap(), false);
    script.open(&uri, SOURCE, 1);
    for invalid in [
        edit((0, 3), (0, 4), "split surrogate"),
        edit((0, 5), (0, 2), "reversed"),
    ] {
        change(
            &mut script,
            &uri,
            2,
            vec![edit((1, 2), (1, 6), "changed"), invalid],
        );
    }
    // Reusing version 2 must still work: both rejected transactions kept version 1.
    change(&mut script, &uri, 2, vec![edit((0, 4), (0, 9), "beta")]);
    // A stale replacement must neither overwrite the text nor publish a version.
    change(&mut script, &uri, 2, vec![obj([("text", "stale".into())])]);
    let sources = Sources::default();
    let messages = script.rust_with(&sources);
    assert_eq!(
        *sources.0.borrow(),
        [SOURCE.to_string(), SOURCE.replacen("alpha", "beta", 1)]
    );
    assert_eq!(versions(&messages), [1, 2]);
}

#[test]
fn full_replacements_and_incremental_changes_share_one_transaction() {
    let ws = Workspace::new("replacement-edits");
    let uri = ws.uri("case.ms");
    let mut script = Script::initialize(ws.root.to_str().unwrap(), false);
    script.open(&uri, SOURCE, 1);
    change(
        &mut script,
        &uri,
        2,
        vec![
            edit((0, 4), (0, 9), "discarded"),
            obj([("text", SOURCE.into())]),
            edit((1, 2), (1, 6), "kept"),
        ],
    );
    change(
        &mut script,
        &uri,
        3,
        vec![
            obj([("text", SOURCE.into())]),
            edit((0, 3), (0, 4), "invalid"),
        ],
    );
    let sources = Sources::default();
    let messages = script.rust_with(&sources);
    assert_eq!(
        *sources.0.borrow(),
        [SOURCE.to_string(), SOURCE.replacen("tail", "kept", 1)]
    );
    assert_eq!(versions(&messages), [1, 2]);
}
