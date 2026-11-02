//! Completion must not advertise an opaque record's private constructor fields.

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::{completion_at, signature_help};
use ms_lsp::nav::{self, Navigate};
use ms_lsp::text::{self, Range};
use ms_rt as _;

mod support;
use support::Workspace;

#[test]
fn opaque_constructor_snippets_respect_the_declaring_file() {
    let workspace = Workspace::new("opaque-constructor");
    let library = include_str!("opaque_completion/vault.ms");
    std::fs::write(workspace.path("vault.ms"), library).unwrap();
    let outside = include_str!("opaque_completion/outside.ms");
    for newline in ["\n", "\r\n"] {
        for (file, fixture) in [("vault.ms", library), ("outside.ms", outside)] {
            let fixture = fixture.replace('\n', newline);
            let checked = analyze(
                &Document::new(workspace.uri(file), fixture.clone()),
                &Documents::new(),
            );
            assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
            for snippets in [false, true] {
                let (call, prefix, expected) = if file == "vault.ms" {
                    (
                        "Vault[Int](7)",
                        "Va",
                        if snippets {
                            "Vault[${1:T}](${2:secret})$0"
                        } else {
                            "Vault"
                        },
                    )
                } else {
                    ("inspect(hidden)", "Va", "Vault")
                };
                let source = fixture.replace(call, prefix);
                let offset = source.find("return Va").unwrap() + "return Va".len();
                let mut document = Document::new(workspace.uri(file), source);
                let item = completion_at(
                    &document,
                    &Documents::new(),
                    text::position(&document.text, offset),
                    snippets,
                )
                .unwrap()
                .into_iter()
                .map(|item| item.json())
                .find(|item| item.get("label").and_then(|j| j.as_str()) == Some("Vault"))
                .expect("Vault");
                let edit = item.get("textEdit").unwrap();
                let insertion = edit.get("newText").and_then(|j| j.as_str()).unwrap();
                assert_eq!(insertion, expected, "{file}, snippets={snippets}");
                if file == "vault.ms" && snippets {
                    let range = Range::from_json(edit.get("range").unwrap()).unwrap();
                    let start = text::offset(&document.text, range.start).unwrap();
                    let end = text::offset(&document.text, range.end).unwrap();
                    document.text.replace_range(
                        start..end,
                        &insertion
                            .replace("${1:T}", "Int")
                            .replace("${2:secret}", "7")
                            .replace("$0", ""),
                    );
                    let checked = analyze(&document, &Documents::new());
                    assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
                }
            }
        }
    }
}

#[test]
fn ordinary_constructors_and_opaque_type_arguments_keep_their_snippets() {
    let workspace = Workspace::new("opaque-constructor-controls");
    std::fs::write(
        workspace.path("vault.ms"),
        include_str!("opaque_completion/vault.ms"),
    )
    .unwrap();
    let fixture = include_str!("opaque_completion/outside.ms");
    for newline in ["\n", "\r\n"] {
        let fixture = fixture.replace('\n', newline);
        for (original, prefix, label, expected) in [
            ("Open[Int](7)", "Op", "Open", "Open[${1:T}](${2:value})$0"),
            ("value: Vault[Int]", "value: Va", "Vault", "Vault[${1:T}]"),
        ] {
            let source = fixture.replace(original, prefix);
            let offset = source.rfind(prefix).unwrap() + prefix.len();
            let mut document = Document::new(workspace.uri("outside.ms"), source);
            let item = completion_at(
                &document,
                &Documents::new(),
                text::position(&document.text, offset),
                true,
            )
            .unwrap()
            .into_iter()
            .map(|item| item.json())
            .find(|item| item.get("label").and_then(|j| j.as_str()) == Some(label))
            .expect("type");
            let edit = item.get("textEdit").unwrap();
            let insertion = edit.get("newText").and_then(|j| j.as_str()).unwrap();
            assert_eq!(insertion, expected);
            let range = Range::from_json(edit.get("range").unwrap()).unwrap();
            let start = text::offset(&document.text, range.start).unwrap();
            let end = text::offset(&document.text, range.end).unwrap();
            document.text.replace_range(
                start..end,
                &insertion
                    .replace("${1:T}", "Int")
                    .replace("${2:value}", "7")
                    .replace("$0", ""),
            );
            let checked = analyze(&document, &Documents::new());
            assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
        }
        let forbidden = fixture.replace("inspect(hidden)", "Vault[Int](secret: 7)");
        let checked = analyze(
            &Document::new(workspace.uri("outside.ms"), forbidden),
            &Documents::new(),
        );
        assert!(
            checked
                .diagnostics
                .iter()
                .any(|d| d.message.contains("opaque")),
            "{:?}",
            checked.diagnostics
        );
    }
}

