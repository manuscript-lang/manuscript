//! URI decoding must not substitute one filesystem identity for another.

use crate::support::{Script, Workspace};
use ms_lsp::analysis::{Analysis, Document, Documents, Options, analyze, analyze_with};
use ms_lsp::json::{Json, obj};
use ms_lsp::uri;
use std::rc::Rc;

#[test]
fn invalid_utf8_file_uris_do_not_overlay_replacement_character_files() {
    let ws = Workspace::new("invalid-uri-identity");
    let source = include_str!("uri_identity/main.ms");
    let replacement = include_str!("uri_identity/replacement.ms");
    let different = include_str!("uri_identity/different.ms");
    std::fs::write(ws.path("consumer.ms"), source).unwrap();
    std::fs::write(ws.path("�.ms"), replacement).unwrap();
    let main = Document::new(ws.uri("consumer.ms"), source);
    let invalid = Document::new(
        ws.uri("invalid.ms").replace("invalid.ms", "%FF.ms"),
        different,
    );
    let syms = ms_syntax::Names::global();
    let session = ms_check::Session::new();
    let mut docs = Documents::from([(main.uri.clone(), main.clone())]);
    let baseline = analyze(syms, &session, &main, &docs);
    assert!(
        baseline
            .diagnostics
            .iter()
            .any(|d| d.message.contains("expected Int, found String"))
    );
    docs.insert(invalid.uri.clone(), invalid);
    let checked = analyze(syms, &session, &main, &docs);
    assert!(
        checked
            .diagnostics
            .iter()
            .any(|d| d.message.contains("expected Int, found String"))
    );
}

#[test]
fn valid_encoded_replacement_characters_keep_their_file_identity() {
    let ws = Workspace::new("valid-uri-identity");
    let source = include_str!("uri_identity/main.ms");
    let replacement = include_str!("uri_identity/replacement.ms");
    let edited = include_str!("uri_identity/different.ms");
    std::fs::write(ws.path("consumer.ms"), source).unwrap();
    std::fs::write(ws.path("�.ms"), replacement).unwrap();
    let main = Document::new(ws.uri("consumer.ms"), source);
    let valid = Document::new(ws.uri("�.ms"), edited);
    assert_eq!(
        ms_driver::project::pathops::clean(&uri::filename(&valid.uri)),
        ms_driver::project::pathops::clean(&ws.path("�.ms"))
    );
    let syms = ms_syntax::Names::global();
    let session = ms_check::Session::new();
    let docs = Documents::from([(main.uri.clone(), main.clone()), (valid.uri.clone(), valid)]);
    assert!(analyze(syms, &session, &main, &docs).success());
}

