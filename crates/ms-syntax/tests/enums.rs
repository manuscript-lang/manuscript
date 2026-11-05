use ms_syntax::ast::DeclKind;
use ms_syntax::{format, parse_partial};
use std::sync::Arc;

#[test]
fn enum_declarations_preserve_forms_and_formatting() {
    let file = Arc::from("enum.ms");
    for ending in ["\n", "\r\n"] {
        let source = include_str!("data/enums/accepted.ms").replace('\n', ending);
        let module = ms_syntax::parser::parse(&file, &source).unwrap();
        assert!(matches!(module.decls[0].kind, DeclKind::Record(_)));
        let DeclKind::Alternative(outcome) = &module.decls[1].kind else {
            panic!("expected enum");
        };
        assert_eq!(outcome.cases.len(), 2);
        assert_eq!(outcome.type_params.len(), 1);
        assert_eq!(outcome.cases[0].fields.len(), 1);
        assert!(outcome.cases[1].fields.is_empty());
        for decl in &module.decls[2..] {
            let DeclKind::Alternative(hidden) = &decl.kind else {
                panic!("expected opaque enum");
            };
            assert!(hidden.opaque);
        }
        assert!(module.decls[2].export);
        let formatted = format(&file, &source).unwrap();
        assert_eq!(format(&file, &formatted).unwrap(), formatted);
        assert!(formatted.contains("export opaque enum Hidden:"));
    }
}

#[test]
fn legacy_cases_have_an_exact_keyword_fix() {
    let file = Arc::from("legacy.ms");
    let source = include_str!("data/enums/legacy.ms");
    let diagnostic = ms_syntax::parser::parse(&file, source).unwrap_err();
    assert!(
        diagnostic
            .message
            .starts_with("a record declared with 'type' cannot contain cases;")
    );
    let fix = diagnostic.fix.unwrap();
    assert_eq!(
        &source[fix.pos.offset as usize..fix.end.offset as usize],
        "type"
    );
    assert_eq!(fix.replacement, "enum");
    let mut repaired = source.to_string();
    repaired.replace_range(
        fix.pos.offset as usize..fix.end.offset as usize,
        &fix.replacement,
    );
    assert!(ms_syntax::parser::parse(&file, &repaired).is_ok());
}

#[test]
fn enum_members_require_cases() {
    let file = Arc::from("wrong.ms");
    for (source, cause) in [
        (
            include_str!("data/enums/fields.ms"),
            "an enum contains only cases;",
        ),
        (
            include_str!("data/enums/method.ms"),
            "an enum contains only cases;",
        ),
        (
            include_str!("data/enums/ellipsis.ms"),
            "an enum must declare at least one case;",
        ),
        (
            include_str!("data/enums/empty.ms"),
            "an enum must declare at least one case;",
        ),
    ] {
        let diagnostic = ms_syntax::parser::parse(&file, source).unwrap_err();
        assert!(diagnostic.message.starts_with(cause), "{:?}", diagnostic);
    }
}

#[test]
fn incomplete_enum_names_are_retained_during_recovery() {
    let file = Arc::from("incomplete.ms");
    let (module, diagnostics) = parse_partial(&file, include_str!("data/enums/incomplete.ms"));
    assert!(!diagnostics.is_empty());
    assert!(module.omitted.iter().any(|name| name == "Broken"));
}

#[test]
fn foreign_union_remedy_uses_enum_and_enum_is_reserved() {
    let file = Arc::from("foreign.ms");
    let source = include_str!("data/enums/foreign.ms");
    let diagnostic = ms_syntax::parser::parse(&file, source).unwrap_err();
    assert!(
        diagnostic
            .message
            .contains("declare an enum with 'enum Name:'")
    );
    assert_eq!(diagnostic.fix.unwrap().replacement, "enum");
    let diagnostic =
        ms_syntax::parser::parse(&file, include_str!("data/enums/reserved.ms")).unwrap_err();
    assert!(diagnostic.message.contains("'enum' is a reserved word"));
}
