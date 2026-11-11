//! Completion contexts preserve legal source and existing argument edits.

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::completion_at;
use ms_lsp::text::{Position, Range};
use ms_rt as _;

use crate::support;
use support::Workspace;

#[test]
fn field_and_column_zero_parameter_annotations_keep_type_context() {
    let syms = ms_syntax::Names::global();
    let session = support::session();
    let workspace = Workspace::new("completion-field-types");
    for newline in ["\n", "\r\n"] {
        let fixture = include_str!("completion/field-types.ms").replace('\n', newline);
        let baseline = Document::new(workspace.uri("fields.ms"), fixture.clone());
        assert!(
            analyze(syms, &session, &baseline, &Documents::new())
                .diagnostics
                .is_empty()
        );
        for snippets in [false, true] {
            for (prefix, name) in [
                ("nested: Pay", "Payload"),
                ("data: T", "T"),
                ("value: T", "T"),
                ("packet: Pay", "Payload"),
                ("data: A", "A"),
            ] {
                for (offset, _) in fixture.match_indices(prefix) {
                    let offset = offset + prefix.len();
                    let item = completion_at(
                        syms,
                        &session,
                        &baseline,
                        &Documents::new(),
                        ms_lsp::text::position(&fixture, offset),
                        snippets,
                    )
                    .unwrap()
                    .into_iter()
                    .map(|i| i.json())
                    .find(|i| i.get("label").and_then(|j| j.as_str()) == Some(name))
                    .unwrap_or_else(|| panic!("{prefix}"));
                    let edit = item.get("textEdit").unwrap();
                    assert_eq!(edit.get("newText").and_then(|j| j.as_str()), Some(name));
                    let range = Range::from_json(edit.get("range").unwrap()).unwrap();
                    let start = ms_lsp::text::offset(&fixture, range.start).unwrap();
                    let end = ms_lsp::text::offset(&fixture, range.end).unwrap();
                    let mut filled = baseline.clone();
                    filled.text.replace_range(start..end, name);
                    assert!(
                        analyze(syms, &session, &filled, &Documents::new())
                            .diagnostics
                            .is_empty()
                    );
                }
            }
            let source = fixture.replace("= Payload(1)", "= Pay");
            let offset = source.find("= Pay").unwrap() + "= Pay".len();
            let document = Document::new(workspace.uri("fields.ms"), source);
            let item = completion_at(
                syms,
                &session,
                &document,
                &Documents::new(),
                ms_lsp::text::position(&document.text, offset),
                snippets,
            )
            .unwrap()
            .into_iter()
            .map(|i| i.json())
            .find(|i| i.get("label").and_then(|j| j.as_str()) == Some("Payload"))
            .unwrap();
            assert_eq!(
                item.get("textEdit")
                    .unwrap()
                    .get("newText")
                    .and_then(|j| j.as_str()),
                Some(if snippets {
                    "Payload(${1:value})$0"
                } else {
                    "Payload"
                })
            );
        }
    }
}

#[test]
fn argument_label_edits_preserve_following_trivia_and_value() {
    let syms = ms_syntax::Names::global();
    let session = support::session();
    let workspace = Workspace::new("completion-label-trivia");
    for newline in ["\n", "\r\n"] {
        for trivia in [
            " ",
            "\n        ",
            " // note\n        ",
            "\n        /* note */\n        ",
        ] {
            let source = include_str!("completion/positional-values.ms")
                .replace(
                    "take(value: amount)",
                    &format!("take(value{trivia}: amount)"),
                )
                .replace('\n', newline);
            let mut document = Document::new(workspace.uri("labels.ms"), source);
            assert!(
                analyze(syms, &session, &document, &Documents::new())
                    .diagnostics
                    .is_empty()
            );
            for snippets in [false, true] {
                let offset = document
                    .text
                    .find(&format!("take(value{}", trivia.replace('\n', newline)))
                    .unwrap()
                    + "take(va".len();
                let item = completion_at(
                    syms,
                    &session,
                    &document,
                    &Documents::new(),
                    ms_lsp::text::position(&document.text, offset),
                    snippets,
                )
                .unwrap()
                .into_iter()
                .map(|i| i.json())
                .find(|i| i.get("label").and_then(|j| j.as_str()) == Some("value"))
                .unwrap();
                let edit = item.get("textEdit").unwrap();
                assert_eq!(edit.get("newText").and_then(|j| j.as_str()), Some("value"));
                let range = Range::from_json(edit.get("range").unwrap()).unwrap();
                let start = ms_lsp::text::offset(&document.text, range.start).unwrap();
                let end = ms_lsp::text::offset(&document.text, range.end).unwrap();
                assert_eq!(&document.text[start..end], "value");
                document.text.replace_range(start..end, "value");
                assert!(
                    analyze(syms, &session, &document, &Documents::new())
                        .diagnostics
                        .is_empty()
                );
            }
        }
    }
}

