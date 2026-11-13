use ms_syntax::ast::DeclKind;
use ms_syntax::{format, parse_partial};
use std::sync::Arc;

#[test]
fn enum_declarations_preserve_forms_and_formatting() {
    let file = Arc::from("enum.ms");
    for ending in ["\n", "\r\n"] {
        let source = include_str!("data/enums/accepted.ms").replace('\n', ending);
        let module = ms_syntax::parser::parse(&file, &source).unwrap();
        assert!(matches!(module.decls[0].kind, DeclKind::Type(_)));
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
fn legacy_type_and_enum_syntax_is_rejected_without_automatic_fixes() {
    let file = Arc::from("legacy.ms");
    for (source, cause) in [
        (
            include_str!("data/enums/legacy.ms"),
            "a type declared with 'type' cannot contain enum variants;",
        ),
        (
            include_str!("data/enums/legacy-enum.ms"),
            "enum variants do not use 'case';",
        ),
    ] {
        for ending in ["\n", "\r\n"] {
            let diagnostic =
                ms_syntax::parser::parse(&file, &source.replace('\n', ending)).unwrap_err();
            assert!(diagnostic.message.starts_with(cause), "{diagnostic:?}");
            assert!(diagnostic.fix.is_none());
        }
    }
}

#[test]
fn enum_members_require_cases() {
    let file = Arc::from("wrong.ms");
    for (source, cause) in [
        (
            include_str!("data/enums/fields.ms"),
            "enum variants have no field or method bodies;",
        ),
        (
            include_str!("data/enums/method.ms"),
            "an enum contains only variants;",
        ),
        (
            include_str!("data/enums/ellipsis.ms"),
            "an enum must declare at least one variant;",
        ),
        (
            include_str!("data/enums/empty.ms"),
            "an enum must declare at least one variant;",
        ),
        (
            include_str!("data/enums/default.ms"),
            "enum variants cannot have defaults;",
        ),
        (
            include_str!("data/enums/payload-default.ms"),
            "function types and case payloads cannot have defaults;",
        ),
        (
            include_str!("data/enums/method-body.ms"),
            "enum variants have no field or method bodies;",
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

#[test]
fn misplaced_opaque_enum_keeps_enum_in_the_remedy() {
    let file = Arc::from("modifiers.ms");
    let diagnostic =
        ms_syntax::parser::parse(&file, include_str!("data/enums/modifier-order.ms")).unwrap_err();
    assert_eq!(
        diagnostic.message,
        "misplaced 'opaque'; write 'export opaque enum Name:', with export first"
    );
}

#[test]
fn case_is_not_a_reserved_word() {
    assert_eq!(
        ms_syntax::token::Tok::from_word("case"),
        ms_syntax::token::Tok::Name
    );
    assert!(!ms_syntax::token::KEYWORDS.contains(&"case"));
    let file = Arc::from("identifiers.ms");
    assert!(
        ms_syntax::parser::parse(
            &file,
            include_str!("../../../tests/conformance/fixtures/e2e/accept/case-identifier.ms")
        )
        .is_ok()
    );
}
