//! Project export hints recognize every exported declaration spelling.

use crate::common;

use common::*;
use ms_driver::imports::{exported_declarations, exported_names, suggest_project_imports};
use ms_syntax::{Diagnostic, Phase, Pos};

#[test]
fn export_hints_include_enums_opaque_types_and_grouped_constants() {
    let syms = ms_syntax::Names::global();
    ms_syntax::parser::parse(
        &"declarations.ms".into(),
        include_str!("export_names/declarations.ms"),
    )
    .expect("valid exported declarations");
    assert_eq!(
        exported_names(syms, include_str!("export_names/declarations.ms")),
        [
            "Plain", "Opaque", "LOW", "HIGH", "read", "Measure", "native", "Color", "Outcome"
        ]
    );
}

#[test]
fn export_kinds_distinguish_types_from_values_in_complete_and_recovered_source() {
    let syms = ms_syntax::Names::global();
    for (source, expected) in [
        (
            include_str!("export_names/declarations.ms"),
            vec!["Plain", "Opaque", "Measure", "Color", "Outcome"],
        ),
        (
            include_str!("export_names/recovery.ms"),
            vec!["Recovered", "RecoveredEnum"],
        ),
    ] {
        for source in [source.to_string(), source.replace('\n', "\r\n")] {
            let types: Vec<_> = exported_declarations(syms, &source)
                .into_iter()
                .filter(|export| export.is_type)
                .map(|export| export.name)
                .collect();
            assert_eq!(types, expected);
        }
    }
}

#[test]
fn incomplete_neighbors_do_not_hide_valid_exports() {
    let syms = ms_syntax::Names::global();
    assert_eq!(
        exported_names(syms, include_str!("export_names/recovery.ms")),
        ["Recovered", "AFTER", "RecoveredEnum"]
    );
}

#[test]
fn missing_enums_opaque_types_and_grouped_constants_get_import_fixes() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let main = write(dir.path(), "main.ms", "");
    write(
        dir.path(),
        "declarations.ms",
        include_str!("export_names/declarations.ms"),
    );
    for (kind, name) in [
        ("type", "Opaque"),
        ("binding", "LOW"),
        ("binding", "HIGH"),
        ("type", "Color"),
        ("type", "Outcome"),
    ] {
        let mut issues = vec![Diagnostic {
            cause: Default::default(),
            opener_line: 0,
            file: main.as_str().into(),
            pos: Pos::new(0, 1, 1),
            phase: Phase::Resolution,
            message: format!("unknown {kind} {name}; declare or import it"),
            end: None,
            fix: None,
        }];
        suggest_project_imports(syms, &mut issues, dir.path());
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

#[test]
fn a_name_the_file_already_imports_gets_no_import_fix() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    write(
        dir.path(),
        "helpers.ms",
        include_str!("export_names/helpers.ms"),
    );
    let main = write(
        dir.path(),
        "main.ms",
        include_str!("export_names/already_imported.ms"),
    );
    let mut issues = vec![Diagnostic {
        cause: Default::default(),
        opener_line: 0,
        file: main.as_str().into(),
        pos: Pos::new(0, 1, 1),
        phase: Phase::Resolution,
        message: "unknown binding helper; declare or import it".to_string(),
        end: None,
        fix: None,
    }];
    suggest_project_imports(syms, &mut issues, dir.path());
    assert!(issues[0].fix.is_none(), "{:?}", issues[0]);
    assert!(!issues[0].message.contains("add:"), "{}", issues[0].message);
}

#[test]
fn export_lookalikes_in_comments_and_text_declare_nothing() {
    let syms = ms_syntax::Names::global();
    let source = concat!(
        "/*\n",
        "export type CommentedType:\n",
        "    value: Int\n",
        "export enum Commented:\n",
        "    Hidden\n",
        "*/\n",
        "\n",
        "note := \"\"\"\n",
        "export fn quoted() Int: 1\n",
        "export enum Quoted:\n",
        "    Hidden\n",
        "\"\"\"\n",
        "\n",
        "export type Actual:\n",
        "    value: Int\n",
    );
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        assert_eq!(exported_names(syms, &source), ["Actual"]);
    }
}
