//! Generic operations reject non-interface bounds just like named functions.

use crate::{CheckOptions, Program, checker::Checker, types::n};
use std::sync::Arc;

fn check(source: &str) -> Program {
    let syms = ms_syntax::Names::global();
    let session = crate::Session::new();
    session.ensure_standard();
    let file: Arc<str> = Arc::from("operation_bounds.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    Checker::new(&session, &CheckOptions::default())
        .check_modules(vec![crate::load_module(syms, &module)], None)
}

fn diagnostics(source: &str) -> Vec<String> {
    check(source)
        .diagnostics
        .into_iter()
        .map(|d| d.message)
        .collect()
}

#[test]
fn operations_reject_non_interface_bounds() {
    for source in [
        include_str!("../tests/operation_bounds/interface.ms"),
        include_str!("../tests/operation_bounds/implementation.ms"),
        include_str!("../tests/operation_bounds/inherent.ms"),
    ] {
        let got = diagnostics(source);
        assert!(!got.is_empty(), "accepted non-interface bound: {source}");
        assert!(
            got.iter()
                .all(|d| d.starts_with("a bound must be an interface")),
            "{got:?}"
        );
    }
}

#[test]
fn operations_reject_type_variable_bounds_without_recording_them() {
    let syms = ms_syntax::Names::global();
    let program = check(include_str!("../tests/operation_bounds/variable.ms"));
    assert_eq!(program.diagnostics.len(), 1, "{:?}", program.diagnostics);
    assert!(
        program.diagnostics[0]
            .message
            .contains("resolves to a type parameter")
    );
    let reader = program.symbols[&n("operation_bounds.ms")].borrow()[&n("Reader")].ty(syms);
    let variables = program
        .session
        .operation_variables(&format!("{}/read", syms.str(reader.id)));
    assert_eq!(variables.len(), 1);
    assert!(variables[0].bounds().is_empty());
}

#[test]
fn operations_keep_recursive_and_receiver_dependent_interface_bounds() {
    let got = diagnostics(include_str!("../tests/operation_bounds/valid.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn exported_operations_reject_private_generic_bounds() {
    let program = check(include_str!(
        "../tests/operation_bounds/private_public_bounds.ms"
    ));
    let got = program.diagnostics;
    assert_eq!(got.len(), 4, "{got:?}");
    for (diagnostic, line) in got.iter().zip([4, 7, 13, 16]) {
        assert_eq!(diagnostic.pos.line, line);
        assert_eq!(diagnostic.phase, ms_syntax::Phase::Type);
        assert!(
            diagnostic
                .message
                .starts_with("public signature exposes private type Secret;"),
            "{diagnostic:?}"
        );
    }
}

#[test]
fn operation_bound_visibility_preserves_private_and_public_interfaces() {
    let got = diagnostics(include_str!("../tests/operation_bounds/public_bounds.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn declaration_bounds_resolve_generic_arities_in_either_order() {
    let source = include_str!("../tests/operation_bounds/declaration_order.ms");
    for source in [
        source.to_string(),
        source.rsplit("\n\n").collect::<Vec<_>>().join("\n\n"),
    ] {
        let got = diagnostics(&source);
        assert!(got.is_empty(), "{got:?}");
    }
}

#[test]
fn declaration_bounds_reject_wrong_arities_in_either_order() {
    let source = include_str!("../tests/operation_bounds/declaration_arity.ms");
    for source in [
        source.to_string(),
        source.rsplit("\n\n").collect::<Vec<_>>().join("\n\n"),
    ] {
        let got = diagnostics(&source);
        assert_eq!(got.len(), 4, "{got:?}");
        assert_eq!(
            got.iter()
                .filter(|d| d.starts_with("Reader requires 1 type arguments, found 0;"))
                .count(),
            2,
            "{got:?}"
        );
        assert_eq!(
            got.iter()
                .filter(|d| d.starts_with("Reader requires 1 type arguments, found 2;"))
                .count(),
            2,
            "{got:?}"
        );
    }
}

#[test]
fn grouped_modules_register_generic_arities_before_resolving_bounds() {
    let syms = ms_syntax::Names::global();
    for reversed in [false, true] {
        let session = crate::Session::new();
        session.ensure_standard();
        let mut imports = crate::ImportMap::default();
        let mut modules: Vec<_> = [
            (
                "consumer.ms",
                include_str!("../tests/operation_bounds/group_consumer.ms"),
            ),
            (
                "provider.ms",
                include_str!("../tests/operation_bounds/group_provider.ms"),
            ),
        ]
        .into_iter()
        .map(|(file, source)| {
            let file: Arc<str> = Arc::from(file);
            let parsed = ms_syntax::parser::parse(&file, source).expect("valid fixture");
            for import in &parsed.imports {
                let target = import.path.strip_prefix("./").expect("local import");
                imports.insert(n(&file), import.id, n(target));
            }
            crate::load_module(syms, &parsed)
        })
        .collect();
        if reversed {
            modules.reverse();
        }
        let mut checker = Checker::new(&session, &CheckOptions::default());
        checker.imports = imports;
        checker.group = modules.clone();
        let got = checker.check_modules(modules, None).diagnostics;
        assert!(got.is_empty(), "{got:?}");
    }
}

const RELATION: &str = "interface Relation[T]:
    fn compare(other: T) Int

interface Reader[A]:
    fn read[T: Relation[A]](value: T) Int
";

const USE: &str = "\nfn use_reader[R: Reader[Int]](r: R) Unit:\n    return\n\nfn run(s: Source) Unit:\n    use_reader(s)\n";

#[test]
fn implementations_compare_bounds_after_interface_substitution() {
    for source in [
        // A concrete argument, with the operation parameter renamed.
        "type Source:\n    number: Int\n\nfn Source.read[T: Relation[Int]](value: T) Int:\n    return self.number\n\nfn use_reader[R: Reader[Int]](r: R) Unit:\n    return\n\nfn run(s: Source) Unit:\n    use_reader(s)\n",
        "type Source:\n    number: Int\n\nfn Source.read[U: Relation[Int]](value: U) Int:\n    return self.number\n\nfn use_reader[R: Reader[Int]](r: R) Unit:\n    return\n\nfn run(s: Source) Unit:\n    use_reader(s)\n",
        // A generic receiver passing its own parameter.
        "type Source[B]:\n    number: Int\n\nfn Source[B].read[T: Relation[B]](value: T) Int:\n    return self.number\n",
    ] {
        let got = diagnostics(&format!("{RELATION}\n{source}"));
        assert!(got.is_empty(), "{got:?} for {source}");
    }
}

#[test]
fn implementations_still_reject_mismatched_substituted_bounds() {
    let source = "type Source:\n    number: Int\n\nfn Source.read[T: Relation[String]](value: T) Int:\n    return self.number\n";
    let got = diagnostics(&format!("{RELATION}\n{source}{USE}"));
    assert!(
        got.iter()
            .any(|d| d.contains("Source does not satisfy Reader[Int]")),
        "{got:?}"
    );
}
