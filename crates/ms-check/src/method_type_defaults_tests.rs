//! Method type defaults complete inference and recorded specialization arguments.

use crate::{CheckOptions, checker::Checker};
use std::sync::Arc;

fn check_defaults_source(source: &str) -> (crate::syntax::ModRef, crate::checker::Program) {
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("invocation_defaults.ms");
    let parsed = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    let module = crate::load_module(&parsed);
    let program = Checker::new(&CheckOptions::default()).check_modules(vec![module.clone()], None);
    (module, program)
}

#[test]
fn invocation_defaults_retain_native_origin_without_granting_permissions() {
    use crate::types::{ParameterDefaults, n};
    let (module, program) = check_defaults_source(
        r#"
fn ordinary(cause: MissingValue? = none) Result[Int, MissingValue]: ok(if cause.is_none(): 7 else: 8)
fn relay[T](value: T) T: value
interface Convert:
    fn convert(cause: MissingValue? = none) Result[Int, MissingValue]
type Source:
    value: Int
impl Convert for Source:
    fn convert(cause: MissingValue?) Result[Int, MissingValue]: ok(if cause.is_none(): self.value else: 8)
impl Source:
    fn ok_or(cause: MissingValue? = none) Result[Int, MissingValue]: ok(if cause.is_none(): self.value else: 8)
fn generic[T](value: T?) Unit:
    let _generic_native = value.ok_or[MissingValue]
fn sample(value: Int?, flag: Bool) Unit:
    let _native = value.ok_or[MissingValue]
    let _alias = _native
    let _nested = fn: _alias()
    let _source = Source(7)
    let _source_method = _source.ok_or
    let _inherited = _source.convert
    let _source_fn = ordinary
    let _source_copy = _source_fn
    let _annotated: fn(MissingValue?) Result[Int, MissingValue] = value.ok_or[MissingValue]
    var _mutable = value.ok_or[MissingValue]
    _mutable = ordinary
    let _forwarded = relay(value.ok_or[MissingValue])
    let _values = [value.ok_or[MissingValue]]
    let _mapping = {"_native": value.ok_or[MissingValue]}
    let _joined = match flag:
        true: value.ok_or[MissingValue]
        false: ordinary
    let _native_join = match flag:
        true: value.ok_or[MissingValue]
        false: value.ok_or[MissingValue]
    let _conditional = if flag: value.ok_or[MissingValue] else: ordinary
"#,
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let facts = module.facts();
    let binding = |name: &str| {
        facts
            .patterns
            .values()
            .find(|b| b.name.as_str().trim_start_matches('_') == name)
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
            .any(|b| { b.name.as_str() == "_alias" && marked(&b.ty) == Some(n("cause")) })
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
    use crate::types::*;
    let cause = n("cause");
    let defaults = ParameterDefaults::new([cause].into_iter().collect());
    let params = vec![Param {
        name: cause,
        ty: primitive("Int"),
    }];
    let plain = function_with(
        params.clone(),
        primitive("Int"),
        Some(std::rc::Rc::new(defaults.clone())),
    );
    let marked = function_with(
        params.clone(),
        primitive("Int"),
        Some(std::rc::Rc::new(defaults.with_missing_value_at_call(cause))),
    );
    assert!(same(&plain, &marked));
    assert_eq!(plain.to_string(), marked.to_string());
    assert_eq!(type_key(&plain), type_key(&marked));
    assert_eq!(lowering_key(&plain), lowering_key(&marked));
    let variable = std::rc::Rc::new(Type::new(n("T"), n("generic.T"), Kind::Variable));
    let generic = function_with(params, variable.clone(), marked.defaults.clone());
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
    let mut wrapper = Type::new(n("Wrapper"), n("Wrapper"), Kind::Record);
    wrapper.args = vec![marked.clone()];
    let nested = function(
        vec![Param {
            name: n("callback"),
            ty: marked.clone(),
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
fn ordinary(cause: MissingValue? = none) Result[Int, MissingValue]: ok(if cause.is_none(): 7 else: 8)
fn relay[T](value: T) T: value
fn sample(flag: Bool) Unit:
    let absent: Int? = none
"#;
    for body in [
        "    var value = absent.ok_or[MissingValue]\n    value = ordinary\n    let result = value()\n",
        "    let value: fn(MissingValue?) Result[Int, MissingValue] = absent.ok_or[MissingValue]\n    let result = value()\n",
        "    let value = relay(absent.ok_or[MissingValue])\n    let result = value()\n",
        "    let factory = fn: absent.ok_or[MissingValue]\n    let value = factory()\n    let result = value()\n",
        "    let values = [absent.ok_or[MissingValue]]\n    let result = values[0]()\n",
        "    let values = {\"native\": absent.ok_or[MissingValue]}\n    let result = values[\"native\"]()\n",
        "    let value = match flag:\n        true: absent.ok_or[MissingValue]\n        false: ordinary\n    let result = value()\n",
        "    let value = match flag:\n        true: ordinary\n        false: absent.ok_or[MissingValue]\n    let result = value()\n",
        "    let value = match flag:\n        true: absent.ok_or[MissingValue]\n        false: absent.ok_or[MissingValue]\n    let result = value()\n",
        "    let value = if flag: absent.ok_or[MissingValue] else: ordinary\n    let result = value()\n",
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
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("method_type_defaults.ms");
    let source = include_str!("../tests/method_type_defaults/accepted.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    let module = crate::load_module(&module);
    let program = Checker::new(&CheckOptions::default()).check_modules(vec![module.clone()], None);
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let facts = module.facts();
    let mut calls = Vec::new();
    for info in facts.exprs.iter().flatten() {
        let Some(method) = &info.method else { continue };
        let Some(name) = method.name() else { continue };
        if info.arguments.is_none()
            || !matches!(name.as_str(), "read" | "choose" | "fallback" | "output")
        {
            continue;
        }
        let args: Vec<_> = info
            .type_args
            .iter()
            .map(|t| t.as_ref().map(ToString::to_string))
            .collect();
        calls.push((name.to_string(), args));
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
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("bound_method_defaults.ms");
    let source = include_str!("../tests/method_type_defaults/bound.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    let module = crate::load_module(&module);
    let program = Checker::new(&CheckOptions::default()).check_modules(vec![module.clone()], None);
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
            .map(|t| t.as_ref().map(ToString::to_string))
            .collect();
        assert_eq!(args, vec![Some("Int".to_string()), Some("Int".to_string())]);
    }
}

#[test]
fn method_type_defaults_reject_unsatisfied_bounds_and_forward_references() {
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
        crate::stdlib::ensure_standard();
        let file: Arc<str> = Arc::from("bad_method_defaults.ms");
        let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
        let program = Checker::new(&CheckOptions::default())
            .check_modules(vec![crate::load_module(&module)], None);
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
