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
    let valid = "fn valid(value: Int) Int:\n    return value\n";
    for source in [
        format!("fn broken(\n\n{valid}"),
        format!("fn broken(\n    a: Int,\n\n{valid}"),
        format!("fn broken(\r\n\r\n{}", valid.replace('\n', "\r\n")),
        format!("fn broken(a: Int):\n    return foo(\n\n{valid}"),
        format!("{valid}\nfn broken(\n"),
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
        "\"hello {name}\"",
        "\"{name} and {name}\"",
        "\"a {greet(name)}\"",
        "\"a {id(\"x\")} {name}\"",
    ] {
        let source = format!("fn greet(name: String) String:\n    return {expression}\n");
        let column = source.split('\n').nth(1).unwrap().rfind("name").unwrap() + 3;
        assert!(
            labels(&source, 1, column).contains(&"name".to_string()),
            "no `name` in {expression}"
        );
    }
    // Literal text and an escaped brace stay suppressed.
    for expression in ["\"hel{name}lo\"", "\"\\{na\""] {
        let source = format!("fn greet(name: String) String:\n    return {expression}\n");
        let column = source.split('\n').nth(1).unwrap().find("hel").unwrap_or(0)
            + if expression.contains("hel") { 3 } else { 14 };
        let found = labels(&source, 1, column);
        assert!(found.is_empty(), "literal text completed {found:?}");
    }
}

#[test]
fn completion_offers_members_inside_fstring_interpolation() {
    let source = "fn greet(name: String) String:\n    return \"hello {name.}\"\n";
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
    let found = editor_actions(
        &d,
        &checked,
        &Tooling,
        &Documents::new(),
        whole,
        &[only.to_string()],
    );
    (d, found)
}

fn title(action: &Json) -> &str {
    action.get("title").and_then(|t| t.as_str()).unwrap()
}

#[test]
fn removing_the_last_unused_import_drops_the_separator() {
    let body = "\nfn root(value: Float) Float:\n    return sqrt(value)\n";
    for (source, expected) in [
        (
            "import sqrt, sin from \"@std/math/math.ms\"\n",
            "import sqrt from \"@std/math/math.ms\"\n",
        ),
        (
            "import sqrt, sin from \"@std/math/math.ms\"\n",
            "import sqrt from \"@std/math/math.ms\"\n",
        ),
        (
            "import sin, sqrt from \"@std/math/math.ms\"\n",
            "import sqrt from \"@std/math/math.ms\"\n",
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
            organized.starts_with("import (") && organized.contains("leading_zeros"),
            "{organized}"
        );
        assert!(organized.find("@std/math").unwrap() < organized.find("@std/string").unwrap());
        ms_syntax::format(&"main.ms".into(), &organized).expect("organized source parses");
    }
}

const IDENTITY: &str = "fn identity(value: Int) Int:\n    return value\n";

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

#[test]
fn rename_preserves_unicode_and_original_ranges_when_name_length_changes() {
    let ws = Workspace::new("rename-lengths");
    let source = include_str!("editing_regressions/repeated-rename.ms");
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        for name in ["x", "renamed_value"] {
            let d = Document::new(ws.uri("repeat.ms"), &source);
            let docs = Documents::from([(d.uri.clone(), d.clone())]);
            let checked = analyze(&d, &docs);
            assert!(checked.success(), "{:?}", checked.diagnostics);
            // Select the final use after a supplementary Unicode character.
            let offset = source.rfind("value").unwrap();
            let edit = ms_lsp::rename::rename(
                &checked,
                checked.index(),
                &d,
                text::position(&source, offset),
                name,
                None,
                Some(&docs),
            )
            .expect("rename");
            let action = ms_lsp::json::obj([("edit", edit)]);
            assert_eq!(apply(&source, &action), source.replace("value", name));
        }
    }
}

