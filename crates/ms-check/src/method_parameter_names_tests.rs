//! Fixed type names cannot become method type parameters.

use crate::{CheckOptions, checker::Checker, stdlib::PRIMITIVE_NAMES};
use std::sync::Arc;

const FORMS: [&str; 3] = [
    include_str!("../tests/method_parameter_names/interface.ms"),
    include_str!("../tests/method_parameter_names/implementation.ms"),
    include_str!("../tests/method_parameter_names/inherent.ms"),
];

fn diagnostics(source: &str) -> Vec<String> {
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("method_parameter_names.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    Checker::new(&CheckOptions::default())
        .check_modules(vec![crate::load_module(&module)], None)
        .diagnostics
        .into_iter()
        .map(|d| d.message)
        .collect()
}

#[test]
fn method_type_parameters_reject_every_fixed_type_name() {
    for name in PRIMITIVE_NAMES
        .into_iter()
        .chain(["Equal", "Comparable", "Hashable", "Clonable"])
    {
        for form in FORMS {
            let source = form.replace("PARAMETER", name);
            let got = diagnostics(&source);
            let expected = format!("duplicate or intrinsic type parameter {name};");
            assert!(
                got.iter().any(|d| d.starts_with(&expected)),
                "{source}: {got:?}"
            );
        }
    }
}

#[test]
fn method_type_parameters_preserve_shadowable_names() {
    for name in [
        "T",
        "Error",
        "Optional",
        "Result",
        "List",
        "Map",
        "CollectionError",
    ] {
        for form in FORMS {
            let source = form.replace("PARAMETER", name);
            let got = diagnostics(&source);
            assert!(got.is_empty(), "{source}: {got:?}");
        }
    }
}