#[test]
fn completion_preserves_existing_call_and_type_arguments() {
    let syms = ms_syntax::Names::global();
    let session = support::session();
    let workspace = Workspace::new("completion-existing-arguments");
    std::fs::write(
        workspace.path("increment.ms"),
        include_str!("completion/auto-import.ms"),
    )
    .unwrap();
    for newline in ["\n", "\r\n"] {
        for snippets in [false, true] {
            for (fixture, prefix, name, expected_import) in [
                (
                    include_str!("completion/existing-arguments.ms"),
                    "value.tr",
                    "trim",
                    false,
                ),
                (
                    include_str!("completion/existing-arguments.ms"),
                    "return rece",
                    "receive",
                    false,
                ),
                (
                    include_str!("completion/auto-import-use.ms"),
                    "return inc",
                    "increment",
                    true,
                ),
                (
                    include_str!("completion/parameter-types.ms"),
                    "data: Pac",
                    "Packet",
                    false,
                ),
            ] {
                let source = fixture.replace('\n', newline);
                for (offset, _) in source.match_indices(prefix) {
                    let offset = offset + prefix.len();
                    let mut document = Document::new(workspace.uri("existing.ms"), source.clone());
                    let item = completion_at(
                        syms,
                        &session,
                        &document,
                        &Documents::new(),
                        ms_lsp::text::position(&document.text, offset),
                        snippets,
                    )
                    .unwrap()
                    .into_iter()
                    .map(|i| i.json())
                    .find(|i| i.get("label").and_then(|j| j.as_str()) == Some(name))
                    .unwrap();
                    assert_eq!(
                        item.get("insertTextFormat").and_then(|j| j.as_i64()),
                        Some(1)
                    );
                    let edit = item.get("textEdit").unwrap();
                    assert_eq!(edit.get("newText").and_then(|j| j.as_str()), Some(name));
                    let range = Range::from_json(edit.get("range").unwrap()).unwrap();
                    let start = ms_lsp::text::offset(&document.text, range.start).unwrap();
                    let end = ms_lsp::text::offset(&document.text, range.end).unwrap();
                    assert_eq!(&document.text[start..end], name);
                    document.text.replace_range(start..end, name);
                    if expected_import {
                        let edits = item.get("additionalTextEdits").unwrap().as_array().unwrap();
                        assert_eq!(edits.len(), 1);
                        let edit = &edits[0];
                        let range = Range::from_json(edit.get("range").unwrap()).unwrap();
                        assert_eq!(range, Range::at(Position::default()));
                        document
                            .text
                            .insert_str(0, edit.get("newText").and_then(|j| j.as_str()).unwrap());
                    }
                    let checked = analyze(syms, &session, &document, &Documents::new());
                    assert!(
                        checked.diagnostics.is_empty(),
                        "{prefix}: {:?}",
                        checked.diagnostics
                    );
                }
            }
        }
    }
}

