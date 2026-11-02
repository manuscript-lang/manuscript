//! Cases in match arms participate in the same identity as constructors.

mod support;

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::json::Json;
use ms_lsp::nav::{self, Navigate};
use ms_lsp::text;
use support::Workspace;

#[test]
fn case_references_and_rename_include_bare_and_qualified_match_arms() {
    let fixture = include_str!("match_cases/source.ms");
    for newline in ["\n", "\r\n"] {
        let ws = Workspace::new("match-case-navigation");
        let source = fixture.replace('\n', newline);
        let d = Document::new(ws.uri("cases.ms"), &source);
        let docs = Documents::from([(d.uri.clone(), d.clone())]);
        let checked = analyze(&d, &docs);
        assert!(checked.success(), "{:?}", checked.diagnostics);
        let declaration = source.find("Value").unwrap();
        let at = text::position(&source, declaration);
        let references = nav::references_with_index(&checked, checked.index(), &d, at, true);
        let starts: Vec<usize> = references
            .iter()
            .map(|location| {
                let range = text::Range::from_json(location.get("range").unwrap()).unwrap();
                text::offset(&source, range.start).unwrap()
            })
            .collect();
        let expected: Vec<usize> = source
            .match_indices("Value")
            .map(|(at, _)| at)
            .enumerate()
            .filter_map(|(index, at)| [0, 2, 3, 5].contains(&index).then_some(at))
            .collect();
        assert_eq!(starts, expected);
        for &offset in &starts {
            let position = text::position(&source, offset);
            let definition = nav::navigation(
                &checked,
                &d,
                position,
                Navigate::Definition,
                checked.index(),
            );
            let found = &definition.as_array().unwrap()[0];
            let range = text::Range::from_json(found.get("range").unwrap()).unwrap();
            assert_eq!(text::offset(&source, range.start), Ok(declaration));
        }
        let renamed = ms_lsp::rename::rename(
            &checked,
            checked.index(),
            &d,
            at,
            "Renamed",
            None,
            Some(&docs),
        )
        .unwrap();
        let changes = renamed.get("documentChanges").unwrap().as_array().unwrap();
        assert_eq!(changes.len(), 1);
        let edits = changes[0].get("edits").unwrap().as_array().unwrap();
        assert_eq!(edits.len(), expected.len());
        let mut updated = source.clone();
        for edit in edits {
            let range = text::Range::from_json(edit.get("range").unwrap()).unwrap();
            let start = text::offset(&source, range.start).unwrap();
            let end = text::offset(&source, range.end).unwrap();
            let name = edit.get("newText").and_then(Json::as_str).unwrap();
            updated.replace_range(start..end, name);
        }
        let d = Document::new(d.uri, updated);
        assert!(analyze(&d, &Documents::new()).success());
    }
}

#[test]
fn invalid_match_paths_do_not_acquire_a_case_identity() {
    let fixture = include_str!("match_cases/source.ms");
    for (from, to, selected) in [
        ("Value(n):", "Missing(n):", "Missing"),
        ("Choice[Int].Value(n):", "Other.Value(n):", "Other.Value"),
        ("Value(n):", "_:", "_"),
    ] {
        let ws = Workspace::new("invalid-case-navigation");
        let offset = fixture.find(from).unwrap();
        let source = fixture.replacen(from, to, 1);
        let d = Document::new(ws.uri("invalid.ms"), &source);
        let checked = analyze(&d, &Documents::new());
        assert!(!checked.success());
        // Select the case component, preserving navigation of a valid qualifier.
        let offset = offset + selected.rfind('.').map_or(0, |at| at + 1);
        let found = nav::occurrence_at(
            &checked,
            &d,
            text::position(&source, offset),
            checked.index(),
        );
        assert!(found.is_none(), "{to}: unexpectedly resolved match path");
    }
}

#[test]
fn synthesized_paths_and_type_suffixes_do_not_become_written_occurrences() {
    let ws = Workspace::new("case-navigation-controls");
    let source = include_str!("match_cases/controls.ms");
    let d = Document::new(ws.uri("controls.ms"), source);
    let checked = analyze(&d, &Documents::new());
    assert!(checked.success(), "{:?}", checked.diagnostics);
    let file = checked.module_file(&d);
    for entry in checked
        .index()
        .iter()
        .filter(|entry| entry.file.as_str() == file)
    {
        assert_eq!(
            source.get(entry.offset..entry.end),
            Some(entry.name.as_str())
        );
        assert!(
            source
                .as_bytes()
                .get(entry.end)
                .is_none_or(|byte| !text::identifier(*byte))
        );
    }
    for (name, kind) in [
        ("value: return", "binding:"),
        ("input?.value", "parameter:"),
    ] {
        let offset = source.find(name).unwrap();
        let entry = nav::occurrence_at(
            &checked,
            &d,
            text::position(source, offset),
            checked.index(),
        )
        .unwrap();
        assert!(entry.key.starts_with(kind));
    }
}
