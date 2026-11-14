//! A long editing session starts over with a fresh name table instead of growing without bound,
//! and answers exactly as a server that never does.

use ms_lsp::json::{Json, obj};
use ms_lsp::lint::Tooling;
use ms_rt as _;
use std::io::Cursor;

use crate::support;
use support::{Script, Workspace, canonical, decode};

const EDITS: usize = 60;
const NAME_LEN: usize = 100;

fn script(workspace: &Workspace, edits: usize) -> Script {
    let uri = workspace.uri("edit.ms");
    let mut s = Script::initialize(&workspace.path(""), false);
    s.open(&uri, "fn start() Int:\n    return 0\n", 1);
    for i in 0..edits {
        // A distinct, long name per edit: every edit interns new text.
        let name = format!("{i:0>width$}", width = NAME_LEN);
        let text = format!("fn n{name}() Int:\n    return {i}\n");
        s.notify(
            "textDocument/didChange",
            obj([
                (
                    "textDocument",
                    obj([
                        ("uri", uri.as_str().into()),
                        ("version", (i as i64 + 2).into()),
                    ]),
                ),
                (
                    "contentChanges",
                    Json::Arr(vec![obj([("text", text.into())])]),
                ),
            ]),
        );
        s.request(
            "textDocument/documentSymbol",
            obj([("textDocument", obj([("uri", uri.as_str().into())]))]),
        );
    }
    // After the last start-over: hover and completion read names through the new table.
    s.at("textDocument/hover", &uri, 0, 6);
    s.at("textDocument/completion", &uri, 1, 11);
    s
}

fn run(script: &Script, limit: Option<usize>) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let mut out = Vec::new();
    let frames = Cursor::new(script.frames());
    let _ = match limit {
        Some(limit) => ms_lsp::server::serve_recycling(syms, frames, &mut out, &Tooling, limit),
        None => ms_lsp::server::serve_with(syms, frames, &mut out, &Tooling),
    };
    decode(&out).iter().map(canonical).collect()
}

#[test]
fn a_server_over_its_limit_starts_over_and_answers_the_same() {
    let workspace = Workspace::new("name-recycling");
    // A private table for this test: the process default is shared with every test running in
    // parallel, so its growth cannot be measured there (it flaked under load).
    let session = ms_syntax::Session::new();
    let _entered = session.enter();
    let default = ms_syntax::Names::global();
    // Warm up: the standard library's own names enter the default table once.
    run(&script(&workspace, 1), None);
    let script = script(&workspace, EDITS);

    let before = default.text_bytes();
    let recycled = run(&script, Some(1_000));
    let recycled_growth = default.text_bytes() - before;
    // Names typed after the limit went into replacement tables, not the process default.
    assert!(
        recycled_growth < 1_000 + 2 * NAME_LEN,
        "the default table grew by {recycled_growth} bytes"
    );

    let before = default.text_bytes();
    let plain = run(&script, None);
    let grew = default.text_bytes() - before;
    // The names the recycled run already put in the default table are not new here.
    assert!(
        grew > 4 * recycled_growth,
        "an unrecycled run grew by only {grew} bytes"
    );

    assert_eq!(recycled, plain);
}
