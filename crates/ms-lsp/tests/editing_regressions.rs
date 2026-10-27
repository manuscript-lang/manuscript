//! Editing features on incomplete or unusual sources: completion scope,
//! f-string interpolation, import actions and rename identity.

use ms_lsp::actions::editor_actions;
use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::completion_at;
use ms_lsp::json::Json;
use ms_lsp::lint::Tooling;
use ms_lsp::text::{self, Position, Range};
use ms_rt as _;

mod support;
use support::Workspace;

fn labels(source: &str, line: usize, character: usize) -> Vec<String> {
    let ws = Workspace::new("editing-completion");
    let d = Document::new(ws.uri("case.ms"), source);
    let at = Position { line, character };
    completion_at(&d, &Documents::new(), at, false)
        .expect("completion")
        .into_iter()
        .filter_map(|item| {
            item.json()
                .get("label")
                .and_then(|j| j.as_str())
                .map(str::to_string)
        })
        .collect()
}

/// The position between `val` and `ue` of the `return value` line.
fn inside_value(source: &str) -> (usize, usize) {
    let line = source
        .split('\n')
        .position(|l| l.contains("return value"))
        .expect("return line");
    let column = source.split('\n').nth(line).unwrap().find("value").unwrap() + 3;
    (line, column)
}

#[test]
fn completion_survives_an_earlier_unmatched_opener() {
    let valid = "def valid(value: Int) -> Int:\n    return value\n";
    for source in [
        format!("def broken(\n\n{valid}"),
        format!("def broken(\n    a: Int,\n\n{valid}"),
        format!("def broken(\r\n\r\n{}", valid.replace('\n', "\r\n")),
        format!("def broken(a: Int):\n    return foo(\n\n{valid}"),
        format!("{valid}\ndef broken(\n"),
    ] {
        let (line, character) = inside_value(&source);
        assert!(
            labels(&source, line, character).contains(&"value".to_string()),
            "no `value` in {source:?}"
        );
    }
}

#[test]
fn completion_works_inside_fstring_interpolation() {
    for expression in [
        "f\"hello {name}\"",
        "f\"{name} and {name}\"",
        "f\"a {greet(name)}\"",
        "f\"a {id(\"x\")} {name}\"",
    ] {
        let source = format!("def greet(name: String) -> String:\n    return {expression}\n");
        let column = source.split('\n').nth(1).unwrap().rfind("name").unwrap() + 3;
        assert!(
            labels(&source, 1, column).contains(&"name".to_string()),
            "no `name` in {expression}"
        );
    }
    // Literal text and an escaped brace stay suppressed.
    for expression in ["f\"hel{name}lo\"", "f\"\\{na\""] {
        let source = format!("def greet(name: String) -> String:\n    return {expression}\n");
        let column = source.split('\n').nth(1).unwrap().find("hel").unwrap_or(0)
            + if expression.contains("hel") { 3 } else { 14 };
        let found = labels(&source, 1, column);
        assert!(found.is_empty(), "literal text completed {found:?}");
    }
}

#[test]
fn completion_offers_members_inside_fstring_interpolation() {
    let source = "def greet(name: String) -> String:\n    return f\"hello {name.}\"\n";
    let column = source.split('\n').nth(1).unwrap().find("name.").unwrap() + 5;
    let found = labels(source, 1, column);
    assert!(found.iter().any(|l| l == "len" || l == "trim"), "{found:?}");
}

fn apply(source: &str, action: &Json) -> String {
    let changes = action
        .get("edit")
        .and_then(|e| e.get("documentChanges"))
        .and_then(|c| c.as_array())
        .and_then(|c| c.first())
        .and_then(|c| c.get("edits"))
        .expect("edits");
    let mut edits: Vec<(usize, usize, String)> = Vec::new();
    for e in changes.as_array().expect("edit list") {
        let range = Range::from_json(e.get("range").unwrap()).unwrap();
        edits.push((
            text::offset(source, range.start).unwrap(),
            text::offset(source, range.end).unwrap(),
            e.get("newText")
                .and_then(|t| t.as_str())
                .unwrap()
                .to_string(),
        ));
    }
    edits.sort_by_key(|e| std::cmp::Reverse(e.0));
    let mut result = source.to_string();
    for (start, end, text) in edits {
        result.replace_range(start..end, &text);
    }
    result
}

