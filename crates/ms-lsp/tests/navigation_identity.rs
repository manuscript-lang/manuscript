//! Independent projects can contain identical logical module paths and offsets.

mod support;

use ms_lsp::analysis::{Document, Documents, analyze, workspace_analysis};
use ms_lsp::json::Json;
use ms_lsp::nav::{self, Navigate};
use ms_lsp::text;
use ms_lsp::workspace::workspace_references;
use support::Workspace;

fn nested_projects() -> Workspace {
    let ws = Workspace::new("navigation-identity");
    std::fs::create_dir(ws.path("project/nested")).unwrap();
    for name in ["ms.toml", "main.ms", "util.ms", "helper.ms"] {
        std::fs::copy(
            ws.path(&format!("project/{name}")),
            ws.path(&format!("project/nested/{name}")),
        )
        .unwrap();
    }
    ws
}

#[test]
fn references_do_not_cross_independent_project_identities() {
    let ws = nested_projects();
    let d = Document::new(ws.uri("project/util.ms"), ws.read("project/util.ms"));
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let analysis = analyze(&d, &docs);
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    for name in ["double", "n", "Counter", "count"] {
        let selected = analysis
            .index()
            .iter()
            .find(|entry| {
                entry.declaration
                    && entry.name == name
                    && entry.file.as_str() == analysis.module_file(&d)
            })
            .unwrap();
        let at = text::position(&d.text, selected.offset);
        for include in [false, true] {
            let locations =
                workspace_references(&analysis, analysis.index(), &d, &docs, at, include, None);
            assert!(!locations.is_empty(), "{name}: no references");
            assert!(
                locations.iter().all(|location| {
                    let uri = location.get("uri").and_then(Json::as_str).unwrap();
                    uri == d.uri
                        || uri == ws.uri("project/main.ms")
                        || uri == ws.uri("project/helper.ms")
                }),
                "{name}: {locations:?}"
            );
        }
        let definition = nav::navigation(&analysis, &d, at, Navigate::Definition, analysis.index());
        assert_eq!(
            definition.as_array().unwrap()[0]
                .get("uri")
                .and_then(Json::as_str),
            Some(d.uri.as_str())
        );
    }
}

#[test]
fn rename_does_not_edit_an_identical_module_in_a_nested_project() {
    let ws = nested_projects();
    let d = Document {
        version: 7,
        ..Document::new(ws.uri("project/util.ms"), ws.read("project/util.ms"))
    };
    let nested = Document {
        version: 19,
        ..Document::new(ws.uri("project/nested/util.ms"), d.text.clone())
    };
    let docs = Documents::from([
        (d.uri.clone(), d.clone()),
        (nested.uri.clone(), nested.clone()),
    ]);
    let analysis = analyze(&d, &docs);
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    for name in ["double", "n", "Counter", "count"] {
        let selected = analysis
            .index()
            .iter()
            .find(|entry| {
                entry.declaration
                    && entry.name == name
                    && entry.file.as_str() == analysis.module_file(&d)
            })
            .unwrap();
        let answer = ms_lsp::rename::rename(
            &analysis,
            analysis.index(),
            &d,
            text::position(&d.text, selected.offset),
            "renamed",
            None,
            Some(&docs),
        )
        .unwrap();
        let changes = answer.get("documentChanges").unwrap().as_array().unwrap();
        assert!(!changes.is_empty());
        for change in changes {
            let document = change.get("textDocument").unwrap();
            let uri = document.get("uri").and_then(Json::as_str).unwrap();
            assert!(
                uri == d.uri
                    || uri == ws.uri("project/main.ms")
                    || uri == ws.uri("project/helper.ms"),
                "{name}: edited unrelated project: {change:?}"
            );
            if uri == d.uri {
                assert_eq!(document.get("version").and_then(Json::as_i64), Some(7));
            }
        }
    }
}

#[test]
fn one_source_keeps_its_identity_when_analysis_roots_differ() {
    let ws = Workspace::new("navigation-root-identity");
    std::fs::create_dir(ws.path("sub")).unwrap();
    let source = ws.read("project/util.ms");
    std::fs::write(ws.path("sub/util.ms"), &source).unwrap();
    let d = Document::new(ws.uri("sub/util.ms"), &source);
    // The importing standalone file sees sub/util.ms; checking the source
    // directly sees util.ms. These must still describe the same declaration.
    let caller = Document::new(
        ws.uri("caller.ms"),
        include_str!("fixtures/project/main.ms")
            .replace("./util.ms", "./sub/util.ms")
            .replace("./helper.ms", "./project/helper.ms"),
    );
    let docs = Documents::from([
        (d.uri.clone(), d.clone()),
        (caller.uri.clone(), caller.clone()),
    ]);
    let direct = workspace_analysis(&d, &docs);
    let imported = workspace_analysis(&caller, &docs);
    for analysis in [&direct, &imported] {
        assert!(analysis.success(), "{:?}", analysis.diagnostics);
    }
    for name in ["double", "n", "Counter", "count"] {
        let key = |analysis: &ms_lsp::analysis::Analysis| {
            analysis
                .index()
                .iter()
                .find(|entry| {
                    entry.declaration
                        && entry.name == name
                        && entry.file.as_str() == analysis.module_file(&d)
                })
                .unwrap()
                .key
                .clone()
        };
        assert_eq!(key(&direct), key(&imported), "{name}");
    }
}
