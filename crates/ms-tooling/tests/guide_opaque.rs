//! Public discovery must respect opaque structure while preserving callable operations.

use ms_check::types::n;
use ms_tooling::guide::docgen::{render_module, render_site_module, to_json};
use ms_tooling::guide::{ApiDeclaration, ApiModule, module_documentation};
use std::sync::Arc;

fn modules() -> Vec<ApiModule> {
    let sources = [
        ("types.ms", include_str!("guide_testdata/opaque/types.ms")),
        (
            "consumer.ms",
            include_str!("guide_testdata/opaque/consumer.ms"),
        ),
    ];
    let mut imports = ms_check::ImportMap::default();
    let modules = sources
        .iter()
        .map(|(file, source)| {
            let file: Arc<str> = Arc::from(*file);
            let parsed = ms_syntax::parser::parse(&file, source).unwrap();
            for import in &parsed.imports {
                imports.insert(
                    n(&file),
                    import.id,
                    n(import.path.strip_prefix("./").unwrap()),
                );
            }
            ms_check::load_module(&parsed)
        })
        .collect();
    let mut program = ms_check::check(modules, imports, ms_check::CheckOptions::default());
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    program.methods.extend(program.methods.clone());
    module_documentation(&program)
}

fn declaration<'a>(module: &'a ApiModule, name: &str) -> &'a ApiDeclaration {
    module
        .declarations
        .iter()
        .find(|declaration| declaration.name == name)
        .unwrap()
}

#[test]
fn opaque_records_and_alternatives_hide_structure_in_every_public_format() {
    let modules = modules();
    let module = modules
        .iter()
        .find(|module| module.path == "types.ms")
        .unwrap();
    for name in ["Sealed", "Token"] {
        let declaration = declaration(module, name);
        assert_eq!(declaration.kind, "opaque");
        assert!(
            declaration
                .declaration
                .starts_with(&format!("opaque type {name}"))
        );
        assert!(declaration.fields.is_empty());
        assert!(declaration.cases.is_empty());
        assert!(
            declaration
                .members
                .iter()
                .all(|member| member.kind == "operation")
        );
    }
    for output in [
        render_module(module),
        render_site_module(module),
        to_json(std::slice::from_ref(module)),
    ] {
        for hidden in ["secret_value", "secret_payload", "Minted", "Labeled"] {
            assert!(!output.contains(hidden), "hidden {hidden}: {output}");
        }
    }
    assert!(render_module(module).contains("**Opaque type**"));
    assert!(render_site_module(module).contains("data-api-kind=\"Opaque type\""));
    assert!(to_json(std::slice::from_ref(module)).contains("\"kind\": \"opaque\""));
}

#[test]
fn opaque_methods_keep_defaults_bounds_and_single_source_identity() {
    let modules = modules();
    let module = modules
        .iter()
        .find(|module| module.path == "types.ms")
        .unwrap();
    let sealed = declaration(module, "Sealed");
    assert_eq!(sealed.parameters, ["T"]);
    assert_eq!(sealed.members.len(), 2);
    for (name, signature) in [
        (
            "accepts",
            "# Receiver: Sealed[T]\nfn accepts(flag: Bool = true) Bool:",
        ),
        (
            "precedes",
            "# Receiver: Sealed[T]; T: Comparable\nfn precedes(other: T) Bool:",
        ),
    ] {
        let members: Vec<_> = sealed
            .members
            .iter()
            .filter(|member| member.name == name)
            .collect();
        assert_eq!(members.len(), 1, "{members:?}");
        assert_eq!(members[0].signature, signature);
        assert!(!members[0].doc.is_empty());
    }
    let token = declaration(module, "Token");
    assert_eq!(token.members.len(), 1);
    assert_eq!(token.members[0].signature, "fn valid() Bool:");
}

#[test]
fn ordinary_records_and_alternatives_keep_their_public_construction_surface() {
    let modules = modules();
    let module = modules
        .iter()
        .find(|module| module.path == "types.ms")
        .unwrap();
    let plain = declaration(module, "Plain");
    assert_eq!(plain.kind, "record");
    assert_eq!(plain.fields, ["visible: Int"]);
    assert!(plain.declaration.contains("visible: Int = 3"));
    assert!(
        plain
            .members
            .iter()
            .any(|member| member.kind == "field" && member.name == "visible")
    );
    let choice = declaration(module, "Choice");
    assert_eq!(choice.kind, "alternative");
    assert_eq!(choice.cases, ["Vacant", "Filled(payload: Int)"]);
    for (kind, name) in [
        ("case", "Vacant"),
        ("case", "Filled"),
        ("field", "Filled.payload"),
    ] {
        assert!(
            choice
                .members
                .iter()
                .any(|member| member.kind == kind && member.name == name)
        );
    }
}