fn actions(source: &str, only: &str) -> (Document, Vec<Json>) {
    let ws = Workspace::new("editing-actions");
    let d = Document::new(ws.uri("main.ms"), source);
    let checked = analyze(&d, &Documents::new());
    let whole = Range {
        start: Position::default(),
        end: text::position(source, source.len()),
    };
    let found = editor_actions(&d, &checked, &Tooling, whole, &[only.to_string()]);
    (d, found)
}

fn title(action: &Json) -> &str {
    action.get("title").and_then(|t| t.as_str()).unwrap()
}

#[test]
fn removing_the_last_unused_import_drops_the_separator() {
    let body = "\ndef root(value: Float) -> Float:\n    return sqrt(value)\n";
    for (source, expected) in [
        (
            "from \"@std/math.ms\" import sqrt, sin\n",
            "from \"@std/math.ms\" import sqrt\n",
        ),
        (
            "from \"@std/math.ms\" import (sqrt, sin,)\n",
            "from \"@std/math.ms\" import (sqrt, )\n",
        ),
        (
            "from \"@std/math.ms\" import sin, sqrt\n",
            "from \"@std/math.ms\" import sqrt\n",
        ),
    ] {
        let source = format!("{source}{body}");
        let (_, found) = actions(&source, "quickfix");
        let action = found
            .iter()
            .find(|a| title(a) == "Remove unused import")
            .expect("quick fix");
        let fixed = apply(&source, action);
        assert!(fixed.starts_with(expected), "{fixed}");
        ms_syntax::format(&"main.ms".into(), &fixed).expect("fixed source parses");
    }
}

#[test]
fn organize_imports_moves_whole_multiline_declarations() {
    let source = include_str!("editing_regressions/multiline-imports.ms");
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        let (_, found) = actions(&source, "source.organizeImports");
        let action = found.first().expect("organize imports");
        let organized = apply(&source, action);
        assert!(
            organized.starts_with("from \"@std/math.ms\" import (") && organized.contains("sqrt,"),
            "{organized}"
        );
        assert!(organized.find("@std/math").unwrap() < organized.find("@std/string").unwrap());
        ms_syntax::format(&"main.ms".into(), &organized).expect("organized source parses");
    }
}

const IDENTITY: &str = "def identity(value: Int) -> Int:\n    return value\n";

fn rename_edit(uri: &str) -> Json {
    let d = Document {
        version: 42,
        ..Document::new(uri, IDENTITY)
    };
    let mut docs = Documents::new();
    docs.insert(d.uri.clone(), d.clone());
    let checked = analyze(&d, &docs);
    let at = Position {
        line: 0,
        character: 15,
    };
    ms_lsp::rename::rename(&checked, checked.index(), &d, at, "item", None, Some(&docs))
        .expect("rename")
}

fn assert_versioned(edit: &Json, uri: &str) {
    let change = edit
        .get("documentChanges")
        .and_then(|c| c.as_array())
        .and_then(|c| c.first())
        .expect("change");
    let document = change.get("textDocument").expect("document");
    assert_eq!(document.get("uri").and_then(|u| u.as_str()), Some(uri));
    assert_eq!(document.get("version").and_then(|v| v.as_i64()), Some(42));
    assert!(
        change
            .get("edits")
            .and_then(|e| e.as_array())
            .is_some_and(|e| e.len() == 2)
    );
}

#[test]
fn rename_keeps_the_open_percent_encoded_uri_and_version() {
    let ws = Workspace::new("rename-encoded");
    let uri = ws.uri("%72eal.ms");
    let edit = rename_edit(&uri);
    assert_versioned(&edit, &uri);
}

#[cfg(unix)]
#[test]
fn rename_through_a_symlink_keeps_the_open_uri_and_version() {
    let ws = Workspace::new("rename-symlink");
    std::fs::write(ws.path("real.ms"), IDENTITY).unwrap();
    std::os::unix::fs::symlink("real.ms", ws.path("alias.ms")).unwrap();
    let uri = ws.uri("alias.ms");
    let edit = rename_edit(&uri);
    assert_versioned(&edit, &uri);
}
