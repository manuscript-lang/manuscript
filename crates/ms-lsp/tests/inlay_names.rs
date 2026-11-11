//! An analysis keeps the meaning of its names while another workspace is current.

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::features::inlay_hints;
use ms_lsp::json::Json;
use ms_lsp::text::{Position, Range};
use ms_rt as _;

use crate::support;
use support::Workspace;

#[test]
fn inlay_hints_keep_the_supplied_name_table() {
    let workspace = Workspace::new("inlay-names");
    let names = ms_syntax::Session::new();
    let entered = names.enter();
    let document = Document::new(
        workspace.uri("inlay.ms"),
        include_str!("inlay_names/source.ms"),
    );
    let analysis = analyze(
        names.names(),
        &support::session(),
        &document,
        &Documents::new(),
    );
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    let range = Range {
        start: Position::default(),
        end: Position {
            line: 3,
            character: 0,
        },
    };
    let expected = inlay_hints(names.names(), &analysis, &document, range);
    assert_eq!(expected.as_array().expect("hints").len(), 1);
    let hint = &expected.as_array().expect("hints")[0];
    assert_eq!(hint.get("label").and_then(Json::as_str), Some(": Int"));
    assert_eq!(
        hint.get("position")
            .and_then(|p| p.get("character"))
            .and_then(Json::as_i64),
        Some(10)
    );
    drop(entered);

    let other = ms_syntax::Session::new();
    let _other_entered = other.enter();
    // Make every index in the other workspace valid but give it unrelated text.
    for i in 0..5_000 {
        other.names().intern(&format!("foreign_{i}"));
    }
    let actual = inlay_hints(names.names(), &analysis, &document, range);
    assert_eq!(support::canonical(&actual), support::canonical(&expected));
}
