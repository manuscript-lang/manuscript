//! Workspace scan failures retain the same reference order as successful scans.

mod support;

use ms_lsp::analysis::{Document, Documents, Options, compile_source};
use ms_lsp::json::Json;
use ms_lsp::text::Position;
use ms_lsp::workspace::{ScanError, workspace_documents, workspace_references};
use support::Workspace;

fn starts(locations: &[Json]) -> Vec<(i64, i64)> {
    locations
        .iter()
        .map(|location| {
            let start = location.get("range").unwrap().get("start").unwrap();
            (
                start.get("line").unwrap().as_i64().unwrap(),
                start.get("character").unwrap().as_i64().unwrap(),
            )
        })
        .collect()
}

#[test]
fn scan_error_preserves_exported_reference_order_and_declaration_filter() {
    let ws = Workspace::new("reference-order");
    // NUL is rejected before directory enumeration on every host, rather than relying on
    // platform-specific error codes for a missing or non-directory parent.
    let parent = ws.root.join("invalid\0directory");
    let path = parent.join("main.ms");
    let source = include_str!("reference_order/exported.ms");
    let d = Document::new(ms_lsp::uri::file_uri(path.to_str().unwrap()), source);
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let analysis = compile_source(&d.path(), source, &Options::default());
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    assert!(matches!(
        workspace_documents(&d, &docs, false, None),
        Err(ScanError::Io(_))
    ));
    let at = Position {
        line: 0,
        character: 10,
    };
    for (include, expected) in [
        (true, vec![(0, 10), (10, 24), (2, 23)]),
        (false, vec![(10, 24), (2, 23)]),
    ] {
        let locations =
            workspace_references(&analysis, analysis.index(), &d, &docs, at, include, None);
        assert_eq!(starts(&locations), expected);
        assert!(locations.iter().all(|location| {
            location.get("uri").and_then(Json::as_str) == Some(d.uri.as_str())
        }));
    }
}

#[test]
fn local_binding_references_keep_source_order() {
    let ws = Workspace::new("binding-reference-order");
    let source = include_str!("reference_order/binding.ms");
    let d = Document::new(ws.uri("main.ms"), source);
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let analysis = compile_source(&d.path(), source, &Options::default());
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    let at = Position {
        line: 1,
        character: 8,
    };
    for (include, expected) in [
        (true, vec![(1, 8), (2, 16), (10, 19)]),
        (false, vec![(2, 16), (10, 19)]),
    ] {
        let locations =
            workspace_references(&analysis, analysis.index(), &d, &docs, at, include, None);
        assert_eq!(starts(&locations), expected);
    }
}
