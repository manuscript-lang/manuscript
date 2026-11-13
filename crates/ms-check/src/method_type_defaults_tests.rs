//! Method type defaults complete inference and recorded specialization arguments.

use crate::type_keys::{lowering_key, type_key};
use crate::{CheckOptions, checker::Checker};
use std::sync::Arc;

fn check_defaults_source(source: &str) -> (crate::syntax::ModRef, crate::checker::Program) {
    let syms = ms_syntax::Names::global();
    let session = crate::Session::new();
    session.ensure_standard();
    let file: Arc<str> = Arc::from("invocation_defaults.ms");
    let parsed = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    let module = crate::load_module(syms, &parsed);
    let program =
        Checker::new(&session, &CheckOptions::default()).check_modules(vec![module.clone()], None);
    (module, program)
}

#[test]
fn invocation_defaults_retain_native_origin_without_granting_permissions() {
    let syms = ms_syntax::Names::global();
    use crate::types::{ParameterDefaults, n};
    let (module, program) = check_defaults_source(
        r#"
fn ordinary(cause: Error? = none) Result[Int, Error]: ok(if cause.is_none(): 7 else: 8)
fn relay[T](value: T) T: value
interface Convert:
    fn convert(cause: Error? = none) Result[Int, Error]
type Source:
    value: Int
fn Source.convert(cause: Error?) Result[Int, Error]: ok(if cause.is_none(): self.value else: 8)
fn Source.ok_or(cause: Error? = none) Result[Int, Error]: ok(if cause.is_none(): self.value else: 8)
fn generic[T](value: T?) Unit:
    _generic_native := value.ok_or[Error]
fn sample(value: Int?, flag: Bool) Unit:
    _native := value.ok_or[Error]
    _alias := _native
    _nested := fn: _alias()
    _source := Source(7)
    _source_method := _source.ok_or
    _inherited := _source.convert
    _source_fn := ordinary
    _source_copy := _source_fn
    _annotated: fn(Error?) Result[Int, Error] := value.ok_or[Error]
    var _mutable = value.ok_or[Error]
    _mutable = ordinary
    _forwarded := relay(value.ok_or[Error])
    _values := [value.ok_or[Error]]
    _mapping := {"_native": value.ok_or[Error]}
    _joined := match flag:
        true: value.ok_or[Error]
        false: ordinary
    _native_join := match flag:
        true: value.ok_or[Error]
        false: value.ok_or[Error]
    _conditional := if flag: value.ok_or[Error] else: ordinary
"#,
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let facts = module.facts();
    let binding = |name: &str| {
        facts
            .patterns
            .values()
            .find(|b| syms.str(b.name).trim_start_matches('_') == name)
            .unwrap()
            .ty
            .clone()
    };
    let marked =
        |ty: &crate::types::Ty| ty.defaults.as_ref().and_then(|d| d.missing_value_at_call());
    for name in ["native", "alias", "generic_native"] {
        let ty = binding(name);
        assert!(ty.is_default(n("cause")), "{name} lost omission permission");
        assert_eq!(marked(&ty), Some(n("cause")), "{name} lost native origin");
    }
    assert!(
        facts
            .exprs
            .iter()
            .flatten()
            .flat_map(|i| &i.captures)
            .any(|b| { syms.str(b.name) == "_alias" && marked(&b.ty) == Some(n("cause")) })
    );
    for name in ["source_method", "inherited", "source_fn", "source_copy"] {
        let ty = binding(name);
        assert!(
            ty.is_default(n("cause")),
            "{name} lost its ordinary default"
        );
        assert_eq!(marked(&ty), None, "{name} gained native origin");
    }
    for name in [
        "annotated",
        "mutable",
        "forwarded",
        "joined",
        "native_join",
        "conditional",
    ] {
        let ty = binding(name);
        assert!(ty.defaults.is_none(), "{name} retained omission metadata");
    }
    for name in ["values", "mapping"] {
        let ty = binding(name);
        let value = ty.args.last().unwrap();
        assert!(
            value.defaults.is_none(),
            "{name} retained element omission metadata"
        );
    }

    let ordinary = ParameterDefaults::new([n("cause")].into_iter().collect());
    let invalid = ordinary.with_missing_value_at_call(n("unknown"));
    assert_eq!(invalid.missing_value_at_call(), None);
    assert!(!invalid.contains(&n("unknown")));
}

#[test]
fn invocation_default_metadata_survives_substitution_and_erases_recursively() {
    let syms = ms_syntax::Names::global();
    use crate::types::*;
    let cause = n("cause");
    let defaults = ParameterDefaults::new([cause].into_iter().collect());
    let params = vec![Param {
        name: cause,
        ty: primitive("Int"),
        mutable: false,
        positional: false,
    }];
    let plain = function_with(
        syms,
        params.clone(),
        primitive("Int"),
        Some(std::rc::Rc::new(defaults.clone())),
    );
    let marked = function_with(
        syms,
        params.clone(),
        primitive("Int"),
        Some(std::rc::Rc::new(defaults.with_missing_value_at_call(cause))),
    );
    assert!(same(&plain, &marked));
    assert_eq!(
        plain.display(syms).to_string(),
        marked.display(syms).to_string()
    );
    assert_eq!(type_key(syms, &plain), type_key(syms, &marked));
    assert_eq!(lowering_key(syms, &plain), lowering_key(syms, &marked));
    let variable = std::rc::Rc::new(Type::new(syms, n("T"), n("generic.T"), Kind::Variable));
    let generic = function_with(syms, params, variable.clone(), marked.defaults.clone());
    let bindings = [(variable.id, primitive("Int"))].into_iter().collect();
    let substituted = sub(&generic, &bindings);
    assert!(same(&substituted.result_ty(), &primitive("Int")));
    assert_eq!(
        substituted
            .defaults
            .as_ref()
            .unwrap()
            .missing_value_at_call(),
        Some(cause)
    );
    let mut wrapper = Type::new(syms, n("Wrapper"), n("Wrapper"), Kind::Type);
    wrapper.args = vec![marked.clone()];
    let nested = function(
        syms,
        vec![Param {
            name: n("callback"),
            ty: marked.clone(),
            mutable: false,
            positional: false,
        }],
        std::rc::Rc::new(wrapper),
    );
    let required = required_type(&nested);
    assert!(required.params[0].ty.defaults.is_none());
    assert!(required.result_ty().args[0].defaults.is_none());
    assert!(required_type(&marked).defaults.is_none());
}

#[test]
fn invocation_defaults_do_not_survive_callable_erasure_or_joins() {
    let prefix = r#"
fn ordinary(cause: Error? = none) Result[Int, Error]: ok(if cause.is_none(): 7 else: 8)
fn relay[T](value: T) T: value
fn sample(flag: Bool) Unit:
    absent: Int? := none
"#;
    for body in [
        "    var value = absent.ok_or[Error]\n    value = ordinary\n    result := value()\n",
        "    value: fn(Error?) Result[Int, Error] := absent.ok_or[Error]\n    result := value()\n",
        "    value := relay(absent.ok_or[Error])\n    result := value()\n",
        "    factory := fn: absent.ok_or[Error]\n    value := factory()\n    result := value()\n",
        "    values := [absent.ok_or[Error]]\n    result := values[0]()\n",
        "    values := {\"native\": absent.ok_or[Error]}\n    result := values[\"native\"]()\n",
        "    value := match flag:\n        true: absent.ok_or[Error]\n        false: ordinary\n    result := value()\n",
        "    value := match flag:\n        true: ordinary\n        false: absent.ok_or[Error]\n    result := value()\n",
        "    value := match flag:\n        true: absent.ok_or[Error]\n        false: absent.ok_or[Error]\n    result := value()\n",
        "    value := if flag: absent.ok_or[Error] else: ordinary\n    result := value()\n",
    ] {
        let (_, program) = check_defaults_source(&format!("{prefix}{body}"));
        assert!(
            program
                .diagnostics
                .iter()
                .any(|d| d.message.starts_with("missing argument")),
            "{body}\n{:?}",
            program.diagnostics
        );
    }
}

#[test]
fn method_defaults_fill_only_missing_type_arguments() {
    let syms = ms_syntax::Names::global();
    let session = crate::Session::new();
    session.ensure_standard();
    let file: Arc<str> = Arc::from("method_type_defaults.ms");
    let source = include_str!("../tests/method_type_defaults/accepted.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    let module = crate::load_module(syms, &module);
    let program =
        Checker::new(&session, &CheckOptions::default()).check_modules(vec![module.clone()], None);
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let facts = module.facts();
    let mut calls = Vec::new();
    for info in facts.exprs.iter().flatten() {
        let Some(method) = &info.method else { continue };
        let Some(name) = method.name() else { continue };
        if info.arguments.is_none()
            || !matches!(syms.str(name), "read" | "choose" | "fallback" | "output")
        {
            continue;
        }
        let args: Vec<_> = info
            .type_args
            .iter()
            .map(|t| t.as_ref().map(|x| x.display(syms).to_string()))
            .collect();
        calls.push((syms.str(name).to_string(), args));
    }
    calls.sort();
    assert_eq!(
        calls,
        vec![
            (
                "choose".to_string(),
                vec![Some("Int".to_string()), Some("Int".to_string())]
            ),
            (
                "choose".to_string(),
                vec![Some("Int".to_string()), Some("String".to_string())]
            ),
            ("fallback".to_string(), vec![Some("Int".to_string())]),
            ("output".to_string(), vec![Some("String".to_string())]),
            ("read".to_string(), vec![Some("Int".to_string())]),
            ("read".to_string(), vec![Some("Int".to_string())]),
            ("read".to_string(), vec![Some("String".to_string())]),
        ]
    );
}

#[test]
fn bound_method_partial_specialization_records_completed_arguments() {
    let syms = ms_syntax::Names::global();
    let session = crate::Session::new();
    session.ensure_standard();
    let file: Arc<str> = Arc::from("bound_method_defaults.ms");
    let source = include_str!("../tests/method_type_defaults/bound.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    let module = crate::load_module(syms, &module);
    let program =
        Checker::new(&session, &CheckOptions::default()).check_modules(vec![module.clone()], None);
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let facts = module.facts();
    let applications: Vec<_> = facts
        .exprs
        .iter()
        .flatten()
        .filter(|i| !i.type_args.is_empty())
        .collect();
    assert!(
        !applications.is_empty(),
        "bound specialization has no recorded type arguments"
    );
    for info in applications {
        let args: Vec<_> = info
            .type_args
            .iter()
            .map(|t| t.as_ref().map(|x| x.display(syms).to_string()))
            .collect();
        assert_eq!(args, vec![Some("Int".to_string()), Some("Int".to_string())]);
    }
}

#[test]
fn method_type_defaults_reject_unsatisfied_bounds_and_forward_references() {
    let syms = ms_syntax::Names::global();
    for (source, expected) in [
        (
            include_str!("../tests/method_type_defaults/bad_bound.ms"),
            "does not satisfy Hashable",
        ),
        (
            include_str!("../tests/method_type_defaults/forward.ms"),
            "unknown type U",
        ),
    ] {
        let session = crate::Session::new();
        session.ensure_standard();
        let file: Arc<str> = Arc::from("bad_method_defaults.ms");
        let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
        let program = Checker::new(&session, &CheckOptions::default())
            .check_modules(vec![crate::load_module(syms, &module)], None);
        assert!(
            program
                .diagnostics
                .iter()
                .any(|d| d.message.contains(expected)),
            "{:?}",
            program.diagnostics
        );
    }
}
