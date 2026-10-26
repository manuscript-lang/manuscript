//! Source inserted by completion must remain valid Manuscript.

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::completion_at;
use ms_lsp::text::{Position, Range};
use ms_rt as _;

#[test]
fn with_snippet_inserts_a_checked_resource_binding() {
    let source = "from \"@std/core.ms\" import Closeable\n\ntype Resource:\n    value: Int\n\nimpl Closeable for Resource:\n    var def close() -> Unit: return ()\n\ndef main() -> Unit:\n    wi\n";
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        let mut document = Document::new("file:///completion.ms", source);
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
    }
}
