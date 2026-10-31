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
        (true, vec![(0, 10), (2, 23), (10, 24)]),
        (false, vec![(2, 23), (10, 24)]),
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

#[test]
fn batched_reference_ranges_match_individual_locations() {
    let ws = Workspace::new("batched-reference-ranges");
    let fixture = include_str!("reference_order/batched.ms");
    for source in [fixture.to_string(), fixture.replace('\n', "\r\n")] {
        let d = Document::new(ws.uri("batched.ms"), &source);
        let analysis = compile_source(&d.path(), &source, &Options::default());
        assert!(analysis.success(), "{:?}", analysis.diagnostics);
        let offsets: Vec<_> = source.match_indices("value").map(|(at, _)| at).collect();
        let at = ms_lsp::text::position(&source, offsets[0]);
        let mut index = analysis.index().to_vec();
        for reverse in [false, true] {
            if reverse {
                index.reverse();
            }
            for include in [false, true] {
                let selected = ms_lsp::nav::occurrence_at(&analysis, &d, at, &index).unwrap();
                let expected: Vec<_> = index
                    .iter()
                    .filter(|entry| entry.key == selected.key && (include || !entry.declaration))
                    .filter_map(|entry| ms_lsp::nav::occurrence_location(&analysis, entry))
                    .collect();
                let actual = ms_lsp::nav::references_with_index(&analysis, &index, &d, at, include);
                assert_eq!(actual, expected);
                assert_eq!(actual.len(), offsets.len() - usize::from(!include));
            }
        }
        // The location renderer also accepts index slices in a caller's order.
        // Interleave files and an absent module to exercise every batch boundary.
        let selected = ms_lsp::nav::occurrence_at(&analysis, &d, at, analysis.index()).unwrap();
        let mut standard = selected.clone();
        standard.file = ms_check::types::n("@std/intrinsics.ms");
        standard.offset = 0;
        standard.end = 1;
        standard.declaration = false;
        let mut missing = standard.clone();
        missing.file = ms_check::types::n("absent.ms");
        let mut clipped = selected.clone();
        clipped.offset = source.len() + 10;
        clipped.end = source.len() + 20;
        clipped.declaration = false;
        let entries = vec![
            selected.clone(),
            standard.clone(),
            clipped,
            missing,
            standard,
        ];
        for include in [false, true] {
            let expected: Vec<_> = entries
                .iter()
                .filter(|entry| include || !entry.declaration)
                .filter_map(|entry| ms_lsp::nav::occurrence_location(&analysis, entry))
                .collect();
            let actual = ms_lsp::nav::references_with_index(&analysis, &entries, &d, at, include);
            assert_eq!(actual, expected);
            assert_eq!(actual.len(), 4 - usize::from(!include));
        }
    }
}