#[test]
fn malformed_uris_never_reach_filesystem_analysis_or_overlays() {
    let ws = Workspace::new("invalid-uri-filesystem-boundary");
    let source = include_str!("uri_identity/different.ms");
    let valid = Document::new(ws.uri("valid.ms"), source);
    let invalid = Document::new("file:///unrelated/%FF.ms", source);
    let docs = Documents::from([
        (valid.uri.clone(), valid.clone()),
        (invalid.uri.clone(), invalid.clone()),
    ]);
    let syms = ms_syntax::Names::global();
    let mut checked = false;
    analyze_with(
        syms,
        &valid,
        &docs,
        Options::default(),
        &mut |_, options| {
            checked = true;
            assert!(options.overlay.contains_key(&valid.path()));
            assert!(!options.overlay.contains_key(&invalid.path()));
            Rc::new(Analysis::default())
        },
    );
    assert!(checked);
    let rejected = analyze_with(syms, &invalid, &docs, Options::default(), &mut |_, _| {
        panic!("malformed URI reached filesystem compilation")
    });
    assert!(rejected.program.is_none());
    assert!(
        ms_lsp::workspace::workspace_documents(&invalid, &docs, true, None)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn malformed_document_uris_are_rejected_by_the_protocol() {
    let ws = Workspace::new("invalid-uri-protocol");
    let invalid = "file:///unrelated/%FF.ms";
    let mut script = Script::initialize(ws.root.to_str().unwrap(), false);
    script.open(invalid, include_str!("uri_identity/different.ms"), 1);
    let id = script.at("textDocument/documentSymbol", invalid, 0, 0);
    let messages = script.rust();
    let response = messages
        .iter()
        .find(|m| m.get("id").and_then(Json::as_i64) == Some(id))
        .unwrap();
    assert_eq!(
        response
            .get("error")
            .and_then(|e| e.get("code"))
            .and_then(Json::as_i64),
        Some(-32602)
    );
    assert!(!messages.iter().any(|m| {
        m.get("params")
            .and_then(|p| p.get("uri"))
            .and_then(Json::as_str)
            == Some(invalid)
    }));
}

#[test]
fn malformed_workspace_roots_do_not_select_literal_percent_directories() {
    let ws = Workspace::new("invalid-uri-workspace-root");
    std::fs::create_dir(ws.path("%FF")).unwrap();
    std::fs::write(
        ws.path("%FF/marker.ms"),
        include_str!("uri_identity/marker.ms"),
    )
    .unwrap();
    let valid = ws.uri("%FF");
    let invalid = valid.replace("%25FF", "%FF");
    for folder in [false, true] {
        for (root, expected) in [(&invalid, false), (&valid, true)] {
            let mut script = Script::new();
            let params = if folder {
                obj([(
                    "workspaceFolders",
                    Json::Arr(vec![obj([
                        ("uri", root.as_str().into()),
                        ("name", "root".into()),
                    ])]),
                )])
            } else {
                obj([("rootUri", root.as_str().into())])
            };
            script.request("initialize", params);
            script.notify("initialized", obj([]));
            let id = script.request("workspace/symbol", obj([("query", "unique_marker".into())]));
            let messages = script.rust();
            let symbols = messages
                .iter()
                .find(|m| m.get("id").and_then(Json::as_i64) == Some(id))
                .unwrap()
                .get("result")
                .unwrap()
                .as_array()
                .unwrap();
            assert_eq!(
                !symbols.is_empty(),
                expected,
                "folder={folder}, root={root}"
            );
        }
    }
}

#[test]
fn valid_opaque_document_uris_still_reach_analysis() {
    let source = include_str!("uri_identity/different.ms");
    let document = Document::new("untitled:Untitled-1", source);
    let docs = Documents::from([(document.uri.clone(), document.clone())]);
    let mut reached = false;
    analyze_with(
        ms_syntax::Names::global(),
        &document,
        &docs,
        Options::default(),
        &mut |_, options| {
            reached = true;
            assert!(options.overlay.contains_key(&document.path()));
            Rc::new(Analysis::default())
        },
    );
    assert!(reached);
}

#[test]
fn rename_does_not_select_a_malformed_open_document_alias() {
    let ws = Workspace::new("invalid-uri-rename");
    let source = include_str!("uri_identity/percent-main.ms");
    let leaf = include_str!("uri_identity/different.ms");
    std::fs::write(ws.path("consumer.ms"), source).unwrap();
    std::fs::write(ws.path("%FF.ms"), leaf).unwrap();
    let main = Document::new(ws.uri("consumer.ms"), source);
    // A raw path is not an encoded document URI; decoding its %FF is invalid UTF-8.
    let malformed = Document::new(ws.path("%FF.ms"), leaf);
    assert!(uri::parse(&malformed.uri).is_none());
    let docs = Documents::from([
        (main.uri.clone(), main.clone()),
        (malformed.uri.clone(), malformed.clone()),
    ]);
    let syms = ms_syntax::Names::global();
    let checked = analyze(syms, &ms_check::Session::new(), &main, &docs);
    assert!(checked.success());
    let edits = ms_lsp::rename::rename(
        syms,
        &checked,
        checked.occurrence_index(syms),
        &main,
        ms_lsp::text::position(source, source.rfind("value").unwrap()),
        "renamed",
        None,
        Some(&docs),
    )
    .unwrap();
    let changes = edits.get("documentChanges").unwrap().as_array().unwrap();
    let uris: Vec<_> = changes
        .iter()
        .map(|c| {
            c.get("textDocument")
                .unwrap()
                .get("uri")
                .unwrap()
                .as_str()
                .unwrap()
        })
        .collect();
    assert!(uris.contains(&ws.uri("%FF.ms").as_str()));
    assert!(!uris.contains(&malformed.uri.as_str()));
}
