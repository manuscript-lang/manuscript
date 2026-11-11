use ms_syntax::ast::DeclKind;
use ms_syntax::format;
use std::sync::Arc;

const ACCEPTED: &str = include_str!("data/receiver_methods/accepted.ms");

#[test]
fn receiver_methods_parse_as_own_methods() {
    let file = Arc::from("receiver.ms");
    let module = ms_syntax::parser::parse(&file, ACCEPTED).unwrap();
    let DeclKind::Impl(get) = &module.decls[1].kind else {
        panic!("expected a receiver method");
    };
    assert!(get.contract.is_none());
    assert_eq!(get.methods.len(), 1);
    assert!(!get.methods[0].mutating);
    let DeclKind::Impl(close) = &module.decls[2].kind else {
        panic!("expected a receiver method");
    };
    assert!(close.methods[0].mutating);
    assert!(matches!(module.decls[3].kind, DeclKind::Fn(_)));
    let formatted = format(&file, ACCEPTED).unwrap();
    assert_eq!(format(&file, &formatted).unwrap(), formatted);
}

#[test]
fn an_exported_receiver_method_is_rejected() {
    let file = Arc::from("receiver.ms");
    let source = include_str!("data/receiver_methods/exported.ms");
    assert!(ms_syntax::parser::parse(&file, source).is_err());
}

#[test]
fn a_plain_receiver_name_is_not_a_qualified_type() {
    let file = Arc::from("receiver.ms");
    let source = include_str!("data/receiver_methods/plain_receiver.ms");
    let module = ms_syntax::parser::parse(&file, source).unwrap();
    assert!(matches!(module.decls[1].kind, DeclKind::Impl(_)));
}
