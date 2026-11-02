//! Independent projects can contain identical logical module paths and offsets.

mod support;

use ms_lsp::analysis::{Document, Documents, analyze, workspace_analysis};
use ms_lsp::json::{Json, obj};
use ms_lsp::nav::{self, Navigate};
use ms_lsp::text;
use ms_lsp::workspace::workspace_references;
use support::{Script, Workspace};

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

#[test]
fn methods_contract_operations_and_cases_stay_in_their_project() {
    let ws = nested_projects();
    let source = include_str!("navigation_identity/operations.ms");
    std::fs::write(ws.path("project/operations.ms"), source).unwrap();
    std::fs::write(ws.path("project/nested/operations.ms"), source).unwrap();
    let d = Document::new(ws.uri("project/operations.ms"), source);
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let analysis = analyze(&d, &docs);
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    for name in ["amount", "label", "Number"] {
        let entry = analysis
            .index()
            .iter()
            .find(|entry| {
                entry.declaration
                    && entry.name == name
                    && entry.file.as_str() == analysis.module_file(&d)
            })
            .unwrap();
        let at = text::position(source, entry.offset);
        let references =
            workspace_references(&analysis, analysis.index(), &d, &docs, at, true, None);
        assert!(references.len() >= 2, "{name}: {references:?}");
        assert!(
            references.iter().all(|location| {
                location.get("uri").and_then(Json::as_str) == Some(d.uri.as_str())
            }),
            "{name}: {references:?}"
        );
        let rename = ms_lsp::rename::rename(
            &analysis,
            analysis.index(),
            &d,
            at,
            "renamed",
            None,
            Some(&docs),
        )
        .unwrap();
        let changes = rename.get("documentChanges").unwrap().as_array().unwrap();
        assert_eq!(changes.len(), 1, "{name}: {changes:?}");
        assert_eq!(
            changes[0]
                .get("textDocument")
                .unwrap()
                .get("uri")
                .and_then(Json::as_str),
            Some(d.uri.as_str())
        );
    }
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
}

fn answer(messages: &[Json], id: i64) -> &Json {
    messages
        .iter()
        .find(|message| message.get("id").and_then(Json::as_i64) == Some(id))
        .unwrap()
        .get("result")
        .unwrap()
}

#[test]
fn incremental_unicode_edits_keep_navigation_and_rename_on_the_live_snapshot() {
    for newline in ["\n", "\r\n"] {
        let ws = Workspace::new("navigation-live-unicode");
        let uri = ws.uri("unicode.ms");
        let source = include_str!("navigation_identity/unicode.ms").replace('\n', newline);
        let mut script = Script::initialize(&ws.root.to_string_lossy(), false);
        script.open(&uri, &source, 1);
        let at = text::position(&source, source.rfind("value").unwrap());
        let before = script.at("textDocument/definition", &uri, at.line, at.character);
        let emoji = source.find('😀').unwrap();
        let range = text::Range {
            start: text::position(&source, emoji),
            end: text::position(&source, emoji + '😀'.len_utf8()),
        };
        let changed = source.replacen('😀', "😀😀", 1);
        change(
            &mut script,
            &uri,
            2,
            vec![obj([("range", range.json()), ("text", "😀😀".into())])],
        );
        let at = text::position(&changed, changed.rfind("value").unwrap());
        let after = script.at("textDocument/definition", &uri, at.line, at.character);
        // Stale full replacements and invalid surrogate splits must not replace
        // the latest valid snapshot or advance its version.
        change(&mut script, &uri, 2, vec![obj([("text", "stale".into())])]);
        let split = text::Position {
            character: range.start.character + 1,
            ..range.start
        };
        change(
            &mut script,
            &uri,
            3,
            vec![obj([
                ("range", text::Range::at(split).json()),
                ("text", "invalid".into()),
            ])],
        );
        let rename = script.request(
            "textDocument/rename",
            obj([
                ("textDocument", obj([("uri", uri.clone().into())])),
                ("position", at.json()),
                ("newName", "item".into()),
            ]),
        );
        let messages = script.rust();
        assert_eq!(answer(&messages, before), answer(&messages, after));
        let change = &answer(&messages, rename)
            .get("documentChanges")
            .unwrap()
            .as_array()
            .unwrap()[0];
        assert_eq!(
            change
                .get("textDocument")
                .unwrap()
                .get("version")
                .and_then(Json::as_i64),
            Some(2)
        );
        let edits = change.get("edits").unwrap().as_array().unwrap();
        assert_eq!(edits.len(), 2);
        for edit in edits {
            let range = text::Range::from_json(edit.get("range").unwrap()).unwrap();
            let start = text::offset(&changed, range.start).unwrap();
            let end = text::offset(&changed, range.end).unwrap();
            assert_eq!(&changed[start..end], "value");
        }
    }
}

#[test]
fn definitions_follow_unsaved_imported_sources_and_close_restores_disk() {
    let ws = Workspace::new("navigation-live-imports");
    let uri = ws.uri("project/main.ms");
    let util = ws.uri("project/util.ms");
    let source = ws.read("project/main.ms");
    let disk = ws.read("project/util.ms");
    let at = text::position(&source, source.rfind("double").unwrap());
    let mut script = Script::initialize(&ws.root.to_string_lossy(), false);
    script.open(&uri, &source, 1);
    let before = script.at("textDocument/definition", &uri, at.line, at.character);
    script.open(&util, &format!("# 😀 unsaved\n{disk}"), 8);
    let after = script.at("textDocument/definition", &uri, at.line, at.character);
    script.notify(
        "textDocument/didClose",
        obj([("textDocument", obj([("uri", util.clone().into())]))]),
    );
    let closed = script.at("textDocument/definition", &uri, at.line, at.character);
    let messages = script.rust();
    assert_eq!(answer(&messages, before), answer(&messages, closed));
    let location = &answer(&messages, after).as_array().unwrap()[0];
    assert_eq!(
        location.get("uri").and_then(Json::as_str),
        Some(util.as_str())
    );
    let range = text::Range::from_json(location.get("range").unwrap()).unwrap();
    assert_eq!(range.start.line, 4);
    assert_eq!(
        std::fs::read_to_string(ws.path("project/util.ms")).unwrap(),
        disk
    );
}