#[test]
fn opaque_constructor_argument_labels_and_signatures_stay_private() {
    let workspace = Workspace::new("opaque-constructor-help");
    let library = include_str!("opaque_completion/vault.ms");
    std::fs::write(workspace.path("vault.ms"), library).unwrap();
    let outside = include_str!("opaque_completion/outside.ms");
    for newline in ["\n", "\r\n"] {
        for (file, fixture, original) in [
            ("vault.ms", library, "Vault[Int](7)"),
            ("outside.ms", outside, "inspect(hidden)"),
        ] {
            for argument in ["", "sec"] {
                let call = format!("Vault[Int]({argument})");
                let source = fixture.replace(original, &call).replace('\n', newline);
                let prefix = format!("return Vault[Int]({argument}");
                let offset = source.find(&prefix).unwrap() + prefix.len();
                let document = Document::new(workspace.uri(file), source);
                for snippets in [false, true] {
                    let items = completion_at(
                        &document,
                        &Documents::new(),
                        text::position(&document.text, offset),
                        snippets,
                    )
                    .unwrap();
                    let labels: Vec<_> = items.into_iter().map(|item| item.json()).collect();
                    let secret = labels
                        .iter()
                        .find(|item| item.get("label").and_then(|j| j.as_str()) == Some("secret"));
                    assert_eq!(secret.is_some(), file == "vault.ms", "{file}: {labels:?}");
                }
                let help = signature_help(
                    &document,
                    &Documents::new(),
                    text::position(&document.text, offset),
                )
                .unwrap();
                if file == "outside.ms" {
                    assert!(help.is_null(), "{help:?}");
                } else {
                    let signature = &help.get("signatures").and_then(|j| j.as_array()).unwrap()[0];
                    assert_eq!(
                        signature.get("label").and_then(|j| j.as_str()),
                        Some("Vault[Int](secret: Int) Vault[Int]")
                    );
                }
            }
        }
    }
}

#[test]
fn opaque_alternative_argument_labels_and_signatures_stay_private() {
    let workspace = Workspace::new("opaque-case-help");
    let library = include_str!("opaque_completion/vault.ms");
    std::fs::write(workspace.path("vault.ms"), library).unwrap();
    let outside = include_str!("opaque_completion/outside.ms");
    for newline in ["\n", "\r\n"] {
        for (file, fixture, original) in [
            ("vault.ms", library, "Choice.Payload(7)"),
            ("outside.ms", outside, "inspect(hidden)"),
        ] {
            let source = fixture
                .replace(original, "Choice.Payload(va)")
                .replace('\n', newline);
            let prefix = "return Choice.Payload(va";
            let offset = source.find(prefix).unwrap() + prefix.len();
            let document = Document::new(workspace.uri(file), source);
            let items = completion_at(
                &document,
                &Documents::new(),
                text::position(&document.text, offset),
                true,
            )
            .unwrap();
            let labels: Vec<_> = items.into_iter().map(|item| item.json()).collect();
            let value = labels
                .iter()
                .find(|item| item.get("label").and_then(|j| j.as_str()) == Some("value"));
            assert_eq!(value.is_some(), file == "vault.ms", "{file}: {labels:?}");
            let help = signature_help(
                &document,
                &Documents::new(),
                text::position(&document.text, offset),
            )
            .unwrap();
            assert_eq!(help.is_null(), file == "outside.ms", "{help:?}");
        }
    }
}

#[test]
fn opaque_representation_hover_and_navigation_stay_private() {
    let workspace = Workspace::new("opaque-hover");
    let library = include_str!("opaque_completion/vault.ms");
    std::fs::write(workspace.path("vault.ms"), library).unwrap();
    let fixture = include_str!("opaque_completion/outside.ms");
    for newline in ["\n", "\r\n"] {
        for (expression, selected) in [
            ("Vault[Int](secret: 7)", "secret"),
            ("hidden.secret", "secret"),
            ("hidden.secret.abs()", "abs"),
            ("(hidden.secret).abs()", "abs"),
            ("Vault[Int](secret: 7).secret.abs()", "abs"),
            ("Choice.Payload(7)", "Payload"),
        ] {
            let source = fixture
                .replace("inspect(hidden)", expression)
                .replace('\n', newline);
            let offset = source.find(expression).unwrap() + expression.find(selected).unwrap();
            let document = Document::new(workspace.uri("outside.ms"), source);
            let checked = analyze(&document, &Documents::new());
            assert!(
                checked
                    .diagnostics
                    .iter()
                    .any(|d| d.message.contains("opaque")),
                "{:?}",
                checked.diagnostics
            );
            let index = checked.index();
            let at = text::position(&document.text, offset);
            assert!(nav::occurrence_at(&checked, &document, at, index).is_none());
            for index in [index, &[][..]] {
                assert!(
                    nav::navigation(&checked, &document, at, Navigate::Hover, index).is_null(),
                    "{expression}"
                );
                assert!(
                    nav::navigation(&checked, &document, at, Navigate::Definition, index).is_null(),
                    "{expression}"
                );
            }
        }
        let document = Document::new(workspace.uri("vault.ms"), library.replace('\n', newline));
        let checked = analyze(&document, &Documents::new());
        let index = checked.index();
        let offset = document.text.find("secret").unwrap();
        let hover = nav::navigation(
            &checked,
            &document,
            text::position(&document.text, offset),
            Navigate::Hover,
            index,
        );
        assert!(!hover.is_null());
        let document = Document::new(workspace.uri("outside.ms"), fixture.replace('\n', newline));
        let checked = analyze(&document, &Documents::new());
        for token in ["Vault", "public.value", "hidden.size"] {
            let offset = if token == "Vault" {
                document.text.find("value: Vault").unwrap() + "value: ".len()
            } else {
                document.text.find(token).unwrap() + token.find('.').unwrap() + 1
            };
            let hover = nav::navigation(
                &checked,
                &document,
                text::position(&document.text, offset),
                Navigate::Hover,
                checked.index(),
            );
            assert!(!hover.is_null(), "{token}");
        }
    }
}