#[test]
fn rename_ignores_an_unrelated_unread_binding() {
    let ws = Workspace::new("rename-unread");
    let source = "fn identity(value: Int) Int:\n    let spare = 1\n    return value\n";
    let d = Document::new(ws.uri("unread.ms"), source);
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let checked = analyze(&d, &docs);
    assert!(
        !checked.success() && checked.resolves(),
        "{:?}",
        checked.diagnostics
    );
    let offset = source.rfind("value").unwrap();
    let edit = ms_lsp::rename::rename(
        &checked,
        checked.index(),
        &d,
        text::position(source, offset),
        "item",
        None,
        Some(&docs),
    )
    .expect("rename");
    let action = ms_lsp::json::obj([("edit", edit)]);
    assert_eq!(apply(source, &action), source.replace("value", "item"));
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

#[test]
fn prepare_rename_uses_the_checked_declaration_without_scanning_workspace() {
    let ws = Workspace::new("prepare-local");
    let source = include_str!("editing_regressions/prepare-local.ms");
    let d = Document::new(ws.uri("project/main.ms"), source);
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let checked = analyze(&d, &docs);
    assert!(checked.success(), "{:?}", checked.diagnostics);
    let polls = std::cell::Cell::new(0);
    let cancel = || {
        polls.set(polls.get() + 1);
        polls.get() > 1
    };
    let answer = ms_lsp::rename::rename(
        &checked,
        checked.index(),
        &d,
        Position {
            line: 0,
            character: 5,
        },
        "",
        Some(&cancel),
        Some(&docs),
    )
    .expect("preparing a checked source declaration needs no workspace scan");
    assert_eq!(
        answer.get("placeholder").and_then(|v| v.as_str()),
        Some("focus")
    );
    assert_eq!(
        answer.get("range"),
        Some(
            &text::Range {
                start: Position {
                    line: 0,
                    character: 3
                },
                end: Position {
                    line: 0,
                    character: 8
                },
            }
            .json()
        )
    );

    let external: Vec<_> = checked
        .index()
        .iter()
        .filter(|o| !o.declaration)
        .cloned()
        .collect();
    assert!(
        ms_lsp::rename::rename(
            &checked,
            &external,
            &d,
            Position {
                line: 1,
                character: 12
            },
            "",
            None,
            Some(&docs),
        )
        .unwrap_err()
        .contains("external")
    );
}

#[test]
fn prepare_rename_accepts_imported_declarations_and_bindings_but_not_stdlib() {
    let ws = Workspace::new("prepare-identities");
    for (relative, name) in [
        ("project/main.ms", "double"),
        ("project/main.ms", "value"),
        ("main.ms", "expect_equal"),
    ] {
        let d = Document::new(ws.uri(relative), ws.read(relative));
        let docs = Documents::from([(d.uri.clone(), d.clone())]);
        let checked = analyze(&d, &docs);
        assert!(checked.success(), "{:?}", checked.diagnostics);
        let file = checked.module_file(&d);
        let entry = checked
            .index()
            .iter()
            .find(|entry| entry.file.as_str() == file && entry.name == name)
            .expect("checked occurrence");
        let answer = ms_lsp::rename::rename(
            &checked,
            checked.index(),
            &d,
            text::position(&d.text, entry.offset),
            "",
            None,
            Some(&docs),
        );
        if entry.key.contains(":@std/") {
            assert!(answer.unwrap_err().contains("read-only"));
        } else {
            assert_eq!(
                answer.unwrap().get("placeholder").and_then(|v| v.as_str()),
                Some(name)
            );
        }
    }
}

#[test]
fn unresolved_standard_name_offers_an_add_import_fix() {
    for (source, expected) in [
        (
            "fn size(b: Bytes) Int:\n    return 0\n",
            "import Bytes from \"@std/bytes.ms\"\nfn size(b: Bytes) Int:\n    return 0\n",
        ),
        (
            "import sqrt from \"@std/math/math.ms\"\n\nfn size(b: Bytes) Int:\n    return 0\n",
            "import sqrt from \"@std/math/math.ms\"\nimport Bytes from \"@std/bytes.ms\"\n\nfn size(b: Bytes) Int:\n    return 0\n",
        ),
    ] {
        let (_, found) = actions(source, "quickfix");
        let action = found
            .iter()
            .find(|a| title(a) == "Add `import Bytes from \"@std/bytes.ms\"`")
            .expect("add import fix");
        assert_eq!(apply(source, action), expected);
    }
}

#[test]
fn project_exports_are_offered_before_standard_ones() {
    let ws = Workspace::new("project-import");
    std::fs::create_dir_all(ws.path("lib")).unwrap();
    std::fs::write(
        ws.path("lib/blobs.ms"),
        "export type Bytes:\n    size: Int\n",
    )
    .unwrap();
    let source = "fn size(b: Bytes) Int:\n    return 0\n";
    let d = Document::new(ws.uri("main.ms"), source);
    let checked = analyze(&d, &Documents::new());
    let whole = Range {
        start: Position::default(),
        end: text::position(source, source.len()),
    };
    let found = editor_actions(&d, &checked, &Tooling, &Documents::new(), whole, &[]);
    let titles: Vec<&str> = found
        .iter()
        .map(title)
        .filter(|t| t.starts_with("Add `"))
        .collect();
    assert_eq!(
        titles,
        [
            "Add `import Bytes from \"./lib/blobs.ms\"`",
            "Add `import Bytes from \"@std/bytes.ms\"`"
        ]
    );
    let first = found.iter().find(|a| title(a) == titles[0]).unwrap();
    assert!(apply(source, first).starts_with("import Bytes from \"./lib/blobs.ms\"\n"));
}
