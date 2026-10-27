//! Source inserted by completion must remain valid Manuscript.

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::completion_at;
use ms_lsp::text::{Position, Range};
use ms_rt as _;
use std::path::Path;

mod support;
use support::Workspace;

#[test]
fn with_snippet_inserts_a_checked_resource_binding() {
    let workspace = Workspace::new("completion-snippet");
    let source = include_str!("completion/with-snippet-inserts-a-checked-resource-binding.ms");
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        let mut document = Document::new(workspace.uri("completion.ms"), source);
        assert!(Path::new(&document.path()).is_absolute());
        assert!(!Path::new(&document.path()).exists(), "unsaved document");
        let at = Position {
            line: 9,
            character: 6,
        };
        let item = completion_at(&document, &Documents::new(), at, true)
            .expect("completion")
            .into_iter()
            .map(|item| item.json())
            .find(|item| item.get("label").and_then(|j| j.as_str()) == Some("with"))
            .expect("with snippet");
        assert_eq!(
            item.get("insertTextFormat").and_then(|j| j.as_i64()),
            Some(2)
        );
        let edit = item.get("textEdit").expect("text edit");
        let range = Range::from_json(edit.get("range").expect("range")).expect("valid range");
        let start = ms_lsp::text::offset(&document.text, range.start).expect("start");
        let end = ms_lsp::text::offset(&document.text, range.end).expect("end");
        assert_eq!(&document.text[start..end], "wi");
        // Fill by placeholder name even if the tab order changes.
        let insertion = edit
            .get("newText")
            .and_then(|j| j.as_str())
            .expect("snippet")
            .replace("${1:resource}", "resource")
            .replace("${2:initializer}", "Resource(1)")
            .replace("${1:initializer}", "Resource(1)")
            .replace("${2:resource}", "resource")
            .replace("$0", "return ()")
            .replace('\n', "\n    ");
        document.text.replace_range(start..end, &insertion);
        let checked = analyze(&document, &Documents::new());
        assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
        assert!(checked.program.is_some(), "inserted source must check");
        assert_eq!(Path::new(&checked.source_root), workspace.root.as_path());
    }
}

#[test]
fn a_native_document_uri_checks_unsaved_text_instead_of_disk() {
    let workspace = Workspace::new("completion-overlay");
    let name = "edited é #%.ms";
    let path = workspace.path(name);
    let stale = "not valid Manuscript\n";
    std::fs::write(&path, stale).expect("disk source");
    let source = "def value() -> Int:\n    return 7\n";
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        let document = Document::new(workspace.uri(name), source);
        assert!(Path::new(&document.path()).is_absolute());
        assert_eq!(std::fs::read_to_string(document.path()).unwrap(), stale);
        let checked = analyze(&document, &Documents::new());
        assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
        assert!(checked.program.is_some(), "unsaved source must check");
        assert_eq!(Path::new(&checked.source_root), workspace.root.as_path());
        let module = checked.module(&document).expect("checked document");
        assert_eq!(&*module.source, document.text.as_str());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), stale);
    }
}
