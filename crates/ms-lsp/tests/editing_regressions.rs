//! Editing features on incomplete or unusual sources: completion scope,
//! f-string interpolation, import actions and rename identity.

use ms_lsp::actions::editor_actions;
use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::completion_at;
use ms_lsp::json::{Json, obj};
use ms_lsp::lint::Tooling;
use ms_lsp::text::{self, Position, Range};
use ms_rt as _;

use crate::support;
use support::Workspace;

fn labels(source: &str, line: usize, character: usize) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("editing-completion");
    let d = Document::new(ws.uri("case.ms"), source);
    let at = Position { line, character };
    completion_at(
        syms,
        &ms_check::Session::new(),
        &d,
        &Documents::new(),
        at,
        false,
    )
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

fn apply_completion(source: &str, completion: &Json) -> String {
    let mut edits = completion
        .get("additionalTextEdits")
        .and_then(Json::as_array)
        .expect("import edit")
        .to_vec();
    edits.push(completion.get("textEdit").unwrap().clone());
    let action = obj([(
        "edit",
        obj([(
            "documentChanges",
            Json::Arr(vec![obj([("edits", Json::Arr(edits))])]),
        )]),
    )]);
    apply(source, &action)
}

fn actions(source: &str, only: &str) -> (Document, Vec<Json>) {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("editing-actions");
    let d = Document::new(ws.uri("main.ms"), source);
    let checked = analyze(syms, &ms_check::Session::new(), &d, &Documents::new());
    let whole = Range {
        start: Position::default(),
        end: text::position(source, source.len()),
    };
    let found = editor_actions(
        syms,
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
fn adding_imports_preserves_grouped_declarations_and_file_directives() {
    let syms = ms_syntax::Names::global();
    for source in [
        include_str!("editing_regressions/import-fix-grouped.ms"),
        include_str!("editing_regressions/import-fix-header.ms"),
    ] {
        for source in [source.to_string(), source.replace('\n', "\r\n")] {
            let (_, found) = actions(&source, "quickfix");
            let action = found
                .iter()
                .find(|a| title(a) == "Add `import Bytes from \"@std/bytes.ms\"`")
                .expect("add import fix");
            let fixed = apply(&source, action);
            ms_syntax::format(&"main.ms".into(), &fixed).expect("fixed source parses");
            let d = Document::new("file:///tmp/import-fix.ms", &fixed);
            let checked = analyze(syms, &ms_check::Session::new(), &d, &Documents::new());
            assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
            let program = checked.program.as_ref().expect("checked program");
            assert!(
                ms_tooling::lint::lint_program(syms, program)
                    .iter()
                    .all(|finding| finding.code != "MSL116"),
                "file directive lost: {fixed}"
            );
            let (_, repeated) = actions(&fixed, "quickfix");
            assert!(
                repeated
                    .iter()
                    .all(|a| !title(a).starts_with("Add `import Bytes"))
            );
        }
    }
}

#[test]
fn completion_auto_import_preserves_file_effect_directives() {
    let syms = ms_syntax::Names::global();
    let source = include_str!("editing_regressions/import-fix-header.ms");
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        for snippets in [false, true] {
            let d = Document::new("file:///tmp/import-completion.ms", &source);
            let at = text::position(&source, source.find("Bytes").unwrap() + "Bytes".len());
            let completion = completion_at(
                syms,
                &ms_check::Session::new(),
                &d,
                &Documents::new(),
                at,
                snippets,
            )
            .expect("completion")
            .into_iter()
            .map(|item| item.json())
            .find(|item| item.get("label").and_then(Json::as_str) == Some("Bytes"))
            .expect("Bytes completion");
            let fixed = apply_completion(&source, &completion);
            assert!(
                fixed.starts_with("// ms: allow_effect std.console.write"),
                "{fixed}"
            );
            let updated = Document::new(d.uri.clone(), &fixed);
            let checked = analyze(syms, &ms_check::Session::new(), &updated, &Documents::new());
            assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
            assert!(
                checked
                    .program
                    .as_ref()
                    .unwrap()
                    .effect_violations
                    .is_empty(),
                "{fixed}"
            );
        }
    }
}

#[test]
fn project_completions_quote_paths_and_prefix_dot_filenames() {
    let syms = ms_syntax::Names::global();
    let source = include_str!("editing_regressions/project-gadget-use.ms");
    for file in ["{gadget}.ms", ".gadget.ms", "space é😀.ms"] {
        let ws = Workspace::new("project-completion-path");
        std::fs::write(
            ws.path(file),
            include_str!("editing_regressions/project-gadget.ms"),
        )
        .unwrap();
        let d = Document::new(ws.uri("main.ms"), source);
        for snippets in [false, true] {
            let at = text::position(source, source.find("Gadget").unwrap() + "Gadget".len());
            let item = completion_at(
                syms,
                &ms_check::Session::new(),
                &d,
                &Documents::new(),
                at,
                snippets,
            )
            .expect("completion")
            .into_iter()
            .map(|item| item.json())
            .find(|item| item.get("label").and_then(Json::as_str) == Some("Gadget"))
            .expect("project completion");
            let fixed = apply_completion(source, &item);
            let parsed =
                ms_syntax::parser::parse(&"main.ms".into(), &fixed).expect("completion parses");
            assert_eq!(parsed.imports[0].path.as_ref(), format!("./{file}"));
            let updated = Document::new(d.uri.clone(), &fixed);
            let checked = analyze(syms, &ms_check::Session::new(), &updated, &Documents::new());
            assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
        }
    }
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
    for fixture in [
        include_str!("editing_regressions/multiline-imports.ms"),
        include_str!("editing_regressions/import-fix-grouped.ms"),
    ] {
        for source in [fixture.to_string(), format!("{fixture}\nfn broken(\n")] {
            for source in [source.to_string(), source.replace('\n', "\r\n")] {
                let (_, found) = actions(&source, "source.organizeImports");
                let action = found.first().expect("organize imports");
                let organized = apply(&source, action);
                assert!(organized.starts_with("import ("), "{organized}");
                assert!(
                    organized.find("@std/math").unwrap() < organized.find("@std/string").unwrap()
                );
                let valid = organized.split("fn broken(").next().unwrap();
                ms_syntax::format(&"main.ms".into(), valid).expect("organized imports parse");
            }
        }
    }
}

const IDENTITY: &str = "fn identity(value: Int) Int:\n    return value\n";

fn rename_edit(uri: &str) -> Json {
    let syms = ms_syntax::Names::global();
    let d = Document {
        version: 42,
        ..Document::new(uri, IDENTITY)
    };
    let mut docs = Documents::new();
    docs.insert(d.uri.clone(), d.clone());
    let checked = analyze(syms, &ms_check::Session::new(), &d, &docs);
    let at = Position {
        line: 0,
        character: 15,
    };
    ms_lsp::rename::rename(
        syms,
        &checked,
        checked.occurrence_index(syms),
        &d,
        at,
        "item",
        None,
        Some(&docs),
    )
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
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("rename-lengths");
    let source = include_str!("editing_regressions/repeated-rename.ms");
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        for name in ["x", "renamed_value"] {
            let d = Document::new(ws.uri("repeat.ms"), &source);
            let docs = Documents::from([(d.uri.clone(), d.clone())]);
            let checked = analyze(syms, &ms_check::Session::new(), &d, &docs);
            assert!(checked.success(), "{:?}", checked.diagnostics);
            // Select the final use after a supplementary Unicode character.
            let offset = source.rfind("value").unwrap();
            let edit = ms_lsp::rename::rename(
                syms,
                &checked,
                checked.occurrence_index(syms),
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
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("rename-unread");
    let source = "fn identity(value: Int) Int:\n    let spare = 1\n    return value\n";
    let d = Document::new(ws.uri("unread.ms"), source);
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let checked = analyze(syms, &ms_check::Session::new(), &d, &docs);
    assert!(
        !checked.success() && checked.resolves(),
        "{:?}",
        checked.diagnostics
    );
    let offset = source.rfind("value").unwrap();
    let edit = ms_lsp::rename::rename(
        syms,
        &checked,
        checked.occurrence_index(syms),
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
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("prepare-local");
    let source = include_str!("editing_regressions/prepare-local.ms");
    let d = Document::new(ws.uri("project/main.ms"), source);
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let checked = analyze(syms, &ms_check::Session::new(), &d, &docs);
    assert!(checked.success(), "{:?}", checked.diagnostics);
    let polls = std::cell::Cell::new(0);
    let cancel = || {
        polls.set(polls.get() + 1);
        polls.get() > 1
    };
    let answer = ms_lsp::rename::rename(
        syms,
        &checked,
        checked.occurrence_index(syms),
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
        .occurrence_index(syms)
        .iter()
        .filter(|o| !o.declaration)
        .cloned()
        .collect();
    assert!(
        ms_lsp::rename::rename(
            syms,
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
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("prepare-identities");
    for (relative, name) in [
        ("project/main.ms", "double"),
        ("project/main.ms", "value"),
        ("main.ms", "expect_equal"),
    ] {
        let d = Document::new(ws.uri(relative), ws.read(relative));
        let docs = Documents::from([(d.uri.clone(), d.clone())]);
        let checked = analyze(syms, &ms_check::Session::new(), &d, &docs);
        assert!(checked.success(), "{:?}", checked.diagnostics);
        let file = checked.module_file(syms, &d);
        let entry = checked
            .occurrence_index(syms)
            .iter()
            .find(|entry| syms.str(entry.file) == file && entry.name == name)
            .expect("checked occurrence");
        let answer = ms_lsp::rename::rename(
            syms,
            &checked,
            checked.occurrence_index(syms),
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
    let syms = ms_syntax::Names::global();
    for file in ["lib/blobs.ms", "lib/{blobs}.ms"] {
        let ws = Workspace::new("project-import");
        std::fs::create_dir_all(ws.path("lib")).unwrap();
        std::fs::write(ws.path(file), "export type Bytes:\n    size: Int\n").unwrap();
        let source = "fn size(b: Bytes) Int:\n    return 0\n";
        let d = Document::new(ws.uri("main.ms"), source);
        let checked = analyze(syms, &ms_check::Session::new(), &d, &Documents::new());
        let whole = Range {
            start: Position::default(),
            end: text::position(source, source.len()),
        };
        let found = editor_actions(syms, &d, &checked, &Tooling, &Documents::new(), whole, &[]);
        let titles: Vec<&str> = found
            .iter()
            .map(title)
            .filter(|t| t.starts_with("Add `"))
            .collect();
        assert_eq!(titles.len(), 2);
        assert_eq!(titles[1], "Add `import Bytes from \"@std/bytes.ms\"`");
        let first = found.iter().find(|a| title(a) == titles[0]).unwrap();
        let fixed = apply(source, first);
        let parsed =
            ms_syntax::parser::parse(&"main.ms".into(), &fixed).expect("fixed source parses");
        assert_eq!(parsed.imports[0].path.as_ref(), format!("./{file}"));
        let updated = Document::new(d.uri.clone(), &fixed);
        let checked = analyze(syms, &ms_check::Session::new(), &updated, &Documents::new());
        assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
    }
}

#[test]
fn checker_fixes_become_quick_fixes() {
    let source = "export fn main() Int:\n    let n: Strin = \"a\"\n    return n.length()\n";
    let (_, found) = actions(source, "quickfix");
    let action = found
        .iter()
        .find(|a| title(a) == "Replace with `String`")
        .expect("misspelling fix");
    assert_eq!(apply(source, action), source.replace("Strin ", "String "));
}

/// A checkout's `stdlib/` sources import the internal modules; opened from disk they report nothing.
#[test]
fn checkout_stdlib_sources_report_no_diagnostics() {
    let syms = ms_syntax::Names::global();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../stdlib");
    for file in ["io/io.ms", "net/router.ms"] {
        let path = std::fs::canonicalize(root.join(file)).expect("stdlib file");
        let source = std::fs::read_to_string(&path).expect("read");
        let d = Document::new(ms_lsp::uri::file_uri(path.to_str().unwrap()), &source);
        let result = analyze(syms, &ms_check::Session::new(), &d, &Documents::new());
        let messages: Vec<_> = result
            .diagnostics
            .iter()
            .map(|d| {
                format!(
                    "{} {}",
                    d.file,
                    d.message.chars().take(40).collect::<String>()
                )
            })
            .collect();
        assert!(messages.is_empty(), "{file}: {messages:?}");
    }
}

#[test]
fn whitespace_actions_preserve_multiline_string_data() {
    for raw in ["", "r"] {
        let source = format!(
            "fn text() String:  \n    return {raw}\"\"\"\n        é{{1 + 2}}  \t\n            \t\n        \"\"\"\n"
        );
        for input in [source.clone(), source.replace('\n', "\r\n")] {
            let (_, found) = actions(&input, "quickfix");
            let whitespace: Vec<_> = found
                .iter()
                .filter(|a| title(a) == "Remove trailing whitespace")
                .collect();
            assert_eq!(whitespace.len(), 1, "{found:?}");
            let fixed = apply(&input, whitespace[0]);
            assert_eq!(fixed, input.replacen("String:  ", "String:", 1));
        }
    }
}