#[test]
fn opaque_public_methods_remain_discoverable() {
    let workspace = Workspace::new("opaque-public-method");
    std::fs::write(
        workspace.path("vault.ms"),
        include_str!("opaque_completion/vault.ms"),
    )
    .unwrap();
    let fixture = include_str!("opaque_completion/outside.ms");
    for newline in ["\n", "\r\n"] {
        let source = fixture
            .replace("hidden.size()", "hidden.si")
            .replace('\n', newline);
        let offset = source.find("hidden.si").unwrap() + "hidden.si".len();
        let mut document = Document::new(workspace.uri("outside.ms"), source);
        let items: Vec<_> = completion_at(
            &document,
            &Documents::new(),
            text::position(&document.text, offset),
            true,
        )
        .unwrap()
        .into_iter()
        .map(|item| item.json())
        .collect();
        assert!(
            !items
                .iter()
                .any(|item| item.get("label").and_then(|j| j.as_str()) == Some("secret"))
        );
        let method = items
            .iter()
            .find(|item| item.get("label").and_then(|j| j.as_str()) == Some("size"))
            .unwrap();
        let edit = method.get("textEdit").unwrap();
        assert_eq!(
            edit.get("newText").and_then(|j| j.as_str()),
            Some("size()$0")
        );
        let range = Range::from_json(edit.get("range").unwrap()).unwrap();
        let start = text::offset(&document.text, range.start).unwrap();
        let end = text::offset(&document.text, range.end).unwrap();
        document.text.replace_range(start..end, "size()");
        let checked = analyze(&document, &Documents::new());
        assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
        let offset = document.text.find("hidden.size(").unwrap() + "hidden.size(".len();
        let help = signature_help(
            &document,
            &Documents::new(),
            text::position(&document.text, offset),
        )
        .unwrap();
        assert!(!help.is_null());
    }
}

#[test]
fn opaque_rejected_receiver_chains_offer_no_members_or_calls() {
    let workspace = Workspace::new("opaque-chains");
    std::fs::write(
        workspace.path("vault.ms"),
        include_str!("opaque_completion/vault.ms"),
    )
    .unwrap();
    let fixture = include_str!("opaque_completion/outside.ms");
    for newline in ["\n", "\r\n"] {
        for (receiver, hidden) in [
            ("hidden.secret", true),
            ("(hidden.secret)", true),
            ("Vault[Int](secret: 7).secret", true),
            ("hidden.size()", false),
            ("public.value", false),
        ] {
            let prefix = format!("{receiver}.ab");
            let source = fixture
                .replace("inspect(hidden)", &prefix)
                .replace('\n', newline);
            let offset = source.find(&prefix).unwrap() + prefix.len();
            let document = Document::new(workspace.uri("outside.ms"), source);
            for snippets in [false, true] {
                let items = completion_at(
                    &document,
                    &Documents::new(),
                    text::position(&document.text, offset),
                    snippets,
                )
                .unwrap();
                let found = items
                    .into_iter()
                    .map(|item| item.json())
                    .any(|item| item.get("label").and_then(|j| j.as_str()) == Some("abs"));
                assert_eq!(found, !hidden, "{receiver}");
            }
            let call = format!("{receiver}.abs()");
            let source = fixture
                .replace("inspect(hidden)", &call)
                .replace('\n', newline);
            let offset = source.find(&call).unwrap() + call.len() - 1;
            let document = Document::new(workspace.uri("outside.ms"), source);
            let help = signature_help(
                &document,
                &Documents::new(),
                text::position(&document.text, offset),
            )
            .unwrap();
            assert_eq!(help.is_null(), hidden, "{receiver}: {help:?}");
        }
    }
}