#[test]
fn multiline_parameter_types_keep_type_snippets_and_variables() {
    let syms = ms_syntax::Names::global();
    let session = support::session();
    let workspace = Workspace::new("completion-parameter-types");
    for newline in ["\n", "\r\n"] {
        let fixture = include_str!("completion/parameter-types.ms").replace('\n', newline);
        let baseline = Document::new(workspace.uri("types.ms"), fixture.clone());
        assert!(
            analyze(syms, &session, &baseline, &Documents::new())
                .diagnostics
                .is_empty()
        );
        for snippets in [false, true] {
            for (original, partial) in [
                ("data: Packet[T]", "data: Pac"),
                (") Packet[Int]:", ") Pac:"),
            ] {
                let source = fixture.replace(original, partial);
                let prefix = partial.split("Pac").next().unwrap().to_string() + "Pac";
                let offset = source.find(&prefix).unwrap() + prefix.len();
                let mut document = Document::new(workspace.uri("types.ms"), source);
                let items: Vec<_> = completion_at(
                    syms,
                    &session,
                    &document,
                    &Documents::new(),
                    ms_lsp::text::position(&document.text, offset),
                    snippets,
                )
                .unwrap()
                .into_iter()
                .map(|i| i.json())
                .collect();
                let item = items
                    .iter()
                    .find(|i| i.get("label").and_then(|j| j.as_str()) == Some("Packet"))
                    .unwrap_or_else(|| panic!("{items:?}"));
                let edit = item.get("textEdit").unwrap();
                let insert = edit.get("newText").and_then(|j| j.as_str()).unwrap();
                assert_eq!(insert, if snippets { "Packet[${1:T}]" } else { "Packet" });
                let range = Range::from_json(edit.get("range").unwrap()).unwrap();
                let start = ms_lsp::text::offset(&document.text, range.start).unwrap();
                let end = ms_lsp::text::offset(&document.text, range.end).unwrap();
                document.text.replace_range(start..end, "Packet[Int]");
                assert!(
                    analyze(syms, &session, &document, &Documents::new())
                        .diagnostics
                        .is_empty()
                );
            }
            let offset = fixture.find("extra: T").unwrap() + "extra: ".len();
            let items: Vec<_> = completion_at(
                syms,
                &session,
                &baseline,
                &Documents::new(),
                ms_lsp::text::position(&fixture, offset),
                snippets,
            )
            .unwrap()
            .into_iter()
            .map(|i| i.json())
            .collect();
            assert!(
                items
                    .iter()
                    .any(|i| i.get("label").and_then(|j| j.as_str()) == Some("T")),
                "{items:?}"
            );
            let source = fixture.replace("= Packet(1)", "= Pac");
            let offset = source.find("= Pac").unwrap() + "= Pac".len();
            let document = Document::new(workspace.uri("types.ms"), source);
            let items: Vec<_> = completion_at(
                syms,
                &session,
                &document,
                &Documents::new(),
                ms_lsp::text::position(&document.text, offset),
                snippets,
            )
            .unwrap()
            .into_iter()
            .map(|i| i.json())
            .collect();
            let item = items
                .iter()
                .find(|i| i.get("label").and_then(|j| j.as_str()) == Some("Packet"))
                .unwrap();
            let insert = item
                .get("textEdit")
                .unwrap()
                .get("newText")
                .and_then(|j| j.as_str())
                .unwrap();
            assert_eq!(
                insert,
                if snippets {
                    "Packet[${1:T}](${2:value})$0"
                } else {
                    "Packet"
                }
            );
        }
    }
}

