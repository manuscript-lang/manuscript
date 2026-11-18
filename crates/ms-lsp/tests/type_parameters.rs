//! A type parameter navigates like a local: its declaration, every use inside its scope, and
//! the receiver arguments of methods (merged into one block, so only the first keeps a receiver).

use crate::support;

use ms_lsp::analysis::{Document, Documents, Options, compile_source};
use ms_lsp::nav::{self, Navigate};
use ms_lsp::rename::rename;
use ms_lsp::text::{self, Position};
use ms_lsp::workspace::workspace_references;
use support::Workspace;

const SOURCE: &str = include_str!("type_parameters/generic.ms");

/// The position of the `nth` whole-word `name` on the first line that contains `line`.
fn at(line: &str, name: &str, nth: usize) -> Position {
    let start = SOURCE.find(line).expect("line");
    let offset = SOURCE[start..]
        .match_indices(name)
        .filter(|(i, _)| {
            let before = SOURCE[..start + i].chars().next_back();
            let after = SOURCE[start + i + name.len()..].chars().next();
            !before.is_some_and(char::is_alphanumeric) && !after.is_some_and(char::is_alphanumeric)
        })
        .nth(nth)
        .expect("name")
        .0;
    text::position(SOURCE, start + offset)
}

fn lines(locations: &[ms_lsp::json::Json]) -> Vec<(i64, i64)> {
    let mut found: Vec<_> = locations
        .iter()
        .map(|l| {
            let start = l.get("range").unwrap().get("start").unwrap();
            (
                start.get("line").unwrap().as_i64().unwrap(),
                start.get("character").unwrap().as_i64().unwrap(),
            )
        })
        .collect();
    found.sort();
    found
}

#[test]
fn parameters_are_scoped_to_their_declaration() {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("type-parameters");
    let d = Document::new(ws.uri("main.ms"), SOURCE);
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let analysis = compile_source(syms, &d.path(), SOURCE, &Options::default());
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    let references = |p: Position| {
        lines(&workspace_references(
            syms,
            &analysis,
            analysis.occurrence_index(syms),
            &d,
            &docs,
            p,
            true,
            None,
        ))
    };
    // `T` of `first` and `T` of `second` share a name and nothing else.
    assert_eq!(
        references(at("fn first", "T", 0)),
        [(10, 9), (10, 24), (10, 28)]
    );
    assert_eq!(
        references(at("fn second", "T", 1)),
        [(13, 10), (13, 25), (13, 29)]
    );
    // The type's `T`, every method receiver that names it, and the uses in their bodies.
    let from_type = references(at("type Box", "T", 0));
    assert_eq!(from_type, references(at("fn Box[T: Clonable].map", "T", 0)));
    assert_eq!(
        from_type,
        [(0, 9), (1, 8), (3, 7), (3, 26), (6, 7), (6, 48)]
    );
    // A method's own parameter stays inside the method.
    assert_eq!(
        references(at("map[B", "B", 0)),
        [(6, 24), (6, 51), (6, 59), (7, 11)]
    );
}

#[test]
fn parameters_hover_and_navigate_to_their_declaration() {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("type-parameter-hover");
    let d = Document::new(ws.uri("main.ms"), SOURCE);
    let analysis = compile_source(syms, &d.path(), SOURCE, &Options::default());
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    let navigate = |p: Position, how: Navigate| {
        nav::navigation(syms, &analysis, &d, p, how, analysis.occurrence_index(syms))
            .compact(ms_json::Escape::Plain)
    };
    let use_site = at("fn first", "T", 1);
    let hover = navigate(use_site, Navigate::Hover);
    assert!(hover.contains("type parameter T"), "{hover}");
    let declaration = navigate(use_site, Navigate::Definition);
    assert!(declaration.contains("\"line\":10"), "{declaration}");
    assert!(declaration.contains("\"character\":9"), "{declaration}");
    let bounded = navigate(at("type Box", "T", 0), Navigate::Hover);
    assert!(bounded.contains("type parameter T: Clonable"), "{bounded}");
}

#[test]
fn renaming_a_type_parameter_renames_its_receiver_methods() {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("type-parameter-rename");
    let d = Document::new(ws.uri("main.ms"), SOURCE);
    let analysis = compile_source(syms, &d.path(), SOURCE, &Options::default());
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    let edit = rename(
        syms,
        &analysis,
        analysis.occurrence_index(syms),
        &d,
        at("type Box", "T", 0),
        "Item",
        None,
        None,
    )
    .expect("rename");
    let edits = edit.compact(ms_json::Escape::Plain);
    // Six sites: the declaration, its field, both receivers, and the uses in the signatures.
    assert_eq!(edits.matches("\"newText\":\"Item\"").count(), 6, "{edits}");
    // A name that the program already declares is refused, not silently captured.
    let clash = rename(
        syms,
        &analysis,
        analysis.occurrence_index(syms),
        &d,
        at("fn first", "T", 0),
        "B",
        None,
        None,
    );
    assert!(clash.is_err(), "{clash:?}");
}

#[test]
fn the_entry_function_cannot_be_renamed() {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("rename-main");
    let d = Document::new(ws.uri("main.ms"), SOURCE);
    let analysis = compile_source(syms, &d.path(), SOURCE, &Options::default());
    let refused = rename(
        syms,
        &analysis,
        analysis.occurrence_index(syms),
        &d,
        at("fn main", "main", 0),
        "start",
        None,
        None,
    );
    assert!(refused.is_err_and(|e| e.contains("entry point")));
}
