//! Project export hints recognize every exported declaration spelling.

mod common;

use common::*;
use ms_driver::imports::{exported_names, suggest_project_imports};
use ms_syntax::{Diagnostic, Phase, Pos};

#[test]
fn export_hints_include_opaque_types_and_grouped_constants() {
    assert_eq!(
        exported_names(include_str!("export_names/declarations.ms")),
        [
            "Plain", "Opaque", "LOW", "HIGH", "read", "Measure", "native"
        ]
    );
}

#[test]
fn incomplete_neighbors_do_not_hide_valid_exports() {
    assert_eq!(
        exported_names(include_str!("export_names/recovery.ms")),
        ["Recovered", "AFTER"]
    );
}

#[test]
fn grouped_export_hints_skip_nested_initializer_names() {
    let source = include_str!("export_names/nested_groups.ms");
    let file = "nested_groups.ms".into();
    ms_syntax::parser::parse(&file, source).expect("valid grouped constants");
    assert_eq!(
        exported_names(source),
        ["LOW", "HIGH", "FLAGS", "ITEMS", "LAST"]
    );
    assert_eq!(
        exported_names(&source.replace('\n', "\r\n")),
        ["LOW", "HIGH", "FLAGS", "ITEMS", "LAST"]
    );
}

#[test]
fn missing_opaque_types_and_grouped_constants_get_import_fixes() {
    let dir = TempDir::new();
    let main = write(dir.path(), "main.ms", "");
    write(
        dir.path(),
        "declarations.ms",
        include_str!("export_names/declarations.ms"),
    );
    for (kind, name) in [("type", "Opaque"), ("binding", "LOW"), ("binding", "HIGH")] {
        let mut issues = vec![Diagnostic {
            file: main.as_str().into(),
            pos: Pos::new(0, 1, 1),
            phase: Phase::Resolution,
            message: format!("unknown {kind} {name}; declare or import it"),
            end: None,
            fix: None,
        }];
        suggest_project_imports(&mut issues, dir.path());
        let statement = format!("import {name} from \"./declarations.ms\"");
        assert_eq!(
            issues[0].message,
            format!("unknown {kind} {name}; add: {statement}")
        );
        assert_eq!(
            issues[0].fix.as_ref().expect("import fix").replacement,
            format!("{statement}\n")
        );
    }
}
