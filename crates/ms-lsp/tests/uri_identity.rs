//! A file URI that does not decode to a path never names a file.

use crate::support::{Script, Workspace};
use ms_lsp::json::Json;

#[test]
fn malformed_file_uri_documents_are_rejected_and_roots_ignored() {
    let ws = Workspace::new("uri-identity");
    let bad = format!("{}/%FF.ms", ws.uri("").trim_end_matches('/'));
    let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
    s.open(&bad, "export fn value() Int: 7\n", 1);
    let id = s.at("textDocument/hover", &bad, 0, 12);
    let replies = s.rust();
    let reply = replies
        .iter()
        .find(|m| m.get("id").and_then(Json::as_i64) == Some(id))
        .expect("hover reply");
    let code = reply
        .get("error")
        .and_then(|e| e.get("code"))
        .and_then(Json::as_i64);
    assert_eq!(code, Some(-32602), "{reply:?}");
}

/// Names found by `workspace/symbol` for a session rooted at `root`.
fn symbols_under(root: String) -> String {
    let mut s = Script::new();
    s.request(
        "initialize",
        ms_lsp::json::obj([
            ("rootUri", root.into()),
            ("capabilities", ms_lsp::json::obj([])),
        ]),
    );
    s.notify("initialized", ms_lsp::json::obj([]));
    let id = s.request(
        "workspace/symbol",
        ms_lsp::json::obj([("query", "zzliteral".into())]),
    );
    let replies = s.rust();
    let reply = replies
        .iter()
        .find(|m| m.get("id").and_then(Json::as_i64) == Some(id))
        .expect("symbol reply");
    format!("{reply:?}")
}

#[test]
fn malformed_workspace_root_is_not_scanned() {
    let ws = Workspace::new("uri-root");
    let literal = ws.root.join("%FF");
    std::fs::create_dir_all(&literal).unwrap();
    std::fs::write(literal.join("a.ms"), "export fn zzliteral() Int: 1\n").unwrap();
    // The valid spelling of the literal-percent directory finds the symbol.
    let valid = ms_lsp::uri::file_uri(&literal.to_string_lossy());
    assert!(symbols_under(valid).contains("zzliteral"));
    // The malformed spelling is not decoded, matched raw, or scanned.
    let malformed = format!("{}/%FF", ms_lsp::uri::file_uri(&ws.root.to_string_lossy()));
    assert!(ms_lsp::uri::is_malformed_file(&malformed));
    assert!(!symbols_under(malformed).contains("zzliteral"));
}