#[test]
fn positional_arguments_complete_values_and_keep_argument_labels() {
    let syms = ms_syntax::Names::global();
    let workspace = Workspace::new("completion-positional-values");
    for newline in ["\n", "\r\n"] {
        let fixture = include_str!("completion/positional-values.ms").replace('\n', newline);
        let document = Document::new(workspace.uri("values.ms"), fixture.clone());
        assert!(
            analyze(syms, &support::session(), &document, &Documents::new())
                .diagnostics
                .is_empty()
        );
        for snippets in [false, true] {
            for prefix in [
                "take(am",
                "take(1 + am",
                "take(1, am",
                "take(value: am",
                "Int: return am",
            ] {
                let offset = fixture.find(prefix).unwrap() + prefix.len();
                let items: Vec<_> = completion_at(
                    syms,
                    &support::session(),
                    &document,
                    &Documents::new(),
                    ms_lsp::text::position(&fixture, offset),
                    snippets,
                )
                .unwrap()
                .into_iter()
                .map(|i| i.json())
                .collect();
                let item = items
                    .iter()
                    .find(|i| i.get("label").and_then(|j| j.as_str()) == Some("amount"))
                    .unwrap_or_else(|| panic!("{prefix}: {items:?}"));
                let edit = item.get("textEdit").unwrap();
                assert_eq!(edit.get("newText").and_then(|j| j.as_str()), Some("amount"));
                let range = Range::from_json(edit.get("range").unwrap()).unwrap();
                let start = ms_lsp::text::offset(&fixture, range.start).unwrap();
                let end = ms_lsp::text::offset(&fixture, range.end).unwrap();
                assert_eq!(&fixture[start..end], "amount");
                let mut filled = document.clone();
                filled.text.replace_range(start..end, "amount");
                assert!(
                    analyze(syms, &support::session(), &filled, &Documents::new())
                        .diagnostics
                        .is_empty()
                );
            }
            let source = fixture.replace("take(amount)", "take(oth)");
            let offset = source.find("take(oth").unwrap() + "take(oth".len();
            let document = Document::new(workspace.uri("values.ms"), source.clone());
            let items: Vec<_> = completion_at(
                syms,
                &support::session(),
                &document,
                &Documents::new(),
                ms_lsp::text::position(&source, offset),
                snippets,
            )
            .unwrap()
            .into_iter()
            .map(|i| i.json())
            .collect();
            assert!(
                items
                    .iter()
                    .any(|i| i.get("label").and_then(|j| j.as_str()) == Some("other")),
                "{items:?}"
            );
            let offset = fixture.find("take(value)").unwrap() + "take(va".len();
            let document = Document::new(workspace.uri("values.ms"), fixture.clone());
            let items: Vec<_> = completion_at(
                syms,
                &support::session(),
                &document,
                &Documents::new(),
                ms_lsp::text::position(&fixture, offset),
                snippets,
            )
            .unwrap()
            .into_iter()
            .map(|i| i.json())
            .collect();
            assert!(
                items.iter().any(|i| i
                    .get("textEdit")
                    .unwrap()
                    .get("newText")
                    .and_then(|j| j.as_str())
                    == Some("value")),
                "{items:?}"
            );
            let label = items
                .iter()
                .find(|i| {
                    i.get("textEdit")
                        .unwrap()
                        .get("newText")
                        .and_then(|j| j.as_str())
                        .is_some_and(|text| text.starts_with("value: "))
                })
                .unwrap();
            assert_eq!(
                label
                    .get("labelDetails")
                    .unwrap()
                    .get("detail")
                    .and_then(|j| j.as_str()),
                Some(":")
            );
            let offset = fixture.find("take(value: amount)").unwrap() + "take(va".len();
            let items: Vec<_> = completion_at(
                syms,
                &support::session(),
                &document,
                &Documents::new(),
                ms_lsp::text::position(&fixture, offset),
                snippets,
            )
            .unwrap()
            .into_iter()
            .map(|i| i.json())
            .collect();
            let edit = items
                .iter()
                .find(|i| i.get("label").and_then(|j| j.as_str()) == Some("value"))
                .unwrap()
                .get("textEdit")
                .unwrap();
            assert_eq!(edit.get("newText").and_then(|j| j.as_str()), Some("value"));
            let range = Range::from_json(edit.get("range").unwrap()).unwrap();
            let start = ms_lsp::text::offset(&fixture, range.start).unwrap();
            let end = ms_lsp::text::offset(&fixture, range.end).unwrap();
            assert_eq!(&fixture[start..end], "value");
        }
    }
}
