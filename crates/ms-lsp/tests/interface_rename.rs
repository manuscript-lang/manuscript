//! A type satisfies an interface by shape, so renaming an operation renames the interface and
//! every method that meets it, and leaves a same-named method with another signature alone.

use ms_lsp::analysis::{Document, Options, compile_source};
use ms_lsp::rename::rename;
use ms_lsp::text;

use crate::support::Workspace;

const SOURCE: &str = include_str!("interface_rename/shapes.ms");

fn rename_at(marker: &str, nth: usize) -> String {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("interface-rename");
    let d = Document::new(ws.uri("main.ms"), SOURCE);
    let analysis = compile_source(syms, &d.path(), SOURCE, &Options::default());
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    let offset = SOURCE.match_indices(marker).nth(nth).unwrap().0 + marker.len() - 4;
    let edit = rename(
        syms,
        &analysis,
        analysis.occurrence_index(syms),
        &d,
        text::position(SOURCE, offset),
        "size",
        None,
        None,
    )
    .expect("rename");
    edit.compact(ms_json::Escape::Plain)
}

#[test]
fn renaming_from_either_side_changes_both_and_the_call() {
    for (marker, nth) in [("fn area()", 0), ("Square.area", 0)] {
        let edits = rename_at(marker, nth);
        assert_eq!(edits.matches("\"newText\":\"size\"").count(), 3, "{edits}");
    }
}

#[test]
fn a_method_with_another_signature_is_not_the_operation() {
    let edits = rename_at("Ring.area", 0);
    assert_eq!(edits.matches("\"newText\":\"size\"").count(), 2, "{edits}");
}

#[test]
fn definition_on_an_import_path_opens_the_module() {
    use ms_lsp::analysis::{Documents, analyze};
    use ms_lsp::nav::{self, Navigate};
    let syms = ms_syntax::Names::global();
    let session = crate::support::session();
    let ws = Workspace::new("import-path-definition");
    std::fs::create_dir(ws.path("imp")).unwrap();
    std::fs::write(
        ws.path("imp/util.ms"),
        "export fn twice(x: Int) Int:\n\treturn x * 2\n",
    )
    .unwrap();
    let main = "import twice from \"./util.ms\"\n\nfn main() Void:\n\tprint(twice(2))\n";
    std::fs::write(ws.path("imp/main.ms"), main).unwrap();
    let d = Document::new(ws.uri("imp/main.ms"), main);
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let checked = analyze(syms, &session, &d, &docs);
    assert!(checked.success(), "{:?}", checked.diagnostics);
    let inside = text::position(main, main.find("util").unwrap());
    let found = nav::navigation(
        syms,
        &checked,
        &d,
        inside,
        Navigate::Definition,
        checked.occurrence_index(syms),
    )
    .compact(ms_json::Escape::Plain);
    assert!(found.contains("util.ms"), "{found}");
    let outside = text::position(main, main.find("fn main").unwrap());
    let none = nav::navigation(
        syms,
        &checked,
        &d,
        outside,
        Navigate::Definition,
        checked.occurrence_index(syms),
    );
    assert!(!none.compact(ms_json::Escape::Plain).contains("util.ms"));
}
