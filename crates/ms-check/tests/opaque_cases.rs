//! Unqualified alternative cases obey the same opaque boundary as qualified cases.

use ms_check::types::n;
use ms_check::{CheckOptions, ImportMap};
use ms_syntax::{Diagnostic, Phase};
use std::sync::Arc;

fn diagnostics(file: &str, source: &str) -> Vec<Diagnostic> {
    let sources = [
        ("gate.ms", include_str!("opaque_cases/gate.ms")),
        (file, source),
    ];
    let mut imports = ImportMap::default();
    let modules = sources
        .into_iter()
        .map(|(file, source)| {
            let file: Arc<str> = Arc::from(file);
            let module = ms_syntax::parser::parse(&file, source).expect("fixture parses");
            for import in &module.imports {
                let target = import
                    .path
                    .strip_prefix("./")
                    .expect("local fixture import");
                imports.insert(n(&file), import.id, n(target));
            }
            ms_check::load_module(&module)
        })
        .collect();
    ms_check::check(modules, imports, CheckOptions::default()).diagnostics
}

#[test]
fn imported_opaque_cases_cannot_be_built_without_qualification() {
    for (file, source, name) in [
        (
            "nullary.ms",
            include_str!("opaque_cases/nullary.ms"),
            "Minted",
        ),
        (
            "payload.ms",
            include_str!("opaque_cases/payload.ms"),
            "Labeled",
        ),
    ] {
        let got = diagnostics(file, source);
        assert_eq!(got.len(), 1, "{got:?}");
        assert_eq!(&*got[0].file, file);
        assert_eq!(got[0].phase, Phase::Resolution);
        assert!(
            got[0]
                .message
                .starts_with(&format!("unknown binding {name};")),
            "{:?}",
            got[0]
        );
    }
}

#[test]
fn hidden_opaque_cases_do_not_make_visible_cases_ambiguous() {
    let got = diagnostics("visible.ms", include_str!("opaque_cases/visible.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn qualified_opaque_cases_remain_hidden() {
    let got = diagnostics("qualified.ms", include_str!("opaque_cases/qualified.ms"));
    assert_eq!(got.len(), 1, "{got:?}");
    assert_eq!(got[0].phase, Phase::Type);
    assert!(
        got[0]
            .message
            .starts_with("Token is opaque outside gate.ms:"),
        "{:?}",
        got[0]
    );
}
