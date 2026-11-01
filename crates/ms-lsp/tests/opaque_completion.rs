//! Completion must not advertise an opaque record's private constructor fields.

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::completion_at;
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
